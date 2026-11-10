import type { Guide } from '../types';

export const guide: Guide = {
	id: 'start-and-finish-lines',
	title: 'Start and finish lines',
	summary: "What a course's start and finish lines are, how they are placed for you, and how to move, turn, widen or place them yourself.",
	kind: 'how-to',
	category: 'races',
	audience: ['organiser', 'club-admin'],
	platforms: ['web'],
	routes: ['/clubs/[slug]/events/[id]'],
	sections: [
		{
			heading: 'What a line is',
			blocks: [
				{
					type: 'p',
					text: 'Every course in a race has a start line and a finish line. A line sits across the course at one point, faces the way runners travel, and reaches a set distance to each side. A runner crosses it only by passing through it in that direction, within its reach.',
				},
				{
					type: 'p',
					text: 'That is the difference from a finish point with a 30 m circle around it. A circle counts anyone who comes near: a runner on a path running alongside, or on the way out of an out-and-back course that comes home the same way. A line does not, because they never pass through it in the right direction.',
				},
			],
		},
		{
			heading: 'Lines placed for you',
			blocks: [
				{
					type: 'p',
					text: "When a course has a route, it gets both lines from it. The start line sits on the route's first point, facing along the route. The finish line sits on its last point, facing the way the route arrives. Each reaches 15 m to each side. They follow the route: change the route and they move with it.",
				},
				{
					type: 'p',
					text: 'Lines appear once the event is saved with at least one course. Open the event, choose **Edit event** and find **Start and finish lines**. Each course has a map and a row for each line, which says where the line came from: **From the route**, **Placed by an organiser** or **None**.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: "If the route's owner has a privacy zone over the start or the end of the route, that end is hidden from everyone else, so it gets no line. Place that line yourself.",
				},
			],
		},
		{
			heading: 'Move, turn or widen a line',
			blocks: [
				{
					type: 'steps',
					items: [
						'Next to **Start line** or **Finish line**, choose **Edit**.',
						'On the map, drag the middle of the line to move it, and drag its handle to turn it. If the map is off, choose **Load map**, or skip the map and type the values instead.',
						'Or type the **Latitude**, **Longitude** and **Direction (degrees)**. The direction is the way runners cross, clockwise from north: 0 is north, 90 east, 180 south and 270 west.',
						'Set **Reach each side**, from 5 to 100 m. Make it wide enough to cover the whole road or path, and a little more.',
						'Choose **Save line**.',
					],
				},
				{
					type: 'p',
					text: 'Each line saves on its own, straight away; you do not need to save the event. A line you have moved shows **Placed by an organiser**. Choose **Reset to route** to put it back where the route places it.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'A line you placed stays exactly where you put it, even if you later change the course route. After changing a route, check the warnings under each line.',
				},
			],
		},
		{
			heading: 'Warnings in the editor',
			blocks: [
				{
					type: 'list',
					items: [
						'The line is more than 100 m from the course route. Check it is in the right place.',
						'The line faces against the route, so runners following the route would cross it backwards. Turn it round.',
						'The route crosses its own finish line before the end, as a course of laps or a track does. Finishing by the line is then turned off for that course, and runners finish by pressing Stop or Finish.',
					],
				},
			],
		},
		{
			heading: 'Courses with no route',
			blocks: [
				{
					type: 'p',
					text: 'A course with no route has no lines until you place them. Choose **Place start line** or **Place finish line**. If you have moved the map to the spot first, the line starts at the middle of the map; otherwise type its position. Then set its direction and reach and choose **Save line**. **Remove line** takes a line you placed away again.',
				},
			],
		},
		{
			heading: 'Lines are frozen when a race starts',
			blocks: [
				{
					type: 'p',
					text: "When you arm a race (for a self-timed race, when its window opens), each course's lines are copied for that race. Every runner in it then crosses the same lines, whatever changes during the race. A change you make later applies from the next race. The event page and the live race page show the lines the race was armed with.",
				},
			],
		},
		{
			heading: 'Checks before a race',
			blocks: [
				{
					type: 'p',
					text: 'Before a race is armed, the lines of every course are checked, on the web and in the phone app. A warning lets you **Arm anyway**; a problem marked **Must fix:** stops the race being armed until you fix it in the event editor on the web.',
				},
				{
					type: 'list',
					items: [
						'A course with no finish line and no finish point: a warning, because its runners finish by hand. A self-timed race must fix it.',
						'A course with no start line: a self-timed race must fix it. Other races can start without one.',
						'A route that crosses its own finish line before the end: a warning, because finishing by the line is off for that course. A self-timed race must fix it.',
						'A line more than 100 m from the route: a warning in every kind of race.',
					],
				},
				{
					type: 'p',
					text: 'Which kind of race you are running is set under **How the race starts**; see [[guide:choose-how-your-race-starts|Choose how your race starts]].',
				},
			],
		},
	],
	related: ['set-up-a-race', 'choose-how-your-race-starts', 'race-day-for-hosts'],
};
