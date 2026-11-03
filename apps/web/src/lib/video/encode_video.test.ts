import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { createFrameSink } from './encode_video.ts';

class FakeTrack {
	stopped = 0;
	requestFrame() {}
	stop() {
		this.stopped++;
	}
}

class FakeRecorder {
	static last: FakeRecorder | null = null;
	state: 'inactive' | 'recording' = 'inactive';
	ondataavailable: ((e: { data: Blob }) => void) | null = null;
	onstop: (() => void) | null = null;
	onerror: ((e: unknown) => void) | null = null;
	constructor() {
		FakeRecorder.last = this;
	}
	start() {
		this.state = 'recording';
	}
	stop() {
		this.state = 'inactive';
		this.ondataavailable?.({ data: new Blob(['x']) });
		this.onstop?.();
	}
}

function fakeCanvas(track: FakeTrack): HTMLCanvasElement {
	return { captureStream: () => ({ getVideoTracks: () => [track] }) } as unknown as HTMLCanvasElement;
}

test('the MediaRecorder sink releases the capture track once the recording finishes', async (t) => {
	const g = globalThis as { MediaRecorder?: unknown };
	const prev = g.MediaRecorder;
	g.MediaRecorder = FakeRecorder;
	t.after(() => {
		g.MediaRecorder = prev;
	});
	const track = new FakeTrack();
	const sink = createFrameSink(
		{ kind: 'mediarecorder', mimeType: 'video/webm', ext: 'webm' },
		fakeCanvas(track),
		30,
	);
	const blob = await sink.finish();
	assert.equal(blob.type, 'video/webm');
	assert.equal(track.stopped, 1);
});

test('the MediaRecorder sink releases the capture track when the recorder errors', async (t) => {
	const g = globalThis as { MediaRecorder?: unknown };
	const prev = g.MediaRecorder;
	g.MediaRecorder = FakeRecorder;
	t.after(() => {
		g.MediaRecorder = prev;
	});
	const track = new FakeTrack();
	const sink = createFrameSink(
		{ kind: 'mediarecorder', mimeType: 'video/webm', ext: 'webm' },
		fakeCanvas(track),
		30,
	);
	const done = sink.finish();
	FakeRecorder.last!.onerror!({ error: new Error('encoder died') });
	await assert.rejects(done, /encoder died/);
	assert.equal(track.stopped, 1);
});
