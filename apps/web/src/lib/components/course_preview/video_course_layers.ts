/// What the video export draws on its map: the same course layers as the
/// dialog, km markers and start / finish markers included, built from the
/// export's own (privacy-clipped) line. Kept out of `flyover_video_export.ts`
/// so it can be tested without a browser.
import { distanceMarkers } from '#lib/routes/flyover_path.ts';
import type { CourseLayerInput } from './course_layers.ts';
import type { FlyoverVideoInput } from './flyover_video_export.ts';
import { startFinishMarkers } from './start_finish.ts';

export function videoCourseLayerInput(
	input: Pick<FlyoverVideoInput, 'path' | 'unit' | 'officialDistanceM' | 'climbs'> & {
		text: Pick<FlyoverVideoInput['text'], 'startFinish'>;
	},
	darkBasemap: boolean,
): CourseLayerInput {
	return {
		path: input.path,
		climbs: input.climbs,
		markers: distanceMarkers(input.path, input.unit, input.officialDistanceM),
		startFinish: startFinishMarkers(input.path, input.text.startFinish),
		darkBasemap,
	};
}
