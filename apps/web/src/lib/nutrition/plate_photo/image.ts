// The photo half of the plate-photo request (decisions § 1972). The image
// arrives in the request body, is checked, stripped of metadata, forwarded to
// the model once and dropped: nothing is written to Storage, so there is no
// bucket policy to get wrong and no stored original to EXIF-strip after the
// fact (§ 576's worker exists for stored photos). The strip here is the same
// lossless marker / chunk walk the upload paths use, run on the server so a
// client that skipped its own re-encode still never ships a GPS tag to the
// sub-processor.

import { stripImageExif } from '../../util/exif_strip';

export type PlateImageType = 'image/jpeg' | 'image/png' | 'image/webp';
export const PLATE_IMAGE_TYPES: readonly PlateImageType[] = ['image/jpeg', 'image/png', 'image/webp'];

/// Decoded-byte ceiling. The client downscales to a 1568 px long edge first
/// (the size the model reads at anyway), which lands well under 1 MB; this
/// bound is for a client that did not, and sits under the provider's 5 MB
/// per-image limit.
export const MAX_PLATE_IMAGE_BYTES = 3 * 1024 * 1024;

/// Smallest buffer that can hold a real image header; anything shorter is junk.
const MIN_PLATE_IMAGE_BYTES = 64;

export type PlateImageResult =
	| { ok: true; mediaType: PlateImageType; base64: string; bytes: number }
	| { ok: false; reason: 'type' | 'encoding' | 'size' | 'mismatch' };

const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

/// The format the bytes actually are, from the magic number.
export function sniffImageType(b: Uint8Array): PlateImageType | null {
	if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
	if (
		b.length >= 8 &&
		b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 &&
		b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a
	) {
		return 'image/png';
	}
	if (
		b.length >= 12 &&
		b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
		b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50
	) {
		return 'image/webp';
	}
	return null;
}

/// Validate the declared type, decode, check size and magic number agree, and
/// strip metadata. Fails closed on every mismatch: an image whose bytes are
/// not the type it claims is refused rather than forwarded under either name.
export function preparePlateImage(rawBase64: unknown, rawType: unknown): PlateImageResult {
	if (!PLATE_IMAGE_TYPES.includes(rawType as PlateImageType)) return { ok: false, reason: 'type' };
	const declared = rawType as PlateImageType;
	if (typeof rawBase64 !== 'string') return { ok: false, reason: 'encoding' };
	const text = rawBase64.replace(/^data:[^,]*,/, '');
	if (text.length === 0 || text.length % 4 !== 0 || !BASE64.test(text)) {
		return { ok: false, reason: 'encoding' };
	}
	if ((text.length / 4) * 3 > MAX_PLATE_IMAGE_BYTES + 2) return { ok: false, reason: 'size' };
	const bytes = new Uint8Array(Buffer.from(text, 'base64'));
	if (bytes.length < MIN_PLATE_IMAGE_BYTES || bytes.length > MAX_PLATE_IMAGE_BYTES) {
		return { ok: false, reason: 'size' };
	}
	if (sniffImageType(bytes) !== declared) return { ok: false, reason: 'mismatch' };
	const stripped = stripImageExif(bytes, declared);
	return {
		ok: true,
		mediaType: declared,
		base64: Buffer.from(stripped).toString('base64'),
		bytes: stripped.length,
	};
}
