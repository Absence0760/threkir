/// Browser glue shared by every video export (decisions § 2259, § 2269): what
/// the browser can encode, a sink that takes rendered canvases frame by frame
/// on the shared clock, and handing the finished file to the OS share sheet or
/// a download. What can be decided without a browser is decided in
/// `video_encoder.ts`, `frame_clock.ts` and `mp4_mux.ts`; this file only
/// drives the APIs. It never imports a map, so a consumer that draws no map
/// pulls none in.
import { muxMp4, type Mp4Sample } from './mp4_mux.ts';
import { frameDurationUs, frameTimestampUs, isKeyFrame, VIDEO_HEIGHT, VIDEO_WIDTH } from './frame_clock.ts';
import {
	chooseVideoEncoder,
	H264_CODECS,
	RECORDER_TYPES,
	VIDEO_BITRATE,
	videoExt,
	videoFileName,
	webcodecsConfig,
	type EncoderProbe,
	type VideoEncoderPlan,
} from './video_encoder.ts';

const MAX_ENCODE_QUEUE = 8;

export function videoAbortError(): DOMException {
	return new DOMException('The video export was cancelled', 'AbortError');
}

async function probeVideoEncoders(): Promise<EncoderProbe> {
	const webcodecs: string[] = [];
	if (typeof VideoEncoder !== 'undefined' && typeof VideoFrame !== 'undefined') {
		for (const codec of H264_CODECS) {
			try {
				const res = await VideoEncoder.isConfigSupported(webcodecsConfig(codec, VIDEO_WIDTH, VIDEO_HEIGHT, 30));
				if (res.supported) webcodecs.push(codec);
			} catch {
				// An unknown codec string rejects rather than answering false.
			}
		}
	}
	const recorder =
		typeof MediaRecorder !== 'undefined'
			? RECORDER_TYPES.filter((t) => {
					try {
						return MediaRecorder.isTypeSupported(t);
					} catch {
						return false;
					}
				})
			: [];
	const canvasStream =
		typeof HTMLCanvasElement !== 'undefined' && typeof HTMLCanvasElement.prototype.captureStream === 'function';
	return { webcodecs, recorder, canvasStream };
}

/// The encoder this browser offers, or null when it can encode no video at
/// all, in which case a consumer hides its export behind a note.
export async function pickVideoEncoder(): Promise<VideoEncoderPlan | null> {
	return chooseVideoEncoder(await probeVideoEncoders());
}

export interface FrameSink {
	push(canvas: HTMLCanvasElement, index: number): Promise<void>;
	finish(): Promise<Blob>;
	abort(): void;
}

function webcodecsSink(plan: Extract<VideoEncoderPlan, { kind: 'webcodecs' }>, fps: number): FrameSink {
	const samples: Mp4Sample[] = [];
	let avcC: Uint8Array | null = null;
	let failure: unknown = null;
	const encoder = new VideoEncoder({
		output: (chunk, meta) => {
			const desc = meta?.decoderConfig?.description;
			if (desc && !avcC) {
				avcC = ArrayBuffer.isView(desc)
					? new Uint8Array(desc.buffer.slice(desc.byteOffset, desc.byteOffset + desc.byteLength))
					: new Uint8Array(desc.slice(0));
			}
			const data = new Uint8Array(chunk.byteLength);
			chunk.copyTo(data);
			samples.push({
				data,
				timestampUs: chunk.timestamp,
				durationUs: chunk.duration ?? frameDurationUs(samples.length, fps),
				keyframe: chunk.type === 'key',
			});
		},
		error: (e) => {
			failure = e;
		},
	});
	encoder.configure(webcodecsConfig(plan.codec, VIDEO_WIDTH, VIDEO_HEIGHT, fps));
	return {
		async push(canvas, index) {
			if (failure) throw failure;
			while (encoder.encodeQueueSize > MAX_ENCODE_QUEUE) {
				await new Promise((r) => setTimeout(r, 10));
			}
			const frame = new VideoFrame(canvas, {
				timestamp: frameTimestampUs(index, fps),
				duration: frameDurationUs(index, fps),
			});
			try {
				encoder.encode(frame, { keyFrame: isKeyFrame(index, fps) });
			} finally {
				frame.close();
			}
		},
		async finish() {
			await encoder.flush();
			encoder.close();
			if (failure) throw failure;
			if (!avcC) throw new Error('the encoder produced no H.264 configuration');
			const bytes = muxMp4({ width: VIDEO_WIDTH, height: VIDEO_HEIGHT, avcC, samples });
			return new Blob([bytes as BlobPart], { type: plan.mimeType });
		},
		abort() {
			if (encoder.state !== 'closed') encoder.close();
		},
	};
}

