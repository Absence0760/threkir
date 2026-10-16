import type { Guide } from '../types';

export const guide: Guide = {
	id: 'location-permission',
	title: 'Location access for recording runs',
	summary: 'Which location option to pick on Android and iPhone, what each one means for your runs, and how to change it later in Settings.',
	kind: 'how-to',
	category: 'running',
	audience: ['runner'],
	platforms: ['android', 'ios'],
	sections: [
		{
			heading: 'Why the app asks for your location',
			blocks: [
				{
					type: 'p',
					text: 'Your location draws the map of a run and measures its distance and pace. Without it a run still records time and steps, but no map, distance or pace.',
				},
				{
					type: 'p',
					text: 'You are asked during setup: after the **Location access** page, tapping **Grant permission** opens your phone\'s own prompt. If you decline, the app tells you so and offers **Open settings**. If you still haven\'t allowed it when you tap **START**, your phone may ask again.',
				},
			],
		},
		{
			heading: 'On Android',
			blocks: [
				{
					type: 'p',
					text: 'Android\'s first prompt can only give access while the app is in use. Keeping the run tracked with the screen off needs **Allow all the time**, which Android only lets you choose in Settings.',
				},
				{
					type: 'steps',
					items: [
						'In the prompt, leave **Precise** selected and tap **While using the app**.',
						'Before your first run the app shows **Allow location all the time**. Tap **Open settings**.',
						'Under **Permissions**, tap **Location** and choose **Allow all the time**, then go back to the app.',
					],
				},
				{
					type: 'p',
					text: 'If you tap **Start anyway**, the run records normally while the app is on screen. With the screen off or another app open, Android may stop sending your location: the clock keeps running and nothing already recorded is lost, but distance covered while you were away is not counted. When that happens, a message starting **Tracking paused while you were away** appears as you come back, with a **Settings** button.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'The reminder before a run appears once. It comes back only if you allowed all the time and that access was later removed, for example by Android resetting the permissions of apps you haven\'t opened in a while.',
				},
				{
					type: 'list',
					items: [
						'**Approximate** location is too rough to measure a run: you will see **Approximate location — distance paused** for the whole run.',
						'**Only this time** works for the run you are about to start, and you are asked again next time.',
						'**Don\'t allow** leaves runs with time and steps only.',
					],
				},
			],
		},
		{
			heading: 'On iPhone',
			blocks: [
				{
					type: 'p',
					text: 'On iPhone, access while the app is in use is enough: a run keeps recording with the screen locked or while you use another app. The app never asks for **Always**, and you don\'t need it.',
				},
				{
					type: 'steps',
					items: [
						'In the prompt, tap **Allow While Using App**.',
						'Leave precise location switched on in the prompt. Without it your position is too rough to measure distance, and the run shows **Approximate location — distance paused**.',
					],
				},
				{
					type: 'p',
					text: '**Allow Once** works for this run only, and you are asked again next time. **Don\'t Allow** leaves runs with time and steps only.',
				},
			],
		},
		{
			heading: 'Battery savers',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Some Android phones (Samsung, Xiaomi, OnePlus and others) put apps to sleep to save battery, which can stop a long run recording with the screen off, even with **Allow all the time**. Before your first run the app shows **Keep recording alive in the background** once: tap **Open settings** and exclude Threkir from battery optimisation. If you tapped **Not now**, open the app\'s page in your phone\'s Settings, tap **Battery** and choose **Unrestricted**. The names differ a little from one phone maker to another.',
				},
			],
		},
		{
			heading: 'Change it later',
			blocks: [
				{
					type: 'p',
					text: 'On Android:',
				},
				{
					type: 'steps',
					items: [
						'Open your phone\'s **Settings** and tap **Apps**, then **Threkir**.',
						'Tap **Permissions**, then **Location**.',
						'Choose **Allow all the time** and switch on **Use precise location**.',
					],
				},
				{
					type: 'p',
					text: 'On iPhone:',
				},
				{
					type: 'steps',
					items: [
						'Open **Settings** › **Privacy & Security** › **Location Services**, and check **Location Services** is on.',
						'Tap **Threkir** and choose **While Using the App**.',
						'Switch on **Precise Location**.',
					],
				},
				{
					type: 'p',
					text: 'If location is off or blocked when you start a run, the run screen says so and its **Settings** button takes you to the right place.',
				},
			],
		},
		{
			heading: 'What the app does with your location',
			blocks: [
				{
					type: 'list',
					items: [
						'It reads your location while you record a run, and when a map centres on you, such as while you build a route or place a privacy zone. It does not follow you between runs.',
						'On Android, a notification shows while a run is recording, if you allow notifications.',
						'A run\'s track stays on your phone until it syncs to your account or you share it, and who can see it follows your privacy settings: see [[guide:your-data-and-privacy|your data and privacy]].',
						'To hide where you live, set up [[guide:privacy-zones|privacy zones]]. Your live position is only shared if you turn on [[guide:live-tracking-and-safety|live tracking]].',
					],
				},
			],
		},
	],
	related: ['record-your-first-run', 'privacy-zones', 'your-data-and-privacy', 'live-tracking-and-safety'],
};
