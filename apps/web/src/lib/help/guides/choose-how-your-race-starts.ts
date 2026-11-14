import type { Guide } from '../types';

export const guide: Guide = {
	id: 'choose-how-your-race-starts',
	title: 'Choose how your race starts',
	summary: 'Host GO, Scheduled GO or a Self-timed window: when to use each, what you do on the day, and how results are approved.',
	kind: 'how-to',
	category: 'races',
	audience: ['organiser', 'club-admin'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/clubs/[slug]/events/new', '/clubs/[slug]/events/[id]'],
	sections: [
		{
			heading: 'Three ways to start',
			blocks: [
				{
					type: 'list',
					items: [
						'**Host GO**: you arm the race and press GO at the line. Use it when you are at the start with everyone, for a mass start.',
						'**Scheduled GO**: the race starts itself at the time you set. Use it when the start time is fixed but you may not be at the line, or want to run yourself. You can delay or cancel it until then.',
						'**Self-timed window**: there is no shared start. Each runner times their own attempt between the start line and the finish line, any time the window is open. Use it for a weekly time trial, or a course people run when they can. There is no gun time.',
					],
				},
				{
					type: 'p',
					text: 'Choose under **How the race starts** in the event editor on the web, for a group run or cycle event. The phone app can run the race on the day (arm it early, delay it, extend it or end it), but the start is chosen on the web.',
				},
			],
		},
		{
			heading: 'Setting the times',
			blocks: [
				{
					type: 'list',
					items: [
						'Scheduled GO: set the **GO time** and the **GO day** (on the day, the day before or the day after the event). Under **Ends after, days** and **Hours**, set how long after GO the race ends by itself, unless you end it first.',
						'Self-timed window: set **Window opens at** and **Opens on** (from the day before the event to a week after it), and how long it stays open under **Window length, days** and **Hours**, from 1 minute to 7 days.',
					],
				},
				{
					type: 'p',
					text: "You type and see the times on the event's own clock, in its time zone. On the event page, the race panel shows that time zone and, when yours is different, your own time beside it.",
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'The times are kept relative to each occurrence of the event. Move the event, or one occurrence of it, and its race times move with it. Change the times in the editor and every occurrence that has not started yet takes the new times.',
				},
			],
		},
		{
			heading: 'On the day: Host GO',
			blocks: [
				{
					type: 'p',
					text: 'You arm the race, fire GO and end it yourself. See [[guide:race-day-for-hosts|Race day for hosts]].',
				},
			],
		},
		{
			heading: 'On the day: Scheduled GO',
			blocks: [
				{
					type: 'list',
					items: [
						'You do not need to do anything. The race is set up about a day before its start, and starts itself at the scheduled time.',
						'To check the course lines sooner, choose **Arm early**.',
						'Before the start, the race panel shows **GO at** with the time and a countdown. To push the start back, enter the minutes and choose **Delay start**; everyone going is told the start has moved. Choose **Cancel** to call the race off.',
						'Once the start time has passed, the race can no longer be cancelled. It ends itself when its time is up, or choose **End race** to end it sooner.',
						"Runners' phones count down to the start on the server's clock and speak the last seconds, so everyone starts together.",
					],
				},
			],
		},
		{
			heading: 'On the day: Self-timed',
			blocks: [
				{
					type: 'list',
					items: [
						'There is nothing to press. The window opens and closes by itself.',
						'Before it opens you can **Delay start** or **Cancel**, as for a scheduled race.',
						'While it is open, enter the hours and choose **Extend window** to keep it open longer (up to 7 days from when it opened), or choose **End window now** to close it early.',
						'When the window closes, a runner who started an attempt but sent no result is marked DNF, as when you end any race.',
					],
				},
				{
					type: 'p',
					text: 'Every course needs a start line and a finish line, and they are frozen for the race when the window opens. See [[guide:start-and-finish-lines|Start and finish lines]].',
				},
			],
		},
		{
			heading: 'Approving self-timed results',
			blocks: [
				{
					type: 'p',
					text: 'Nobody stands at the line in a self-timed race, so its results wait for you by default: **Auto-approve submitted results** starts off. Each result shows as **PENDING** until you choose **Approve**.',
				},
				{
					type: 'p',
					text: "Some results are held for your review even when auto-approve is on: one with no start-line crossing (from an older app or an Apple Watch), one that starts outside the window, and one whose crossings the runner's own live positions do not back up. A runner who changes their own time also goes back to pending.",
				},
				{
					type: 'p',
					text: 'A runner can make several attempts. Their best finish timed by both lines counts, and a slower attempt does not replace it.',
				},
			],
		},
		{
			heading: 'Starting soon notices',
			blocks: [
				{
					type: 'p',
					text: "About 10 minutes before a scheduled GO, everyone going gets a push notice that the race starts soon, unless an event reminder reached them in the last hour. When you delay a start, they get one saying it has moved. These notices are never emailed.",
				},
				{
					type: 'p',
					text: 'Runners turn both off with **Race starting soon**: on the web in [[route:/settings/notifications|Notifications]], in the phone app under **Notifications** in the **You** tab.',
				},
			],
		},
		{
			heading: 'Runners need a recent app',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Scheduled and self-timed races need the latest app on the phone or Wear OS watch. Results from older apps and from the Apple Watch are kept for your review rather than refused.',
				},
			],
		},
	],
	related: ['set-up-a-race', 'start-and-finish-lines', 'race-day-for-hosts', 'run-a-self-timed-race'],
};
