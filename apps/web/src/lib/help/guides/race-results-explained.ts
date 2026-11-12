import type { Guide } from '../types';

export const guide: Guide = {
	id: 'race-results-explained',
	title: 'Race results explained',
	summary: 'What gun and chip time mean, how places are worked out, what the Manual, Host, DNF, DNS and pending marks say, and how to re-time from your track.',
	kind: 'explainer',
	category: 'races',
	audience: ['everyone'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/clubs/[slug]/events/[id]', '/live/event/[id]/[instance]', '/runs/[id]'],
	sections: [
		{
			heading: 'Gun time and chip time',
			blocks: [
				{
					type: 'list',
					items: [
						'**Gun time** is measured from the moment the host fired GO to the moment you crossed the finish. GO is stamped by our server, so everyone in the race shares the same start.',
						'**Chip time** is measured from when you crossed the course\'s start line to your finish. If your phone or watch saw no start-line crossing, it runs from when you pressed Start on your own device, including any pauses.',
						'A self-timed race has no GO, so it has no gun time: its board shows your chip time, from the start line to the finish line.',
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
						"**No badge**: the racer's phone or watch timed the finish, at the moment they crossed the finish line, or at the 30 m circle around the finish on a course with no finish line. This is the normal case, so neither the web nor the phone app marks it.",
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
					text: 'If the host turned off auto-approve, each new result waits for the host. On the web event page it shows **PENDING** with no place yet; in the phone app and on the live page it shows **Pending**. Once the host chooses **Approve**, it takes its place on the board.'
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'A finisher **Certificate** can be downloaded only once a finished result has been approved.'
				}
			]
		},
		{
			heading: 'Re-time from your track',
			blocks: [
				{
					type: 'p',
					text: 'If your phone missed a line, your result is a DNF you did not expect, or you raced with an Apple Watch, you can time your result again from the run you recorded. Open the run on the web: if it belongs to a race, it shows **Re-time from my track** with your current result beside the one your track gives.'
				},
				{
					type: 'steps',
					items: [
						'Check the two columns: gun time, chip time, and whether the start and the finish were timed by the line.',
						'Choose **Re-time result**, then **Replace result**.'
					]
				},
				{
					type: 'list',
					items: [
						'It times your track by the start and finish lines the race was run with, on the same clock your phone or watch used during the race.',
						'You can re-time until 24 hours after the race finished. After that, your time, course and distance are locked, and only the organiser can change your time.',
						'It replaces a DNF, a time finished by hand and a result waiting for review. It never replaces a time the organiser set, or a result already timed by both lines; in a self-timed race, only a faster attempt timed by both lines replaces it.',
						'If the organiser approves results by hand, a re-timed result goes back to them for approval.'
					]
				}
			]
		},
		{
			heading: 'Something looks wrong',
			blocks: [
				{
					type: 'list',
					items: [
						'No result at all? If your device had no signal at the finish, it sends the result when it reconnects, within 24 hours of the race ending. Within the same 24 hours you can also re-time it from your track.',
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
