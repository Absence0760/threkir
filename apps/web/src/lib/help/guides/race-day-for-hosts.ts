import type { Guide } from '../types';

export const guide: Guide = {
	id: 'race-day-for-hosts',
	title: 'Race day for hosts',
	summary: 'Arm the race, fire GO, watch it live, end it, then approve and correct the results.',
	kind: 'how-to',
	category: 'races',
	audience: ['organiser'],
	requires: ['race-director'],
	platforms: ['web', 'android'],
	routes: ['/clubs/[slug]/events/[id]', '/live/event/[id]/[instance]'],
	sections: [
		{
			heading: 'Who can run a race',
			blocks: [
				{
					type: 'p',
					text: 'Race control appears on the event page for club owners, admins and members with the **Race director** role. On the web it is the **Race control** card; in the phone app it is the **RACE CONTROL** card on the event screen. Approving and editing results is web only.'
				},
				{
					type: 'p',
					text: 'Make sure the event has courses first — see [[guide:set-up-a-race|Set up a race]].'
				}
			]
		},
		{
			heading: '1. Arm the race',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the event and pick today\'s occurrence if it repeats.',
						'Leave **Auto-approve submitted results** ticked to publish results as they arrive, or untick it to approve each one yourself. (In the phone app it reads **Auto-approve submitted times**.)',
						'Choose **Arm race** when everyone is gathered.'
					]
				},
				{
					type: 'p',
					text: 'Racers who said **I\'m in** now see **Race armed** on their phone\'s Run tab and "RACE ARMED" on their Wear OS watch.'
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Armed is a waiting state. Nothing is timed and no results can be saved until you fire GO.'
				}
			]
		},
		{
			heading: '2. Fire GO',
			blocks: [
				{
					type: 'p',
					text: 'Press **GO** on the web (**Fire Go** in the phone app) at the moment the race starts.'
				},
				{
					type: 'p',
					text: "The start time is stamped by our server, not by your device, so it is the same gun time for every racer even if your phone's clock is a few seconds off. Each racer's gun time is measured from it."
				},
				{
					type: 'note',
					tone: 'caution',
					text: "GO does not start anyone's recording. Racers still press Start on their own phone or watch. Remind them to start after they see **Race LIVE**."
				}
			]
		},
		{
			heading: '3. Watch it live',
			blocks: [
				{
					type: 'list',
					items: [
						'The race control card shows **Running** with the elapsed time.',
						'Choose **Spectator view** for the live map, the **On course** board and the **Finished** board. See [[guide:follow-a-race-live|Follow a race live]].',
						"Racers' devices finish them automatically at the finish line, so results appear on the event page while the race is still running."
					]
				}
			]
		},
		{
			heading: '4. End the race',
			blocks: [
				{
					type: 'steps',
					items: [
						'When the last racer is in (or your cut-off has passed), choose **End race**.',
						'On the web the confirmation tells you how many racers who started have no result. Those racers will be marked DNF.',
						'Confirm with **End race**.'
					]
				},
				{
					type: 'p',
					text: 'Ending files a DNF for every racer who sent at least one live position but has no result, using the distance and time from their last position. These DNFs carry the host mark. Racers who never started recording get nothing filed.'
				},
				{
					type: 'p',
					text: 'A racer whose phone or watch was out of signal at the finish can still send a queued result for up to 24 hours after you end the race, and it replaces the DNF.'
				},
				{
					type: 'note',
					tone: 'caution',
					text: "Ending cannot be undone. Once ended, racers' devices stop expecting a result. To race the same occurrence again, arm a new session."
				}
			]
		},
		{
			heading: 'Cancelling',
			blocks: [
				{
					type: 'p',
					text: 'On the web you can cancel only while the race is armed: choose **Cancel** next to **GO**, then **Cancel race**. In the phone app, **Cancel** is offered while armed and **Cancel race** while running.'
				},
				{
					type: 'p',
					text: 'Cancelling files no DNFs. The spectator page says the race was cancelled by the organiser, and racers see that the race has ended.'
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Cancelling cannot be undone. Use **End race** instead if people actually raced and you want their results.'
				}
			]
		},
		{
			heading: 'Approve and edit results',
			blocks: [
				{
					type: 'p',
					text: 'Results are on the event page under **Results**, with one board per course. This part is on the web only.'
				},
				{
					type: 'list',
					items: [
						'If auto-approve was off, new results show **PENDING** and no place. Choose **Approve** to publish one. **Unverify** puts an approved result back into pending.',
						'To correct a result, choose **Edit**, enter a **Time (h:mm:ss)** and a **Status** (**Finished**, **DNF** or **DNS**), then **Save result**.',
						'An edited result is marked **Host edited** so everyone can see it was changed by the host. The edit moves the racer\'s gun time with it.',
						'**Download results CSV** exports the boards.'
					]
				}
			]
		}
	],
	related: ['set-up-a-race', 'follow-a-race-live', 'race-results-explained', 'racing-in-a-race']
};
