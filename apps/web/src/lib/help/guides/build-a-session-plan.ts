import type { Guide } from '../types';

export const guide: Guide = {
	id: 'build-a-session-plan',
	title: 'Build a session plan for yoga, pilates or mobility',
	summary: 'Write a timed sequence of holds, flows and reps with per-side movements and cues, then teach from it, attach it to a class and follow along.',
	kind: 'how-to',
	category: 'instructors',
	audience: ['instructor', 'runner'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/plans/new', '/sessions', '/sessions/[id]', '/clubs/[slug]', '/clubs/[slug]/events/[id]'],
	sections: [
		{
			heading: 'Where to build it',
			blocks: [
				{
					type: 'p',
					text: 'Session plans are written on the web. The phone app lists them and runs them, but has no editor yet.'
				},
				{
					type: 'list',
					items: [
						'For yourself: open [[route:/plans/new|New plan]] and pick **Session plan**, or press **New session** on [[route:/sessions|Sessions]].',
						'For your club: on the club\'s **Templates** tab, press **Add template** and pick **Session plan**. It is saved as a club template straight away.'
					]
				}
			]
		},
		{
			heading: 'Fill it in',
			blocks: [
				{
					type: 'steps',
					items: [
						'Give it a **Title** that names the sequence, such as "Hip opener flow, 45 min".',
						'Add a **Discipline** (for example Vinyasa yoga) and the **Equipment** people should have out, such as a mat or a reformer.',
						'Optionally press **Add block** to split it into sections like Warm-up, Standing and Cool-down. A plan with no blocks runs straight through.',
						'Press **Add movement** for each pose or exercise and type its name in **Movement**.',
						'Pick its **Type**: **Hold** for a timed pose, **Flow** for a timed sequence of movement, or **Reps** for a counted exercise. Then enter the **Seconds** or **Reps**, and the **Block** it belongs to.',
						'Tick **Per side (left & right)** for anything done on each side. It runs once each way, so it takes twice as long.',
						'Optionally add a **Tempo** and a **Cue**, the breath or alignment prompt shown beside the movement while someone follows along.',
						'Check the estimated length the editor works out for you, then press **Save**.'
					]
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Movement names are suggested from your earlier plans as you type. Picking a suggestion keeps the same pose spelled the same way everywhere.'
				}
			]
		},
		{
			heading: 'Attach it to a class',
			blocks: [
				{
					type: 'list',
					items: [
						'When creating a class, pick the plan under **Session plan**.',
						'Already created the class? On the class page, organisers press **Attach to a class event** in the **Session sequence** card.'
					]
				},
				{
					type: 'p',
					text: 'Attendees then see the full sequence on the class page. A private plan stays private to everyone else, but the people at a class you attach it to can see it.'
				}
			]
		},
		{
			heading: 'Follow along',
			blocks: [
				{
					type: 'p',
					text: 'Open the plan and press **Start session**. Timed holds and flows move on by themselves; for reps, press **Done** when finished. You can **Pause**, **Resume**, **Skip** a step, or **Abandon**. When you finish it is saved to your gym log as a workout.'
				},
				{
					type: 'p',
					text: 'The phone app runs the same follow-along, reads the cues aloud, keeps the screen awake, and keeps time if you switch to another app.'
				}
			]
		},
		{
			heading: 'Share it',
			blocks: [
				{
					type: 'list',
					items: [
						'**Make public** lets anyone find and follow it. **Copy share link** makes the plan public and copies a link that works without signing in.',
						'**Publish to a club**: pick the club from **Pick a club…** and press **Publish**. It appears under **Session templates** on the club\'s **Templates** tab, and members press **Adopt** to get their own copy.'
					]
				}
			]
		}
	],
	related: ['host-a-paid-yoga-class', 'build-a-gym-routine', 'take-attendance']
};
