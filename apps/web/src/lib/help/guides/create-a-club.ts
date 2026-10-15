import type { Guide } from '../types';

export const guide: Guide = {
	id: 'create-a-club',
	title: 'Create a club',
	summary: 'Start a club for your running group, choose who can find it and how people join, then post your first event.',
	kind: 'how-to',
	category: 'clubs',
	audience: ['organiser', 'club-admin'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/social', '/clubs/new', '/clubs/[slug]'],
	sections: [
		{
			heading: 'On the web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open [[route:/social|Social]] and choose the **Clubs** tab.',
						'Select **Create club**.',
						'Fill in **Name**. Members search for the club by this name, and the club\'s web address is built from it when you create the club. Renaming the club later does not change that address.',
						'Add a **Description** and a **Location** if you like. Both are optional, but a town and country in **Location** helps runners nearby find you when they search their own region.',
						'Pick a **Visibility**: **Public** clubs appear in **Browse**, while **Private** clubs are hidden and people can only join through an invite link.',
						'Under **Who can join?** choose **Anyone can join**, **Approval required** or **Invite only**.',
						'Tick **Require an activity-risk acknowledgement to join** if you want every new member to confirm they understand the risks of group runs. This can only be set now, while the club is being created.',
						'Select **Create club**. You are taken to the new club\'s page, and you are its owner.',
					],
				},
			],
		},
		{
			heading: 'On the phone app',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the **Social** tab and choose **Clubs**.',
						'Tap **New club**.',
						'Enter a **Name**, and optionally a **Description (optional)** and **Location (optional)**.',
						'Choose **Public** or **Private**, then pick a **Join policy**: **Open — anyone joins**, **Request — admins approve** or **Invite only**.',
						'Tap **Create**.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'The activity-risk acknowledgement and the club\'s website and social links can only be set on the web.',
				},
			],
		},
		{
			heading: 'After you create it',
			blocks: [
				{
					type: 'p',
					text: 'Your club page has tabs for **Feed**, **Events**, **Routes**, **Templates**, **Photos** and **Members**. As the owner you can post updates to the feed, add events and manage members.',
				},
				{
					type: 'list',
					items: [
						'To change the name, description, visibility, join policy or links later, open the club on the web and select **Edit club**.',
						'To add your first group run, select **New event** on the web, or tap **Create event** on the **Events** tab in the phone app.',
						'To bring people in, see [[guide:invite-members-and-roles|Invite members and give them roles]].',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Deleting a club removes all of its events, posts and members for everyone, and it cannot be undone.',
				},
			],
		},
		{
			heading: 'Bring a club across from Strava',
			blocks: [
				{
					type: 'p',
					text: 'If your Strava account is connected, open [[route:/social|Social]] on the web, choose **Clubs** and then **My clubs**. Under **Your Strava clubs** you see the Strava clubs you belong to. Only you can see this list.',
				},
				{
					type: 'list',
					items: [
						'**Set up on Threkir** opens a new club form with its name and location filled in, and links the two once you create the club.',
						'**Link to my club** connects it to a club you already run here: pick it under **Which of your clubs is this?** and select **Link**.',
						'**Unlink** removes the connection. Neither club is changed.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Only an admin of the club on Strava can link it, and only to a club they own or help run here. If the section is missing, connect Strava under [[route:/settings/integrations|Integrations]] in Settings first.',
				},
			],
		},
	],
	related: ['invite-members-and-roles', 'recurring-events', 'set-up-a-race', 'import-your-history'],
};
