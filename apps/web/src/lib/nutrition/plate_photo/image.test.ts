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
