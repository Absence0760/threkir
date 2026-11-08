import type { Guide } from '../types';

export const guide: Guide = {
	id: 'park-courses',
	title: 'Park courses: checkpoints, seasons and the boards',
	summary: 'How a park course times your run, why every checkpoint counts, when a season starts, and how the Fastest and Most completions boards rank people.',
	kind: 'explainer',
	category: 'running',
	audience: ['runner'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/parks', '/parks/[region]/[park]', '/parks/[region]/[park]/[course]'],
	sections: [
		{
			heading: 'What a park course is',
			blocks: [
				{
					type: 'p',
					text: 'A park course is a fixed time-trial course on a trail in a state or national park. There is no organiser and no race day: run it whenever the park is open, and a run that covers the whole course is timed against it. Find them under [[route:/parks|Park courses]].',
				},
				{
					type: 'list',
					items: [
						'It is a time trial, not a race. The trail stays open to everyone and nobody marshals it, so follow the park\'s rules and give way to other people on the trail.',
						'Each course page shows the distance, elevation gain, shape, surface and difficulty, where the course line came from, and whether the course is open.',
						'Select **Navigate this course** to follow the course as a route. It isn\'t offered while the course is closed.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'A closed course keeps its times and boards, but please don\'t run it until it reopens. The page shows when its status was last checked.',
				},
			],
		},
		{
			heading: 'Checkpoints: why shortcuts never count',
			blocks: [
				{
					type: 'p',
					text: 'Besides the start and the finish, a course can have checkpoints along the way. Your run is only timed when it passes every checkpoint, in order, between the start and the finish. A run that cuts a corner, skips a switchback or takes a path across the middle misses a checkpoint and gets no time.',
				},
				{
					type: 'p',
					text: 'Stay on the marked trail. Cutting a trail damages it, and parks treat it as a breach of their rules.',
				},
			],
		},
		{
			heading: 'Seasons follow the park\'s clock',
			blocks: [
				{
					type: 'p',
					text: 'A season is a calendar year in the park\'s own time zone, not yours. The boards start again at midnight on 1 January where the park is.',
				},
				{
					type: 'p',
					text: 'For example, a run that starts at 22:00 on 31 December in a Virginia park counts for that year, even if your phone is set to a time zone where it is already 1 January.',
				},
			],
		},
		{
			heading: 'The Fastest board',
			blocks: [
				{
					type: 'list',
					items: [
						'**Fastest** ranks each runner by their best time on the course. You appear once, with your best run.',
						'It shows this year by default. Select **All time** for the best times ever.',
						'Filter by gender or age band. The age filter only includes runners who have agreed to share health data, so it may be shorter than the full board.',
					],
				},
			],
		},
		{
			heading: 'The Most completions board',
			blocks: [
				{
					type: 'p',
					text: '**Most completions** rewards the regulars. It counts the days you completed the course, in the park\'s time zone, so running several laps on one day counts as one.',
				},
			],
		},
		{
			heading: 'Who appears on the boards',
			blocks: [
				{
					type: 'list',
					items: [
						'You need to be signed in to see the boards. Signed out, a course page still shows the course and a **Sign in** link.',
						'A time from a run other people can\'t see isn\'t shown to them.',
						'You won\'t see people you have blocked, and they won\'t see you.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: "A run is checked against park courses on our servers shortly after it's saved or imported, from any device. A new time can take a few minutes to appear on a board.",
				},
			],
		},
	],
	related: ['import-your-history', 'record-your-first-run'],
};
