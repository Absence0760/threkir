import type { Guide } from '../types';

export const guide: Guide = {
	id: 'notifications-reactions-and-mentions',
	title: 'Reactions, mentions and your notifications',
	summary: 'React to runs, like comments and mention other runners, then choose which notifications also reach your email and phone.',
	kind: 'how-to',
	category: 'account',
	audience: ['everyone'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/settings/notifications', '/runs/[id]'],
	sections: [
		{
			heading: 'React, like and mention',
			blocks: [
				{
					type: 'list',
					items: [
						'On someone else\'s run, next to the kudos, pick a reaction: **On fire**, **Strong**, **Champion**, **Nice** or **Hello**. You can leave more than one, and choosing one again takes it back.',
						'To like a comment, choose the heart beside it. You can\'t react to your own run or like your own comment.',
						'To mention someone in a comment, type @ and the start of their name, then pick them from the list that appears. They are notified only if they can already see the run and neither of you has blocked the other.',
					],
				},
				{
					type: 'p',
					text: 'Reactions and comment likes show on the run itself. Cards in the feed still show only kudos and comment counts.',
				},
			],
		},
		{
			heading: 'Where notifications show up',
			blocks: [
				{
					type: 'p',
					text: 'Every notification lands in the app: under the bell on the web, and on the **Notifications** tab of your profile in the phone app. Whether it also reaches your email or your phone is up to you.',
				},
			],
		},
		{
			heading: 'Choose what is emailed and pushed',
			blocks: [
				{
					type: 'steps',
					items: [
						'On the web, open [[route:/settings/notifications|Notifications]] in Settings. In the phone app, open **Preferences** in the **You** tab and scroll to **Notifications**.',
						'Set **Email notifications** and **Push notifications** separately.',
					],
				},
				{
					type: 'list',
					items: [
						'**Important only**, the default: things you are waiting on or that change your plans, such as messages, event reminders and cancellations, a waitlist place held for you, mentions, follow requests and a finished data export.',
						'**Everything**: the important ones plus the social ones, such as kudos, comments, new followers, reactions and comment likes.',
						'**Off**: nothing on that channel. The app still shows everything.',
					],
				},
			],
		},
		{
			heading: 'Turn off a single kind',
			blocks: [
				{
					type: 'p',
					text: 'On the web, the same page lets you silence some kinds without changing a whole channel: **Data export ready**, **Mentions**, **Reactions to my runs**, **Likes on my comments** and **Follow requests**. Untick one and it stops being emailed and pushed, on your phone as well, but it still appears in the app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'These switches only ever turn things off. Reactions and comment likes are sent only when a channel is set to **Everything**, and a channel set to **Off** stays silent whatever they say.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'The single-kind switches are on the web only for now. The phone app shows the email and push settings.',
				},
			],
		},
	],
	related: ['private-profile-and-follow-requests', 'your-data-and-privacy', 'using-help'],
};
