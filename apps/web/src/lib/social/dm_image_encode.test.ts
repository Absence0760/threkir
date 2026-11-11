// Node has no canvas, so createImageBitmap and the canvas are stood in for
// here and the encoder's own decisions are pinned against them: which inputs
// reach the decoder, the size it draws at, the white under the pixels, the
// quality ladder and every refusal. What a real browser writes into the JPEG
// (no APP1 / EXIF, the orientation baked in, transparency read back as white)
// is pinned by tests-e2e/messages/dm-photos-links.spec.ts, which runs this
// encoder in Chromium. Mobile twin: test/dm_image_encode_test.dart.
import { afterEach, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';

import { DM_IMAGE_CONTENT_TYPE, DM_IMAGE_MAX_BYTES, DM_IMAGE_MAX_EDGE, DM_IMAGE_QUALITY, dmImageFit } from './dm_image.ts';
import { DM_IMAGE_QUALITY_STEPS, DmImageEncodeError, encodeDmImage } from './dm_image_encode.ts';

const JPEG_EXIF = [0xff, 0xd8, 0xff, 0xe1, 0x00, 0x10, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13];
const WEBP = [0x52, 0x49, 0x46, 0x46, 0x10, 0, 0, 0, 0x57, 0x45, 0x42, 0x50];

function file(head: number[], type = ''): Blob {
	return new Blob([new Uint8Array([...head, ...new Array(64).fill(0x11)])], { type });
}

interface Stage {
	bitmap: { width: number; height: number };
	decodeFails: boolean;
	noContext: boolean;
	/** One entry per toBlob call: the size of what the canvas writes, or null for a failed encode. */
	blobSizes: (number | null)[];
}

interface Seen {
	decoded: { source: Blob; options: unknown }[];
	canvas: { width: number; height: number } | null;
	ops: string[];
	encodes: { type: string; quality: number }[];
	closed: number;
	written: Blob[];
}

let stage: Stage;
let seen: Seen;
const saved = { createImageBitmap: globalThis.createImageBitmap, document: (globalThis as { document?: unknown }).document };

beforeEach(() => {
	stage = { bitmap: { width: 40, height: 30 }, decodeFails: false, noContext: false, blobSizes: [1000] };
	seen = { decoded: [], canvas: null, ops: [], encodes: [], closed: 0, written: [] };
	const bitmap = () => ({
		...stage.bitmap,
		close: () => {
			seen.closed++;
		},
	});
	globalThis.createImageBitmap = (async (source: Blob, options: unknown) => {
		seen.decoded.push({ source, options });
		if (stage.decodeFails) throw new DOMException('The source image could not be decoded.', 'InvalidStateError');
		return bitmap();
	}) as unknown as typeof createImageBitmap;
	(globalThis as { document?: unknown }).document = {
		createElement(tag: string) {
			assert.equal(tag, 'canvas');
			const canvas = {
				width: 0,
				height: 0,
				getContext(kind: string) {
					assert.equal(kind, '2d');
					seen.canvas = { width: canvas.width, height: canvas.height };
					if (stage.noContext) return null;
					const ctx = {
						fillStyle: '',
						fillRect: (...a: number[]) => seen.ops.push(`fillRect ${ctx.fillStyle} ${a.join(',')}`),
						drawImage: (_img: unknown, ...a: number[]) => seen.ops.push(`drawImage ${a.join(',')}`),
					};
					return ctx;
				},
				toBlob(cb: (b: Blob | null) => void, type: string, quality: number) {
					seen.encodes.push({ type, quality });
					const size = stage.blobSizes[seen.encodes.length - 1] ?? null;
					const out = size === null ? null : new Blob([new Uint8Array(size)], { type });
					if (out) seen.written.push(out);
					queueMicrotask(() => cb(out));
				},
			};
			return canvas;
		},
	};
});

afterEach(() => {
	globalThis.createImageBitmap = saved.createImageBitmap;
	(globalThis as { document?: unknown }).document = saved.document;
});

async function refusal(input: Blob): Promise<string> {
	try {
		await encodeDmImage(input);
	} catch (e) {
		assert.ok(e instanceof DmImageEncodeError, `expected DmImageEncodeError, got ${e}`);
		return e.kind;
	}
	assert.fail('expected the encode to be refused');
}

test('a geotagged JPEG is redrawn from pixels only: oriented, fitted, on white, written as a JPEG', async () => {
	stage.bitmap = { width: 3000, height: 1000 };
	const input = file(JPEG_EXIF, 'image/jpeg');
	const out = await encodeDmImage(input);

	assert.equal(seen.decoded.length, 1);
	assert.deepEqual(seen.decoded[0].options, { imageOrientation: 'from-image' });
	const fit = dmImageFit(3000, 1000);
	assert.deepEqual(seen.canvas, fit);
	assert.equal(fit.width, DM_IMAGE_MAX_EDGE);
	assert.deepEqual(seen.ops, [`fillRect #fff 0,0,${fit.width},${fit.height}`, `drawImage 0,0,${fit.width},${fit.height}`]);
	assert.deepEqual(seen.encodes, [{ type: DM_IMAGE_CONTENT_TYPE, quality: DM_IMAGE_QUALITY }]);
	assert.equal(out, seen.written[0], 'the upload is what the canvas wrote, never the input bytes');
	assert.notEqual(out, input);
	assert.equal(seen.closed, 1);
});

test('a small photo keeps its size and is still redrawn', async () => {
	stage.bitmap = { width: 40, height: 30 };
	const out = await encodeDmImage(file(PNG, 'image/png'));
	assert.deepEqual(seen.canvas, { width: 40, height: 30 });
	assert.equal(out.type, DM_IMAGE_CONTENT_TYPE);
	assert.equal(seen.ops[0], 'fillRect #fff 0,0,40,30', 'transparency is flattened onto white before the draw');
});

test('a JPEG, a PNG and a WebP are taken whatever the file claims to be', async () => {
	stage.blobSizes = [1000, 1000, 1000];
	for (const head of [JPEG_EXIF, PNG, WEBP]) {
		await encodeDmImage(file(head, 'application/octet-stream'));
	}
	assert.equal(seen.decoded.length, 3);
});

test('anything else is refused as unreadable before the browser decodes it', async () => {
	const others: [string, number[], string][] = [
		['GIF', [...Buffer.from('GIF89a')], 'image/gif'],
		['BMP', [0x42, 0x4d, 0x36, 0, 0, 0], 'image/bmp'],
		['HEIC', [0, 0, 0, 0x18, ...Buffer.from('ftypheic')], 'image/jpeg'],
		['SVG named .jpg', [...Buffer.from('<svg></svg>')], 'image/jpeg'],
	];
	for (const [name, head, type] of others) {
		assert.equal(await refusal(file(head, type)), 'unreadable', name);
	}
	assert.equal(await refusal(new Blob([])), 'unreadable', 'an empty file');
	assert.equal(seen.decoded.length, 0, 'none of them reaches createImageBitmap');
});

test('a file that looks like a JPEG but does not decode is refused as unreadable', async () => {
	stage.decodeFails = true;
	assert.equal(await refusal(new Blob([new Uint8Array([0xff, 0xd8, 0xff, 0x00, 0x01])])), 'unreadable');
	assert.equal(seen.canvas, null);
});

test('a decoded image with no pixels, no 2d context or a failed encode is refused, and the bitmap is closed', async () => {
	stage.bitmap = { width: 0, height: 10 };
	assert.equal(await refusal(file(JPEG_EXIF)), 'unreadable');
	assert.equal(seen.closed, 1);

	stage.bitmap = { width: 10, height: 10 };
	stage.noContext = true;
	assert.equal(await refusal(file(JPEG_EXIF)), 'unreadable');
	assert.equal(seen.closed, 2);

	stage.noContext = false;
	stage.blobSizes = [null];
	assert.equal(await refusal(file(JPEG_EXIF)), 'unreadable');
	assert.equal(seen.closed, 3);
});

test('quality steps down until the photo fits the bucket limit', async () => {
	stage.blobSizes = [DM_IMAGE_MAX_BYTES + 1, DM_IMAGE_MAX_BYTES];
	const out = await encodeDmImage(file(JPEG_EXIF));
	assert.deepEqual(
		seen.encodes.map((e) => e.quality),
		[DM_IMAGE_QUALITY_STEPS[0], DM_IMAGE_QUALITY_STEPS[1]],
	);
	assert.equal(out.size, DM_IMAGE_MAX_BYTES);
});

test('a photo still over the limit at the lowest quality is refused as too large', async () => {
	stage.blobSizes = [DM_IMAGE_MAX_BYTES + 1, DM_IMAGE_MAX_BYTES + 1, DM_IMAGE_MAX_BYTES + 1];
	assert.equal(await refusal(file(JPEG_EXIF)), 'too_large');
	assert.deepEqual(
		seen.encodes.map((e) => e.quality),
		[...DM_IMAGE_QUALITY_STEPS],
	);
	assert.equal(seen.closed, 1);
});

test('quality steps down the way mobile does', () => {
	assert.deepEqual([...DM_IMAGE_QUALITY_STEPS], [DM_IMAGE_QUALITY, 0.7, 0.55]);
	assert.equal(DM_IMAGE_QUALITY, 0.85);
});
