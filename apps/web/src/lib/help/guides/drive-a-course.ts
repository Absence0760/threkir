import type { Guide } from '../types';

export const guide: Guide = {
	id: 'drive-a-course',
	title: 'Drive a race course before race day',
	summary: 'Open a public course in your Maps app, see which stretches it can\'t follow, and have the phone app read the course notes aloud as you drive.',
	kind: 'how-to',
	category: 'races',
	audience: ['runner'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/routes/[id]', '/races/[id]'],
	sections: [
		{
			heading: 'What it does',
			blocks: [
				{
					type: 'p',
					text: 'On a public route or a race with a public course, **Drive this course** splits the course into legs that Google Maps, Apple Maps or Waze can follow. Your Maps app does the driving, including on CarPlay and Android Auto.',
				},
				{
					type: 'list',
					items: [
						'Google Maps takes several stops per leg. Apple Maps and Waze take one destination at a time, so you open each leg in turn.',
						'Race courses use paths, bridges and closed roads. The list under the legs shows the stretches Maps can\'t follow, so you know which parts you won\'t see.',
						'The Maps route is only a guide. The course notes follow the real course.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Drive this course is being switched on gradually. If a public course doesn\'t show **Drive this course**, it isn\'t available to you yet.',
				},
			],
		},
		{
			heading: 'Open a course in Maps',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the route or the race and select **Drive this course**.',
						'Choose your Maps app, then select **Drive to the start**.',
						'At the start, open leg 1. When a leg ends, open the next one.',
					],
				},
				{
					type: 'p',
					text: 'The web page also lists every course note with its distance, and you can print the list for a passenger.',
				},
			],
		},
		{
			heading: 'Hear the course notes on the phone',
			blocks: [
				{
					type: 'steps',
					items: [
						'In the phone app, open the route or the race and tap **Drive this course**.',
						'Read the safety notice and tap **I understand**. It only appears once on each phone.',
						'Tap **Start spoken notes**, then switch to your Maps app and lock the phone.',
					],
				},
				{
					type: 'p',
					text: 'Each aid station, cut-off, climb, hazard and note is read out about 15 seconds before you reach it, and again when you are there. If you join part way, the notes start from where you are. They stop at the finish, or after 10 minutes off the course. Tap **Stop** to end them sooner.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Use it with a passenger or a mounted phone, and don\'t touch the phone while driving. Follow road rules and signs, and remember that course roads may be closed on race day.',
				},
			],
		},
	],
};
