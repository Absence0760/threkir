import type { Guide } from '../types';

export const guide: Guide = {
	id: 'your-data-and-privacy',
	title: 'Your data and privacy',
	summary: 'See what other people can see, choose who sees new runs, download everything we hold about you, and delete your account.',
	kind: 'explainer',
	category: 'account',
	audience: ['everyone'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/settings/privacy', '/settings/account', '/delete-account', '/u/[id]'],
	sections: [
		{
			heading: 'What other people can see',
			blocks: [
				{
					type: 'list',
					items: [
						'Your profile page, with your display name, picture, follower counts and your public runs, can be opened by anyone with its link. With a private profile, only followers you approve see your runs and follower lists; see [[guide:private-profile-and-follow-requests|Make your profile private and approve followers]].',
						'Runs you make public appear on your profile and in the feed. Private runs are visible only to you.',
						'Membership of a public club, and anything you post there, can be seen by people who can see the club.',
						'While you share a live link, the run in progress can be seen by anyone with the link.',
						'A photo you mark **Show on race page**, on a public run linked to a race, appears on that race\'s public page with its caption and your name. Untick it, or make the run private, to take it down.',
					],
				},
				{
					type: 'p',
					text: 'Privacy zones trim the start and end of your tracks wherever someone else sees them. See [[guide:privacy-zones|Hide your home with privacy zones]].',
				},
			],
		},
		{
			heading: 'Choose who sees new runs',
			blocks: [
				{
					type: 'steps',
					items: [
						'On the web open [[route:/settings/privacy|Privacy & sharing]] in Settings and pick a **Default Visibility for New Runs**. In the phone app, it is **Default run privacy** under **Preferences** in the **You** tab.',
						'To change a single run later, open it and use **Make public** or **Make private**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Only **Public** makes new runs visible to others. Runs don\'t have a followers-only setting yet, so choosing followers as your default keeps new runs private, and your followers won\'t see them.',
				},
				{
					type: 'list',
					items: [
						'**Show me in name search**: turn off to keep your account out of name searches. Your profile and public runs can still be opened by anyone who has the link.',
						'**Show me in Runners nearby**, where it is offered: off by default. When on, runners near the area you set can find you. Only a rough area is stored, never your live location.',
					],
				},
			],
		},
		{
			heading: 'Download your data',
			blocks: [
				{
					type: 'p',
					text: 'On the web, open **Account** in Settings. The phone app has the same choices under **Account** in the **You** tab.',
				},
				{
					type: 'list',
					items: [
						'**Download full account archive** (on the phone, **Account export**): everything we hold about you, including coach chats, messages, integrations and safety contacts, as one zip. It is built on our server, so you can close the page and come back for it. A finished export is kept for 7 days.',
						'**Download full backup** (on the phone, **Full backup**): every run with its GPS trace, plus your routes, profile and preferences, in a file you can restore later with **Restore from backup**.',
						'**Cloud export (GPX zip)**: one GPX file per run, with heart rate, ready to import into other apps. Free accounts can export twice an hour, Pro accounts eight times.',
						'**Export All Runs (CSV)** (on the phone, **Export runs as CSV**): one row per run for a spreadsheet, without GPS traces.',
					],
				},
			],
		},
		{
			heading: 'Delete your account',
			blocks: [
				{
					type: 'steps',
					items: [
						'Download anything you want to keep first. Deletion cannot be undone.',
						'On the web, open **Account** in Settings and select **Delete Account** under **Danger Zone**. In the phone app, open **Account** in the **You** tab and tap **Delete account**.',
						'Type DELETE to confirm, then select **Delete my account** on the web or **Delete** in the app.',
					],
				},
				{
					type: 'p',
					text: 'This permanently removes your account, runs, routes, tracks, club memberships and preferences from our servers. On a phone, runs stored on the device itself stay there until you sign in as someone else or remove the app.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Can\'t get into the app? [[route:/delete-account|Delete your account]] explains how to ask for deletion without it.',
				},
			],
		},
	],
	related: ['privacy-zones', 'private-profile-and-follow-requests', 'live-tracking-and-safety', 'what-pro-includes'],
};
