import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MAX_PLATE_IMAGE_BYTES, preparePlateImage, sniffImageType } from './image';

function jpeg(withExif: boolean, fill = 100): Uint8Array {
	const parts: number[] = [0xff, 0xd8];
	parts.push(0xff, 0xe0, 0x00, 0x10, ...Array.from({ length: 14 }, () => 0x4a));
	if (withExif) {
		const gps = Array.from('Exif\0\0GPS-51.5074N', (c) => c.charCodeAt(0));
		parts.push(0xff, 0xe1, 0x00, gps.length + 2, ...gps);
	}
	parts.push(0xff, 0xda, 0x00, 0x08, ...Array.from({ length: fill }, (_, i) => i % 200), 0xff, 0xd9);
	return Uint8Array.from(parts);
}

const b64 = (b: Uint8Array) => Buffer.from(b).toString('base64');

test('sniffImageType reads JPEG, PNG and WebP magic numbers', () => {
	assert.equal(sniffImageType(jpeg(false)), 'image/jpeg');
	assert.equal(
		sniffImageType(Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0])),
		'image/png',
	);
	assert.equal(sniffImageType(Uint8Array.from(Buffer.from('RIFF\0\0\0\0WEBPVP8 '))), 'image/webp');
	assert.equal(sniffImageType(Uint8Array.from(Buffer.from('GIF89a......'))), null);
});

test('a JPEG passes and loses its EXIF (GPS) segment before it is forwarded', () => {
	const out = preparePlateImage(b64(jpeg(true)), 'image/jpeg');
	assert.equal(out.ok, true);
	if (!out.ok) return;
	const sent = Buffer.from(out.base64, 'base64');
	assert.equal(sent.includes(Buffer.from('GPS-51.5074N')), false);
	assert.equal(sent.length, jpeg(false).length);
});

test('a data: URL prefix is accepted', () => {
	assert.equal(preparePlateImage(`data:image/jpeg;base64,${b64(jpeg(false))}`, 'image/jpeg').ok, true);
});

test('an unsupported declared type is refused', () => {
	assert.deepEqual(preparePlateImage(b64(jpeg(false)), 'image/gif'), { ok: false, reason: 'type' });
	assert.deepEqual(preparePlateImage(b64(jpeg(false)), undefined), { ok: false, reason: 'type' });
});

test('bytes that are not the declared type are refused', () => {
	assert.deepEqual(preparePlateImage(b64(jpeg(false)), 'image/png'), { ok: false, reason: 'mismatch' });
});

test('malformed base64 is refused', () => {
	for (const bad of ['not base64!!', 'abc', '', 42]) {
		assert.deepEqual(preparePlateImage(bad, 'image/jpeg'), { ok: false, reason: 'encoding' }, String(bad));
	}
});

test('an image over the byte ceiling, or too small to be one, is refused', () => {
	const big = new Uint8Array(MAX_PLATE_IMAGE_BYTES + 3);
	big.set([0xff, 0xd8, 0xff]);
	assert.deepEqual(preparePlateImage(b64(big), 'image/jpeg'), { ok: false, reason: 'size' });
	assert.deepEqual(preparePlateImage(b64(Uint8Array.from([0xff, 0xd8, 0xff, 0xd9])), 'image/jpeg'), {
		ok: false,
		reason: 'size',
	});
});

function pngChunk(type: string, data: number[]): number[] {
	const len = data.length;
	return [(len >>> 24) & 0xff, (len >>> 16) & 0xff, (len >>> 8) & 0xff, len & 0xff, ...Buffer.from(type, 'latin1'), ...data, 0, 0, 0, 0];
}

function png(withExif: boolean): Uint8Array {
	const parts = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
	parts.push(...pngChunk('IHDR', [0, 0, 0, 2, 0, 0, 0, 2, 8, 2, 0, 0, 0]));
	if (withExif) parts.push(...pngChunk('eXIf', Array.from(Buffer.from('GPS-51.5074N', 'latin1'))));
	parts.push(...pngChunk('IDAT', Array.from({ length: 40 }, (_, i) => i)));
	parts.push(...pngChunk('IEND', []));
	return Uint8Array.from(parts);
}

function webp(withExif: boolean): Uint8Array {
	const chunk = (fourcc: string, data: number[]) => {
		const n = data.length;
		return [...Buffer.from(fourcc, 'latin1'), n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff, ...data, ...(n & 1 ? [0] : [])];
	};
	const body = [...Buffer.from('WEBP', 'latin1'), ...chunk('VP8 ', Array.from({ length: 60 }, (_, i) => i))];
	if (withExif) body.push(...chunk('EXIF', Array.from(Buffer.from('GPS-51.5074N', 'latin1'))));
	const size = body.length;
	return Uint8Array.from([...Buffer.from('RIFF', 'latin1'), size & 0xff, (size >>> 8) & 0xff, (size >>> 16) & 0xff, (size >>> 24) & 0xff, ...body]);
}

test('a PNG passes under its own type and loses its eXIf chunk', () => {
	const out = preparePlateImage(b64(png(true)), 'image/png');
	assert.equal(out.ok, true);
	if (!out.ok) return;
	assert.equal(out.mediaType, 'image/png');
	const sent = Buffer.from(out.base64, 'base64');
	assert.equal(sent.includes(Buffer.from('GPS-51.5074N')), false);
	assert.deepEqual(new Uint8Array(sent), png(false));
});

test('a WebP passes under its own type and loses its EXIF chunk', () => {
	const out = preparePlateImage(b64(webp(true)), 'image/webp');
	assert.equal(out.ok, true);
	if (!out.ok) return;
	assert.equal(out.mediaType, 'image/webp');
	const sent = Buffer.from(out.base64, 'base64');
	assert.equal(sent.includes(Buffer.from('GPS-51.5074N')), false);
	assert.deepEqual(new Uint8Array(sent), webp(false));
	assert.equal(out.bytes, sent.length);
});
