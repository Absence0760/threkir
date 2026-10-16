// The pure half of the plate-photo client: the upload sizing and the
// status-to-state mapping, kept free of the Supabase client so they are
// unit-testable.

import { AI_DISCLOSURE_ERROR } from '../../core/ai_disclosure';

/// The long edge the model reads at; anything larger is resized server-side by
/// the provider anyway, so sending more only costs upload time.
export const PLATE_UPLOAD_LONG_EDGE_PX = 1568;
export const PLATE_UPLOAD_JPEG_QUALITY = 0.85;

/// The optional free-text hint ("half portion", "no dressing"). The only text
/// the runner types into the prompt; the server truncates rather than rejects.
export const MAX_PLATE_NOTE_CHARS = 200;

export type PlatePhotoErrorKind =
	| 'not_authenticated'
	| 'consent'
	| 'pro_required'
	| 'rate_limited'
	| 'invalid'
	| 'not_understood'
	| 'unavailable';

export class PlatePhotoError extends Error {
	kind: PlatePhotoErrorKind;
	constructor(kind: PlatePhotoErrorKind, message?: string) {
		super(message ?? kind);
		this.name = 'PlatePhotoError';
		this.kind = kind;
	}
}

export function platePhotoErrorKind(
	status: number,
	body: { code?: unknown; upgrade?: unknown } | null,
): PlatePhotoErrorKind {
	if (status === 401) return 'not_authenticated';
	if (status === 403 && body?.code === AI_DISCLOSURE_ERROR) return 'consent';
	if (status === 403 && body?.upgrade === true) return 'pro_required';
	if (status === 429) return 'rate_limited';
	if (status === 400 || status === 413) return 'invalid';
	if (status === 422) return 'not_understood';
	return 'unavailable';
}

/// The long-edge scale that fits `w`×`h` inside the upload size. Never
/// enlarges.
export function uploadScale(w: number, h: number, longEdge = PLATE_UPLOAD_LONG_EDGE_PX): number {
	const edge = Math.max(w, h);
	if (!Number.isFinite(edge) || edge <= 0) return 1;
	return Math.min(1, longEdge / edge);
}
