/**
 * Photos in a direct message (issue #1216, migration 20271213121604).
 *
 * The client re-encodes a picked photo to a JPEG no larger than
 * `DM_IMAGE_MAX_EDGE` on its long edge before upload, which drops the
 * camera's metadata; the server re-encodes it again and shows only its own
 * copy. These limits mirror the bucket and the worker, and dm_image.test.ts
 * reads them out of the migration. Mobile twin: `dm_image.dart`.
 */

export type DmImageStatus = 'pending' | 'ready' | 'rejected';

/** Every `direct_message_images.status` the CHECK admits. */
export const DM_IMAGE_STATUSES = ['pending', 'ready', 'rejected'] as const satisfies readonly DmImageStatus[];

/** The long edge the client scales to; the worker and the size CHECK use it too. */
export const DM_IMAGE_MAX_EDGE = 2048;

/** The dm-images bucket's file_size_limit. */
export const DM_IMAGE_MAX_BYTES = 5 * 1024 * 1024;

/** The only type the bucket accepts. */
export const DM_IMAGE_CONTENT_TYPE = 'image/jpeg';

/** JPEG quality for the client re-encode. */
export const DM_IMAGE_QUALITY = 0.85;

/** How long a signed URL for a photo lives. */
export const DM_IMAGE_SIGNED_URL_SECONDS = 600;

export function parseDmImageStatus(raw: unknown): DmImageStatus {
	return raw === 'ready' || raw === 'rejected' ? raw : 'pending';
}

/** `width` x `height` scaled down to fit `max` on the long edge; never scaled up. */
export function dmImageFit(width: number, height: number, max = DM_IMAGE_MAX_EDGE): { width: number; height: number } {
	if (!(width > 0) || !(height > 0)) return { width: 0, height: 0 };
	const long = Math.max(width, height);
	if (long <= max) return { width: Math.round(width), height: Math.round(height) };
	const scale = max / long;
	return {
		width: Math.max(1, Math.round(width * scale)),
		height: Math.max(1, Math.round(height * scale)),
	};
}