/// `MediaRecorder` stamps frames by wall clock, so each frame is handed over
/// no earlier than its own time. A frame that takes longer than its slot to
/// render stretches the recording there; the WebCodecs path has no such
/// limit, which is why it is preferred.
function recorderSink(
	plan: Extract<VideoEncoderPlan, { kind: 'mediarecorder' }>,
	canvas: HTMLCanvasElement,
	fps: number,
): FrameSink {
	const stream = canvas.captureStream(0);
	const track = stream.getVideoTracks()[0] as CanvasCaptureMediaStreamTrack;
	const recorder = new MediaRecorder(stream, { mimeType: plan.mimeType, videoBitsPerSecond: VIDEO_BITRATE });
	const parts: Blob[] = [];
	recorder.ondataavailable = (e) => {
		if (e.data.size > 0) parts.push(e.data);
	};
	recorder.start();
	const t0 = performance.now();
	return {
		async push(_canvas, index) {
			const due = t0 + frameTimestampUs(index, fps) / 1000;
			const wait = due - performance.now();
			if (wait > 0) await new Promise((r) => setTimeout(r, wait));
			track.requestFrame();
		},
		finish() {
			return new Promise((resolve, reject) => {
				recorder.onstop = () => {
					track.stop();
					resolve(new Blob(parts, { type: plan.mimeType }));
				};
				recorder.onerror = (e) => {
					track.stop();
					reject((e as Event & { error?: unknown }).error ?? new Error('recorder failed'));
				};
				setTimeout(() => recorder.stop(), frameDurationUs(0, fps) / 1000);
			});
		},
		abort() {
			if (recorder.state !== 'inactive') recorder.stop();
			track.stop();
		},
	};
}

/// `canvas` is the one every frame is drawn on: the `MediaRecorder` path
/// records it as a stream, so it must be the same element each `push` passes.
export function createFrameSink(plan: VideoEncoderPlan, canvas: HTMLCanvasElement, fps: number): FrameSink {
	return plan.kind === 'webcodecs' ? webcodecsSink(plan, fps) : recorderSink(plan, canvas, fps);
}

/// The OS share sheet when it takes files (phones, Safari), a download
/// otherwise. Must run inside a fresh user gesture: a share sheet opened at
/// the end of a long render has long lost the one that started it. The file
/// is named from `stem` (`videoFileName`) in the container the encoder wrote.
export async function deliverVideo(blob: Blob, stem: string, title: string): Promise<'shared' | 'downloaded'> {
	const fileName = videoFileName(stem, videoExt(blob.type));
	const file = new File([blob], fileName, { type: blob.type });
	if (typeof navigator.share === 'function' && navigator.canShare?.({ files: [file] })) {
		await navigator.share({ files: [file], title });
		return 'shared';
	}
	const url = URL.createObjectURL(blob);
	try {
		const a = document.createElement('a');
		a.href = url;
		a.download = fileName;
		a.click();
	} finally {
		setTimeout(() => URL.revokeObjectURL(url), 60_000);
	}
	return 'downloaded';
}
