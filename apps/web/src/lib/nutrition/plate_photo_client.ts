// Network glue for the plate-photo logger on /nutrition/log (decisions
// § 1972). It shrinks the chosen picture in the browser, posts it to
// /api/coach/plate-photo and resolves to the validated estimate the runner
// then reviews and edits. Nothing is saved here: the page writes food_log rows
// only for the items the runner keeps.
//
// The manual composer is the fallback, so every non-200 throws a typed
// `PlatePhotoError`. Refreshes the JWT once on a 401, like the other coach
// sub-path clients.

import { supabase } from '../core/supabase';
import { payloadSha256Hex } from '../util/payload_hash';
import type { PlateEstimate } from './plate_photo/estimate';
import {
	PLATE_UPLOAD_JPEG_QUALITY,
	PlatePhotoError,
	platePhotoErrorKind,
	uploadScale,
} from './plate_photo/upload';

export type { PlateEstimate, PlateItem } from './plate_photo/estimate';
export { PlatePhotoError, type PlatePhotoErrorKind } from './plate_photo/upload';

/// Re-encode the picture as a JPEG no larger than the upload size. Drawing to
/// a canvas drops every metadata block (the server strips again regardless),
/// and `imageOrientation: 'from-image'` keeps a portrait phone shot upright.
export async function encodeForUpload(file: Blob): Promise<{ base64: string; mediaType: 'image/jpeg' }> {
	const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
	try {
		const scale = uploadScale(bitmap.width, bitmap.height);
		const w = Math.max(1, Math.round(bitmap.width * scale));
		const h = Math.max(1, Math.round(bitmap.height * scale));
		const canvas = document.createElement('canvas');
		canvas.width = w;
		canvas.height = h;
		const ctx = canvas.getContext('2d');
		if (!ctx) throw new PlatePhotoError('invalid');
		ctx.drawImage(bitmap, 0, 0, w, h);
		const blob = await new Promise<Blob | null>((resolve) =>
			canvas.toBlob(resolve, 'image/jpeg', PLATE_UPLOAD_JPEG_QUALITY),
		);
		if (!blob) throw new PlatePhotoError('invalid');
		const bytes = new Uint8Array(await blob.arrayBuffer());
		let binary = '';
		for (let i = 0; i < bytes.length; i += 0x8000) {
			binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
		}
		return { base64: btoa(binary), mediaType: 'image/jpeg' };
	} finally {
		bitmap.close();
	}
}

export async function requestPlateEstimate(file: Blob, note: string): Promise<PlateEstimate> {
	const image = await encodeForUpload(file);
	const body = JSON.stringify({ image: image.base64, media_type: image.mediaType, note });
	// CloudFront's Lambda OAC can't hash the body itself — the client supplies
	// the sigv4 payload hash or the Function URL 403s (#590).
	const bodyHash = await payloadSha256Hex(body);
	const post = (token: string) =>
		fetch('/api/coach/plate-photo', {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				'X-Supabase-Authorization': `Bearer ${token}`,
				'x-amz-content-sha256': bodyHash,
			},
			body,
		});

	let token = (await supabase.auth.getSession()).data.session?.access_token;
	if (!token) throw new PlatePhotoError('not_authenticated');

	let res = await post(token);
	if (res.status === 401) {
		try {
			const refreshed = await supabase.auth.refreshSession();
			token = refreshed.data.session?.access_token ?? token;
			res = await post(token);
		} catch (_) {
			/* fall through to the status check below */
		}
	}

	if (!res.ok) {
		const errBody = (await res.json().catch(() => null)) as { code?: unknown; upgrade?: unknown } | null;
		throw new PlatePhotoError(platePhotoErrorKind(res.status, errBody));
	}
	const data = (await res.json().catch(() => null)) as PlateEstimate | null;
	if (!data || !Array.isArray(data.items)) throw new PlatePhotoError('unavailable');
	return data;
}
