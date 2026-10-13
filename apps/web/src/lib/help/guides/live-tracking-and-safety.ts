import type { Guide } from '../types';

export const guide: Guide = {
	id: 'live-tracking-and-safety',
	title: 'Live tracking and safety contacts',
	summary: 'Let someone follow your run live, and have trusted contacts emailed when you finish, go quiet or are not back on time.',
	kind: 'how-to',
	category: 'running',
	audience: ['runner', 'spectator'],
	platforms: ['android', 'ios', 'web'],
	routes: ['/live/[id]', '/settings/safety', '/safety/confirm'],
	sections: [
		{
			heading: 'Share a live link',
			blocks: [
				{
					type: 'steps',
					items: [
						'Sign in on the phone app. A live link only works for a signed-in runner.',
						'On the run screen, before you start, tap **Share live link** and send it with any app on your phone.',
						'Tap **START**. The link goes live as the run begins.',
					],
				},
				{
					type: 'p',
					text: 'Whoever has the link can open it in a web browser and watch your position and stats, with no account needed. Privacy zones still apply to the live map.',
				},
				{
					type: 'p',
					text: 'While sharing, a **Live** badge shows on the recording screen. Tap it to **Share link again**, **Stop sharing**, or set a **Not back by…** time.',
				},
				{
					type: 'p',
					text: 'When the run ends, the link stops updating. If your runs are normally not public, you are asked whether to **Keep public** the saved run for people with the link; otherwise it goes back to your usual run privacy.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'To share every run without remembering to, turn on **Auto live share** under **Safety contacts** in the **You** tab. It applies to that phone only, and the run in progress can be viewed by anyone with the link.',
				},
			],
		},
		{
			heading: 'Add safety contacts',
			blocks: [
				{
					type: 'p',
					text: 'A safety contact is someone you trust, such as a partner, friend or family member. They are emailed when you finish a run, even a private one, so they know you got back.',
				},
				{
					type: 'steps',
					items: [
						'On the web open [[route:/settings/safety|Safety]] in Settings, or in the phone app open **Safety contacts** in the **You** tab.',
						'Enter their **Contact email**. You can also add a **Phone for SMS (optional)** in international format, such as +447700900123.',
						'Select **Add contact**. They get an email asking them to confirm.',
						'Their status shows **Pending — waiting for them to confirm** until they accept, then **Confirmed**. Only confirmed contacts are alerted.',
					],
				},
				{
					type: 'p',
					text: 'If someone adds you as their contact, the request appears under **Requests for you**, where you can **Confirm** or **Decline**. Later, under **You are a safety contact**, you can change how you are alerted or **Withdraw**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Email alerts are always sent. Text messages also need the contact to agree when they confirm, and SMS sending is not switched on everywhere yet, so don\'t rely on SMS alone.',
				},
			],
		},
		{
			heading: 'Alerts when something seems wrong',
			blocks: [
				{
					type: 'p',
					text: 'These alerts only cover runs with live sharing on, because the live link is what tells us where you are. Each contact gets at most one alert per run.',
				},
				{
					type: 'list',
					items: [
						'**Overdue alert**: choose a time under **Alert contacts after silence of** on the web, or **Alert after silence of** in the app. If your live run sends nothing for that long, your confirmed contacts are emailed your live link. It is **Off** until you pick a time.',
						'**Not back by…**: during a live-shared run, tap the **Live** badge and pick when you expect to be done. If the run is still going then, your contacts are alerted. The time is kept on our server, so it still counts if your phone dies. You can also set it from your own live page on the web.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Losing phone signal looks the same as going quiet, and a run that finishes with no signal can still trigger an alert until it uploads. The email tells your contacts that signal loss is a possible cause.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'An automatic alert to your contacts when you leave your planned route is built but not switched on yet. Until it is, the **Off-route alert** setting stays hidden.',
				},
			],
		},
		{
			heading: 'Off-route warnings while you run',
			blocks: [
				{
					type: 'p',
					text: 'If you follow a saved route, the run screen warns you when you stray from it, showing how far away you are, and can say so out loud if audio cues are on. This warning is for you; it does not contact anyone.',
				},
			],
		},
	],
	related: ['privacy-zones', 'record-your-first-run', 'racing-in-a-race'],
};
