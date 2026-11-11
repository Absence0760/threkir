import type { Guide } from '../types';

export const guide: Guide = {
	id: 'how-segment-times-are-measured',
	title: 'How segment times are measured',
	summary: 'Segment and park course times run from a start line to an end line, crossed the right way, and your fastest pass counts.',
	kind: 'explainer',
	category: 'running',
	audience: ['runner'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/segments/[id]', '/parks/[region]/[park]/[course]'],
	sections: [
		{
			heading: 'Start and end lines',
			blocks: [
				{
					type: 'p',
					text: 'Each segment has a start line and an end line, one across the path at each end, facing the way the segment runs and reaching 15 m to each side. A park course is a segment too, so it is timed the same way.',
				},
				{
					type: 'list',
					items: [
						'Your time runs from the moment your run crosses the start line to the moment it crosses the end line.',
						'Each crossing is worked out between the two GPS points either side of the line, not taken at whichever point happened to be nearest, so the time is closer to the real one.',
						'Both lines must be crossed going the way the segment runs. Crossing one backwards does not count.',
						'The distance you covered between the two crossings must be within 25% of the segment\'s length, and on a park course you must pass every checkpoint, in order, in between.',
					],
				},
			],
		},
		{
			heading: 'Why a path alongside does not count',
			blocks: [
				{
					type: 'p',
					text: 'A run on a path running alongside the segment, 20 m away, comes close to both ends without ever passing through the lines, so it gets no time. Neither does the way out of an out-and-back route that only passes near the end.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Start recording a little before the start line. A run whose recording starts on the line, or past it, never crosses it, and gets no time on that segment.',
				},
			],
		},
		{
			heading: 'More than one pass',
			blocks: [
				{
					type: 'list',
					items: [
						'If your run passes the segment more than once, your fastest pass counts.',
						'A warm-up that loops back over the start line does not lengthen your time: the time starts from your last crossing of the start line before the end.',
						'On a loop, every complete lap is timed and your fastest lap counts. Where the start and end are the same line, the crossing that ends one lap also starts the next.',
					],
				},
			],
		},
		{
			heading: 'Segments without lines',
			blocks: [
				{
					type: 'p',
					text: 'A segment too short at one end to place a line there has no lines. It is still timed the old way: your run must pass within 35 m of its start and then within 35 m of its end.',
				},
			],
		},
		{
			heading: 'Older efforts',
			blocks: [
				{
					type: 'p',
					text: 'Efforts recorded before segments had lines were measured the old way, by passing near the start and the end. Each is measured again by the lines the next time its runner opens the run on the website. Its time can change, and it can disappear if the run never crossed the lines.',
				},
				{
					type: 'p',
					text: 'Until every effort on a segment has been measured again, its board says that some older efforts were measured the old way.',
				},
			],
		},
	],
	related: ['park-courses', 'import-your-history'],
};
