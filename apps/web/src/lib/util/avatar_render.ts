import { cropRect, outputSize, rotatedSize, type CropState } from './avatar_crop';

/// The largest source file the crop step will decode. The upload itself is a
/// re-encoded square of at most AVATAR_OUTPUT_MAX_PX, far below the bucket's
/// 2 MB limit, so this bounds decode memory rather than storage.
export const AVATAR_SOURCE_MAX_BYTES = 20 * 1024 * 1024;

export const AVATAR_OUTPUT_MIME = 'image/jpeg';
const AVATAR_OUTPUT_QUALITY = 0.9;

export type AvatarSource = ImageBitmap | HTMLImageElement;

export function sourceSize(source: AvatarSource): { width: number; height: number } {
	return source instanceof HTMLImageElement
		? { width: source.naturalWidth, height: source.naturalHeight }
		: { width: source.width, height: source.height };
}

/// Decode with EXIF orientation applied, so a phone photo stored sideways with
/// an Orientation tag arrives upright. The upload is re-encoded from these
/// pixels and carries no EXIF, so the orientation has to be baked in here or
/// it is lost. The <img> fallback is for engines without createImageBitmap
/// options; every current engine also honours orientation for an <img>.
export async function loadOrientedImage(file: Blob): Promise<AvatarSource> {
	if (typeof createImageBitmap === 'function') {
		try {
			return await createImageBitmap(file, { imageOrientation: 'from-image' });
		} catch (err) {
			console.warn('createImageBitmap failed, falling back to <img>', err);
		}
	}
	const url = URL.createObjectURL(file);
	try {
		const img = new Image();
		img.decoding = 'async';
		img.src = url;
		await img.decode();
		return img;
	} finally {
		URL.revokeObjectURL(url);
	}
}

/// Paint the crop the state describes into a `px`-square target. Used for both
/// the on-screen preview and the upload, so what the user sees is what lands.
/// A white ground under the image keeps a transparent PNG from encoding black.
export function drawAvatarCrop(
	ctx: CanvasRenderingContext2D,
	source: AvatarSource,
	state: CropState,
	px: number,
): void {
	const { width, height } = sourceSize(source);
	const rect = cropRect(state);
	const rotated = rotatedSize(width, height, state.quarterTurns);
	ctx.save();
	ctx.setTransform(1, 0, 0, 1, 0, 0);
	ctx.fillStyle = '#fff';
	ctx.fillRect(0, 0, px, px);
	ctx.imageSmoothingEnabled = true;
	ctx.imageSmoothingQuality = 'high';
	const k = px / rect.size;
	ctx.scale(k, k);
	ctx.translate(-rect.x, -rect.y);
	ctx.translate(rotated.width / 2, rotated.height / 2);
	ctx.rotate((state.quarterTurns * Math.PI) / 2);
	ctx.drawImage(source, -width / 2, -height / 2);
	ctx.restore();
}

export async function encodeAvatarCrop(source: AvatarSource, state: CropState): Promise<File> {
	const px = outputSize(cropRect(state).size);
	const canvas = document.createElement('canvas');
	canvas.width = px;
	canvas.height = px;
	const ctx = canvas.getContext('2d');
	if (!ctx) throw new Error('Canvas unavailable');
	drawAvatarCrop(ctx, source, state, px);
	const blob = await new Promise<Blob | null>((resolve) =>
		canvas.toBlob(resolve, AVATAR_OUTPUT_MIME, AVATAR_OUTPUT_QUALITY),
	);
	if (!blob) throw new Error('Could not encode the photo');
	return new File([blob], 'avatar.jpg', { type: AVATAR_OUTPUT_MIME });
}
