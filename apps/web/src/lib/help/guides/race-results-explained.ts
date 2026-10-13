import type { Guide } from '../types';

export const guide: Guide = {
	id: 'race-results-explained',
	title: 'Race results explained',
	summary: 'What gun and chip time mean, how places are worked out per course, and what the Auto, Manual, Host, DNF, DNS and pending marks say.',
	kind: 'explainer',
	category: 'races',
	audience: ['everyone'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/clubs/[slug]/events/[id]', '/live/event/[id]/[instance]'],
	sections: [
		{
			heading: 'Gun time and chip time',
			blocks: [
				{
					type: 'list',
					items: [
						'**Gun time** is measured from the moment the host fired GO to the moment you crossed the finish. GO is stamped by our server, so everyone in the race shares the same start.',
						'**Chip time** is measured from when you pressed Start on your own device to your finish, including any pauses.',
						'The big time on the board is your gun time when the race had a GO, otherwise your chip time. Places are worked out from that big time.'
					]
				},
				{
					type: 'p',
					text: 'On the web the smaller line under a time reads like "gun 41:58 · chip 41:20". In the phone app, a "Chip" time is shown under the main time when it differs from it. If you started late, your gun time is longer than your chip time.'
				}
			]
		},
		{
			heading: 'Places are per course',
			blocks: [
				{
					type: 'p',
					text: 'When a race has more than one course, each course has its own board and its own places. A 5K finisher is never ranked against a 10K finisher. Results with no course are grouped together (**No course** on the event page, **Other** on the live page).'
				},
				{
					type: 'p',
					text: 'Only finishers get a place. Ties are broken by whoever\'s result arrived first.'
				}
			]
		},
		{
			heading: 'How the finish was recorded',
			blocks: [
				{
					type: 'list',
					items: [
						"**Auto**: the racer's phone or watch detected the finish line. The phone app shows this badge; the web shows no badge for it, because it is the normal case.",
						'**Manual**: the racer finished by hand, either with **Finish race** after covering at least 90% of the course, or by using **Submit my time** on the web during the race.',
						'**Host** (on the web, **Host edited**): the host entered or corrected this result, or the racer was marked DNF when the host ended the race.'
					]
				}
			]
		},
		{
			heading: 'DNF and DNS',
			blocks: [
				{
					type: 'list',
					items: [
						'**DNF** (did not finish): the racer started but did not finish. This happens when someone chooses **Finish as DNF** before covering 90% of the course, when the host ends the race while they are still out, or when the host records it.',
						'**DNS** (did not start): recorded by the racer with **Record DNS** or by the host.',
						'Neither gets a place. On the live page they are listed under **Did not finish**.'
					]
				}
			]
		},
		{
			heading: 'Pending results',
			blocks: [
				{
					type: 'p',
					text: 'If the host turned off auto-approve, each new result waits for the host. On the event page it shows **PENDING** with no place yet; on the live page it shows **Pending**. Once the host chooses **Approve**, it takes its place on the board.'
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'A finisher **Certificate** can be downloaded only once a finished result has been approved.'
				}
			]
		},
		{
			heading: 'Something looks wrong',
			blocks: [
				{
					type: 'list',
					items: [
						'No result at all? If your device had no signal at the finish, it sends the result when it reconnects, within 24 hours of the race ending.',
						'A DNF you think is wrong, or a time that is off? Ask the host. They can correct it on the web, and the result will then show the host mark.'
					]
				},
				{
					type: 'p',
					text: 'For the racer side, see [[guide:racing-in-a-race|Racing in a live race]]. Hosts: [[guide:race-day-for-hosts|Race day for hosts]].'
				}
			]
		}
	],
	related: ['racing-in-a-race', 'race-day-for-hosts', 'follow-a-race-live', 'using-help']
};
