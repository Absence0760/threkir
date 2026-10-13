import type { Guide } from '../types';

export const guide: Guide = {
	id: 'invite-members-and-roles',
	title: 'Invite members and give them roles',
	summary: 'Share an invite link, approve join requests, and give trusted members the admin, event organiser or race director role.',
	kind: 'how-to',
	category: 'clubs',
	audience: ['club-admin', 'organiser'],
	requires: ['club-admin'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/clubs/[slug]', '/clubs/join/[token]'],
	sections: [
		{
			heading: 'How people join',
			blocks: [
				{
					type: 'p',
					text: 'How someone joins depends on the club\'s join policy, which you chose when you created it and can change with **Edit club** on the web.',
				},
				{
					type: 'list',
					items: [
						'**Anyone can join**: people select **Join club** on the club page and are in straight away.',
						'**Approval required**: people select **Request to join** and wait in a queue until an admin approves them.',
						'**Invite only**: people need an invite link from an admin.',
					],
				},
			],
		},
		{
			heading: 'Share an invite link',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open your club on the web. When the club is **Invite only**, admins see an **Invite link** panel on the club page.',
						'Select **Generate invite link** the first time, then **Copy** to put the link on your clipboard.',
						'Send the link however you like. Anyone who opens it and signs in joins the club as a member.',
					],
				},
				{
					type: 'p',
					text: 'If a link has spread further than you wanted, select **Rotate**. A new link is made and the old one stops working immediately.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'An invite link lets people straight in: it skips the approval queue, so only share it with people you are happy to admit.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'In the phone app, a member can also tap **Join with invite code** on the **Clubs** tab of **Social** and enter the code from the link: only the part after /clubs/join/, not the whole link. Opening the link in a phone browser works too.',
				},
			],
		},
		{
			heading: 'Approve or reject join requests',
			blocks: [
				{
					type: 'p',
					text: 'When the club needs approval, admins see **Pending requests** with a count beside it.',
				},
				{
					type: 'list',
					items: [
						'On the web, select **Approve** or **Reject** on each request, or **Approve all** when several are waiting. Rejecting asks you to confirm first.',
						'In the phone app, open the club\'s **Members** tab and tap **Approve** or **Deny** on each request.',
					],
				},
			],
		},
		{
			heading: 'Give members a role',
			blocks: [
				{
					type: 'p',
					text: 'Every club has one **Owner**, the person who created it. Other people can hold one of these roles:',
				},
				{
					type: 'list',
					items: [
						'**Admin**: changes the club\'s settings, manages members and their roles, runs events and races, and approves results.',
						'**Event organiser**: creates, edits and deletes events and adds attendees, without access to club settings or members.',
						'**Race director**: arms, starts and ends races and approves or rejects results.',
						'**Member**: posts replies, RSVPs to events and submits their own race results.',
					],
				},
				{
					type: 'steps',
					items: [
						'Open your club on the web and choose the **Members** tab.',
						'Use the role menu beside a member to pick their new role. The change saves straight away.',
						'To take someone out of the club, use the remove button beside them and confirm.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Changing roles and removing members is web-only for now. The phone app\'s **Members** tab shows the member count and the pending requests, not the full list.',
				},
			],
		},
	],
	related: ['create-a-club', 'recurring-events', 'set-up-a-race'],
};
