import type { Guide } from '../types';

export const guide: Guide = {
	id: 'what-pro-includes',
	title: 'What Pro includes',
	summary: 'Almost everything in Threkir is free; Pro raises your AI Coach allowance, adds a few AI extras and moves some background work up the queue.',
	kind: 'explainer',
	category: 'account',
	audience: ['everyone'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/settings/upgrade', '/messages/coach'],
	sections: [
		{
			heading: 'What stays free',
			blocks: [
				{
					type: 'p',
					text: 'Almost nothing in the app is locked behind Pro. Free accounts get unlimited recording on phone and watch, routes, training plans and the numbers behind them, clubs and events, the social feed, safety contacts, imports and backups.',
				},
			],
		},
		{
			heading: 'What Pro adds',
			blocks: [
				{
					type: 'list',
					items: [
						'**AI Coach — 10/day**: ten Coach messages a day instead of two. The count resets at midnight UTC.',
						'Longer, more thorough Coach answers that can take more of your runs into account.',
						'**Priority map-matching**: your GPS tracks are snapped to roads ahead of free accounts, so they are ready sooner.',
						'**Priority cloud exports**: up to 8 GPX bundle exports an hour instead of 2.',
						'**Server route generation**: loops traced on the real street network when you generate a route by distance. Free accounts still get loop generation, worked out in the browser.',
						'Richer route descriptions: on a route\'s page, **Enhance with AI** turns the standard description into a fuller paragraph.',
						'**Log from a photo**: photograph a meal and get your food log filled in for you to check. See [[guide:log-a-meal-from-a-photo|Log a meal from a photo]].',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Some of these depend on services that may not be switched on yet. The Pro card in [[route:/settings/upgrade|Pro & support]] only lists what is working today; if it says **Pro unlocks the AI Coach — coming soon.**, Pro can\'t be bought yet.',
				},
			],
		},
		{
			heading: 'How to get Pro',
			blocks: [
				{
					type: 'p',
					text: 'Pro is a monthly or yearly subscription; the Pro card shows the current prices. Where you can buy it depends on your device:',
				},
				{
					type: 'list',
					items: [
						'On an iPhone, open **Pro & support** in the **You** tab and subscribe through the App Store.',
						'On the web, open [[route:/settings/upgrade|Pro & support]] in Settings. If it says **Subscribing on the web is coming soon.**, subscribe in the iPhone app instead.',
					],
				},
				{
					type: 'p',
					text: 'Pro belongs to your account, not your device, so a subscription bought on one device works everywhere you sign in.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Prices are in US dollars, and the App Store charges the price set for your country. Some countries and payment methods can\'t be served by our payment processor.',
				},
			],
		},
		{
			heading: 'Managing or cancelling',
			blocks: [
				{
					type: 'list',
					items: [
						'Cancel or change your plan where you started it: the App Store, the Play Store, or the web billing portal. **Manage subscription** takes you there.',
						'On a new phone, tap **Restore purchases** in **Pro & support** to bring an existing subscription across.',
						'Prefer a one-off contribution? **Donate** is on the same page.',
					],
				},
			],
		},
	],
	related: ['your-data-and-privacy', 'log-a-meal-from-a-photo', 'using-help'],
};
