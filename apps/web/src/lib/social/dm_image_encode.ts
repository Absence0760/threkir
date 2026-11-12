// Re-encodes a picked photo for a direct message in the browser (issue #1216).
// Drawing to a canvas keeps pixels only, so the camera's EXIF / XMP block,
// GPS position included, never leaves the device; `imageOrientation:
// 'from-image'` bakes the orientation tag into the pixels first so a portrait
// shot stays upright, and transparency is flattened onto white (a JPEG has
// none; mobile's dm_image_encode.dart does the same). Only a JPEG, PNG or
// WebP is taken, judged by its bytes rather than its name, as on mobile: a
// browser would decode a GIF or BMP too. The server re-encodes again before
// anyone reads it.

import { detectImageMime } from '../util/exif_strip';
import { DM_IMAGE_CONTENT_TYPE, DM_IMAGE_MAX_BYTES, DM_IMAGE_QUALITY, dmImageFit } from './dm_image';

/** The JPEG qualities tried in turn until the photo fits; mobile's `kDmImageQualitySteps`. */
export const DM_IMAGE_QUALITY_STEPS = [DM_IMAGE_QUALITY, 0.7, 0.55] as const;

export class DmImageEncodeError extends Error {
	constructor(readonly kind: 'unreadable' | 'too_large') {
		super(`dm image: ${kind}`);
	}
}

export async function encodeDmImage(file: Blob): Promise<Blob> {
	if (detectImageMime(new Uint8Array(await file.slice(0, 12).arrayBuffer())) === null) {
		throw new DmImageEncodeError('unreadable');
	}
	let bitmap: ImageBitmap;
	try {
		bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
	} catch {
		throw new DmImageEncodeError('unreadable');
	}
	try {
		const { width, height } = dmImageFit(bitmap.width, bitmap.height);
		if (width === 0 || height === 0) throw new DmImageEncodeError('unreadable');
		const canvas = document.createElement('canvas');
		canvas.width = width;
		canvas.height = height;
		const ctx = canvas.getContext('2d');
		if (!ctx) throw new DmImageEncodeError('unreadable');
		ctx.fillStyle = '#fff';
		ctx.fillRect(0, 0, width, height);
		ctx.drawImage(bitmap, 0, 0, width, height);
		for (const quality of DM_IMAGE_QUALITY_STEPS) {
			const blob = await new Promise<Blob | null>((resolve) =>
				canvas.toBlob(resolve, DM_IMAGE_CONTENT_TYPE, quality),
			);
			if (!blob) throw new DmImageEncodeError('unreadable');
			if (blob.size <= DM_IMAGE_MAX_BYTES) return blob;
		}
		throw new DmImageEncodeError('too_large');
	} finally {
		bitmap.close();
	}
}
