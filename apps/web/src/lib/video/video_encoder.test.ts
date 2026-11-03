import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { chooseVideoEncoder, videoExt, videoFileName, webcodecsConfig } from './video_encoder.ts';

test('WebCodecs H.264 wins, at the highest profile the browser accepts', () => {
	assert.deepEqual(
		chooseVideoEncoder({ webcodecs: ['avc1.42e028', 'avc1.4d0028'], recorder: ['video/webm'], canvasStream: true }),
		{ kind: 'webcodecs', codec: 'avc1.4d0028', mimeType: 'video/mp4', ext: 'mp4' },
	);
});

test('without WebCodecs H.264, MediaRecorder MP4 beats WebM', () => {
	assert.deepEqual(
		chooseVideoEncoder({ webcodecs: [], recorder: ['video/webm;codecs=vp9', 'video/mp4'], canvasStream: true }),
		{ kind: 'mediarecorder', mimeType: 'video/mp4', ext: 'mp4' },
	);
	assert.deepEqual(
		chooseVideoEncoder({ webcodecs: [], recorder: ['video/webm;codecs=vp8', 'video/webm'], canvasStream: true }),
		{ kind: 'mediarecorder', mimeType: 'video/webm;codecs=vp8', ext: 'webm' },
	);
});

test('no encoder at all, or no canvas stream for the recorder, offers nothing', () => {
	assert.equal(chooseVideoEncoder({ webcodecs: [], recorder: [], canvasStream: true }), null);
	assert.equal(chooseVideoEncoder({ webcodecs: [], recorder: ['video/webm'], canvasStream: false }), null);
	assert.equal(chooseVideoEncoder({ webcodecs: ['vp09.00.10.08'], recorder: [], canvasStream: true }), null);
});

test('the WebCodecs config leaves the bitstream at its AVCC default, which the muxer reads', () => {
	const c = webcodecsConfig('avc1.640028', 1080, 1920, 30);
	assert.ok(!('avc' in c));
	assert.deepEqual([c.width, c.height, c.framerate], [1080, 1920, 30]);
});

test('file names keep letters in any script and drop everything else', () => {
	assert.equal(videoFileName('Saturday long run: 30 km!', 'mp4'), 'threkir-saturday-long-run-30-km.mp4');
	assert.equal(videoFileName('Café côte', 'webm'), 'threkir-café-côte.webm');
	assert.equal(videoFileName('朝ラン', 'mp4'), 'threkir-朝ラン.mp4');
	assert.equal(videoFileName('../../', 'mp4'), 'threkir-flyover-video.mp4');
});

test('the file extension follows the container the encoder wrote', () => {
	assert.equal(videoExt('video/mp4'), 'mp4');
	assert.equal(videoExt('video/mp4;codecs=avc1'), 'mp4');
	assert.equal(videoExt('video/webm;codecs=vp9'), 'webm');
});
