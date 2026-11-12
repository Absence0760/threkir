/// Which encoder a video export uses, chosen from what the browser says it
/// supports. WebCodecs H.264 into an MP4 the export muxes itself is preferred:
/// its frames carry exact timestamps, and H.264 MP4 is the file every social
/// app takes. `MediaRecorder` over a canvas stream is the fallback where
/// WebCodecs is missing; it timestamps frames by wall clock, so the export
/// paces frames to real time on that path. The probing itself is browser glue
/// (`encode_video.ts`); this module only decides.

/// High, Main, then Constrained Baseline, all at level 4.0, which admits a
/// 1080x1920 frame (8160 macroblocks against a 8192 ceiling).
export const H264_CODECS: readonly string[] = ['avc1.640028', 'avc1.4d0028', 'avc1.42e028'];

export const RECORDER_TYPES: readonly string[] = [
	'video/mp4;codecs=avc1',
	'video/mp4',
	'video/webm;codecs=vp9',
	'video/webm;codecs=vp8',
	'video/webm',
];

export const VIDEO_BITRATE = 8_000_000;

export interface EncoderProbe {
	/// The H.264 codec strings `VideoEncoder.isConfigSupported` accepted.
	webcodecs: readonly string[];
	/// The `RECORDER_TYPES` entries `MediaRecorder.isTypeSupported` accepted.
	recorder: readonly string[];
	/// Whether a canvas can hand `MediaRecorder` a stream at all.
	canvasStream: boolean;
}

export type VideoEncoderPlan =
	| { kind: 'webcodecs'; codec: string; mimeType: 'video/mp4'; ext: 'mp4' }
	| { kind: 'mediarecorder'; mimeType: string; ext: 'mp4' | 'webm' };

export function chooseVideoEncoder(probe: EncoderProbe): VideoEncoderPlan | null {
	const codec = H264_CODECS.find((c) => probe.webcodecs.includes(c));
	if (codec) return { kind: 'webcodecs', codec, mimeType: 'video/mp4', ext: 'mp4' };
	if (!probe.canvasStream) return null;
	const type = RECORDER_TYPES.find((t) => probe.recorder.includes(t));
	if (!type) return null;
	return { kind: 'mediarecorder', mimeType: type, ext: videoExt(type) };
}

export function videoExt(mimeType: string): 'mp4' | 'webm' {
	return mimeType.startsWith('video/mp4') ? 'mp4' : 'webm';
}

/// No `avc.format`: its default is AVCC framing with the `avcC` record in
/// `decoderConfig.description`, which is what the muxer consumes; Annex B
/// would have to be reframed first.
export function webcodecsConfig(codec: string, width: number, height: number, fps: number) {
	return { codec, width, height, bitrate: VIDEO_BITRATE, framerate: fps };
}

/// A file name the OS share sheet and a download both accept: the title's
/// letters and digits, never empty, never a path.
export function videoFileName(title: string, ext: string): string {
	const stem = title
		.normalize('NFC')
		.replace(/[^\p{L}\p{M}\p{N}]+/gu, '-')
		.replace(/^-+|-+$/g, '')
		.slice(0, 60)
		.toLowerCase();
	return stem ? `threkir-${stem}.${ext}` : `threkir-flyover-video.${ext}`;
}
