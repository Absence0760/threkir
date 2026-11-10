import type { Guide } from '../types';

export const guide: Guide = {
	id: 'run-a-self-timed-race',
	title: 'Run a self-timed race',
	summary: 'Join a race that is open for a window of time, mark your run as your attempt, and run from the start line to the finish line whenever suits you.',
	kind: 'how-to',
	category: 'races',
	audience: ['participant', 'runner'],
	platforms: ['web', 'android', 'ios', 'wear'],
	routes: ['/clubs/[slug]/events/[id]'],
	sections: [
		{
			heading: 'What a self-timed race is',
			blocks: [
				{
					type: 'p',
					text: 'A self-timed race has no group start. The organiser opens a window, which can last up to a week, and you run the course whenever you like while it is open. Your time runs from when you cross the start line to when you cross the finish line, so there is no gun time.',
				},
				{
					type: 'p',
					text: 'You record your attempt with the phone app or a Wear OS watch. The web is for joining and for seeing results; a browser cannot record a run.',
				},
			],
		},
		{
			heading: 'Before you go',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the race event, on the web or in the phone app.',
						'If there is more than one course, choose yours first.',
						"Choose **Join and attempt**. If you have already said **I'm in**, you are already in.",
						'Open the app once while you have signal, before you set off. It then knows about the race, so the race banner and your attempt still work where there is no signal.',
					],
				},
			],
		},
		{
			heading: 'Start your attempt',
			blocks: [
				{
					type: 'steps',
					items: [
						'On the Run tab of the phone app, the race banner shows **Self-timed** and when the window closes.',
						'Tap **This run is my attempt**. It changes to **Attempt ready: tap Start**; tap it again if you change your mind.',
						'Press Start before you reach the start line, then run through the start line the way the course goes.',
					],
				},
				{
					type: 'p',
					text: 'On a Wear OS watch, the screen before you start shows SELF-TIMED. Tap **This run is my attempt**, then Start.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: "A run you do not mark as your attempt never joins the race: it sends no live position and gets no result. That way a run you did not mean to race never lands on the board.",
				},
			],
		},
		{
			heading: 'Attempts and your result',
			blocks: [
				{
					type: 'list',
					items: [
						'You can make more than one attempt while the window is open. Tap **This run is my attempt** before each one.',
						'Your best finish timed by both lines counts. A slower attempt does not replace it.',
						'Your result may wait for the organiser to approve it. Until then it shows as pending and has no place.',
						"A result with no start-line crossing, such as one sent from an Apple Watch or an older version of the app, is kept, but the organiser reviews it before it counts.",
					],
				},
				{
					type: 'p',
					text: 'What the times on the board mean is in [[guide:race-results-explained|Race results explained]].',
				},
			],
		},
	],
	related: ['racing-in-a-race', 'race-results-explained', 'follow-a-race-live'],
};
