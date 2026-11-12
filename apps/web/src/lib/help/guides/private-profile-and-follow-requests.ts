import type { Guide } from '../types';

export const guide: Guide = {
	id: 'private-profile-and-follow-requests',
	title: 'Make your profile private and approve followers',
	summary: 'Turn on a private profile so only followers you approve see your runs, then approve or decline follow requests as they arrive.',
	kind: 'how-to',
	category: 'account',
	audience: ['everyone'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/settings/privacy', '/follow-requests', '/u/[id]'],
	sections: [
		{
			heading: 'What a private profile hides',
			blocks: [
				{
					type: 'p',
					text: 'With a private profile, only followers you have approved see your runs and other activities, and the lists of who follows you and who you follow. Everyone else sees your name, picture and follower counts, with **This profile is private** where your runs would be.',
				},
				{
					type: 'list',
					items: [
						'People can still find you by name and ask to follow you. To stay out of name search too, turn off **Show me in name search** on the same page.',
						'Anyone who already follows you when you switch it on keeps following you.',
						'Routes, event results and badges keep their own visibility, because each one is shared on its own.',
						'A live link you send during a run, including the link in a safety alert, still works for the people you sent it to.',
					],
				},
			],
		},
		{
			heading: 'Turn it on',
			blocks: [
				{
					type: 'steps',
					items: [
						'On the web, open [[route:/settings/privacy|Privacy & sharing]] in Settings and tick **Private profile** under **Being found**.',
						'In the phone app, open **Preferences** in the **You** tab and turn on **Private profile** under **Privacy & sharing**.',
					],
				},
				{
					type: 'p',
					text: 'The change saves straight away.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Turning it off again approves every request that is still waiting, so those people start following you at once.',
				},
			],
		},
		{
			heading: 'Approve or decline requests',
			blocks: [
				{
					type: 'p',
					text: 'When someone asks to follow you, you get a notification. Follow requests count as important, so by default they are emailed and pushed to you as well.',
				},
				{
					type: 'steps',
					items: [
						'Open the notification. You can also select **Review follow requests** under **Private profile** on the web, or tap **Follow requests** under **Private profile** in the phone app.',
						'Choose **Approve** to let that person see your profile, or **Decline** to turn the request down. They aren\'t notified when you decline.',
					],
				},
			],
		},
		{
			heading: 'Follow someone with a private profile',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open their profile and choose **Request to follow**.',
						'The button shows **Requested** while you wait. Choose it again to withdraw the request.',
						'Once they approve, the button shows **Following** and their runs appear.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'If you unfollow someone with a private profile, you have to ask again to see their runs.',
				},
			],
		},
	],
	related: ['your-data-and-privacy', 'notifications-reactions-and-mentions', 'privacy-zones'],
};
