import type { Guide } from '../types';

export const guide: Guide = {
	id: 'set-up-a-race',
	title: 'Set up a race',
	summary: 'Create a club event with one or more courses so racers can pick a distance, be timed live and land on a leaderboard per course.',
	kind: 'how-to',
	category: 'races',
	audience: ['organiser', 'club-admin'],
	platforms: ['web'],
	routes: ['/clubs/[slug]', '/clubs/[slug]/events/new', '/clubs/[slug]/events/[id]'],
	sections: [
		{
			heading: 'Before you start',
			blocks: [
				{
					type: 'p',
					text: "A race is an ordinary club event with courses attached. Club owners, admins and event organisers can create events. Running the race on the day (Arm, GO, End) needs an owner, an admin or a **Race director** — see [[guide:race-day-for-hosts|Race day for hosts]]."
				},
				{
					type: 'p',
					text: 'Courses are built on the web. The phone app can create a simple event, but it has no course editor, so add or change courses from a browser.'
				}
			]
		},
		{
			heading: 'Create the event',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open your club and choose **New event**.',
						'Under **Event type**, pick **Group run** (or **Cycle**). Class and social events have no route, distance, race controls or results.',
						'Give it a **Title** and a **Date**. Set a repeat only if the race really recurs; each occurrence is raced separately.',
						'Choose a **Route** and fill in **Distance**. Together these are your *main course*.',
						'Optionally type a **Main course name** under **Race courses** (for example "Half marathon"). If you leave it blank, the route name is used.',
						'Choose **Create event**.'
					]
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'The finish line racers are timed at is the last point of the course route. Draw the route so it ends exactly where your finish arch will be.'
				}
			]
		},
		{
			heading: 'Add more courses',
			blocks: [
				{
					type: 'p',
					text: 'Racing more than one distance on the same day? Add each extra distance as its own course. Every course gets its own leaderboard.'
				},
				{
					type: 'steps',
					items: [
						'In the event editor, find **Race courses** and choose **Add a course**.',
						'Give it a **Course name**, pick its **Route** and enter its distance.',
						'Use the up and down arrows to reorder courses, or remove one you no longer need.',
						'Save the event.'
					]
				},
				{
					type: 'list',
					items: [
						'Every course needs a name, and no two courses can share one.',
						'A course with no route has no finish point, so its racers are not finished automatically; they finish by hand from their device.',
						'A course with no distance cannot check that a racer covered most of the course, so its racers also finish by hand.'
					]
				},
				{
					type: 'note',
					tone: 'caution',
					text: "Attaching a route shows its finish point to everyone who can see the event, even if the route itself is private. You can only attach routes you are allowed to see."
				}
			]
		},
		{
			heading: 'What racers see',
			blocks: [
				{
					type: 'list',
					items: [
						"On the event page racers see the courses. When there is more than one, they must choose one from **Your course** before **I'm in** will work; otherwise they see \"Pick your course first.\"",
						'In the phone app, tapping **I\'m in** on a multi-course race asks them to **Pick your course**, and they can use **Change course** later.',
						'With a single course, nobody has to choose anything.',
						'Paid registrations do not ask for a course yet. A paid racer picks one afterwards from the same **Your course** menu.'
					]
				},
				{
					type: 'p',
					text: 'The racer side is covered in [[guide:racing-in-a-race|Racing in a race]].'
				}
			]
		},
		{
			heading: 'Approving results automatically',
			blocks: [
				{
					type: 'p',
					text: 'Just before you arm the race you choose whether results go straight onto the leaderboard. **Auto-approve submitted results** is ticked by default. Untick it if you want to check every result first; each one then shows as **PENDING** until you approve it.'
				}
			]
		},
		{
			heading: 'Share the spectator link',
			blocks: [
				{
					type: 'p',
					text: 'Every race occurrence has a live page with a map and boards. On the event page, the race control card has a **Spectator view** link that opens it in a new tab. Copy that address and share it with family, friends and your race channel.'
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'For a **Members only** event, only club members can see the event, so the spectator page will not work for people outside the club.'
				},
				{
					type: 'p',
					text: 'What spectators see is explained in [[guide:follow-a-race-live|Follow a race live]].'
				}
			]
		}
	],
	related: ['race-day-for-hosts', 'racing-in-a-race', 'follow-a-race-live', 'race-results-explained']
};
