import type { Guide } from '../types';

export const guide: Guide = {
	id: 'follow-a-race-live',
	title: 'Follow a race live',
	summary: "Watch a race as it happens on the live race page: runners on a map, who is on course, and who has finished on each course.",
	kind: 'how-to',
	category: 'races',
	audience: ['spectator', 'everyone'],
	platforms: ['web'],
	routes: ['/live/event/[id]/[instance]'],
	sections: [
		{
			heading: 'Open the live page',
			blocks: [
				{
					type: 'p',
					text: 'The host shares a link to the live race page, or, if you can see the event, open it and choose **Spectator view**. You do not need an account. If the event is **Members only**, you need to be a club member to see it.'
				},
				{
					type: 'p',
					text: 'The top of the page shows the race state:'
				},
				{
					type: 'list',
					items: [
						'**Pre-race**: the organiser has not armed the race timer yet.',
						'**Armed**: the timer is armed and waiting for the start.',
						'**Running**: the race is on, with the elapsed time.',
						'**Finished**: the race is over.',
						'**Cancelled**: the organiser cancelled the race.'
					]
				},
				{
					type: 'p',
					text: 'A race with a scheduled start shows **Armed** with the time it starts by itself. A self-timed race shows **Self-timed window** with when it opens, then **Self-timed window open** with when it closes: each runner starts when they cross the start line.'
				}
			]
		},
		{
			heading: 'The map',
			blocks: [
				{
					type: 'p',
					text: "Unless you have already allowed maps in your cookie settings, the map stays off until you choose **Load map**, because loading it sends your IP address to our map tile provider. Once loaded, each runner is a coloured dot with a short trail of their recent path. Runners' phones and watches send a position about every 10 seconds, and the page updates on its own."
				},
				{
					type: 'illustration',
					id: 'follow-a-race-live',
					alt: 'A course on a map with runners along it, each a coloured dot with a short trail of their recent path, and a flag at the finish.',
				},
				{
					type: 'p',
					text: "The map also draws each course's start and finish lines, the ones the race was armed with.",
				},
			]
		},
		{
			heading: 'On course',
			blocks: [
				{
					type: 'p',
					text: 'The **On course** board lists every runner who has sent a position, furthest first, with distance, pace and elapsed time, with one board per course when the race has more than one. Each row also says how long ago it was last updated.'
				},
				{
					type: 'p',
					text: 'There is no separate "paused" label. A runner who has stopped (to tie a lace, at an aid station, or because they paused their recording) or who has lost signal simply stops updating. After about 90 seconds without an update their row is marked **DELAYED**. That does not mean anything is wrong; it often just means no signal.'
				},
				{
					type: 'p',
					text: 'In a self-timed race, runners are ordered by how long ago they crossed the start line, longest first. Runners with no start-line time yet are listed after them, under **No start-line time yet**.'
				}
			]
		},
		{
			heading: 'Finished',
			blocks: [
				{
					type: 'p',
					text: 'Finishers appear under **Finished** as their results arrive, with one board per course when the race has more than one. Runners who did not finish are listed under **Did not finish**. A result the host has not approved yet is marked **Pending**.'
				},
				{
					type: 'p',
					text: 'What the times and badges mean is in [[guide:race-results-explained|Race results explained]].'
				}
			]
		},
		{
			heading: 'Privacy',
			blocks: [
				{
					type: 'list',
					items: [
						"Runners' real names are shown only to people connected to them by a follow, in either direction. Everyone else sees an anonymous handle such as Runner #A1B2.",
						'Near a runner\'s privacy zone, their exact position is hidden. You see **Last seen near here · approximate** instead, shown as a hollow ring rather than a dot.',
						'Finishers imported by the host from a bib list have no account, so they keep the name the host entered.'
					]
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Anyone with the link can watch. If you are racing and would rather not be followed live, talk to the host before the race.'
				}
			]
		}
	],
	related: ['race-results-explained', 'racing-in-a-race', 'run-a-self-timed-race', 'race-day-for-hosts']
};
