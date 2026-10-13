import type { Guide } from '../types';

export const guide: Guide = {
	id: 'refund-policies',
	title: 'Refund policies and cancelling your registration',
	summary: 'How the three refund policies work, how a participant cancels a paid registration, and what they see when they do.',
	kind: 'explainer',
	category: 'paid-classes',
	audience: ['organiser', 'instructor', 'participant'],
	requires: ['stripe-connected', 'paid-rail-live'],
	platforms: ['web'],
	routes: ['/clubs/[slug]/events/[id]', '/clubs/[slug]/events/new'],
	sections: [
		{
			heading: 'Before you start',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Paid registration is not live yet. It needs the host\'s Stripe account connected and the platform\'s paid rail switched on. Until then no event can be charged for, so there is nothing to refund.'
				}
			]
		},
		{
			heading: 'The three policies',
			blocks: [
				{
					type: 'p',
					text: 'The host picks one **Refund policy** when creating a paid event. It decides what someone gets back if *they* cancel, and it is shown on the event page before anyone pays.'
				},
				{
					type: 'list',
					items: [
						'**Full refund until start time**: shown to participants as **Free cancellation until the event starts**.',
						'**Full refund until 24h before**: shown as **Free cancellation until 24 hours before the start**. This is the default.',
						'**No refunds**: shown as **No refund on cancellation**.'
					]
				},
				{
					type: 'p',
					text: 'A refund is all or nothing: inside the window you get the full price back, outside it you get nothing back. The window is measured against the start of the occurrence you registered for.'
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'The policy only covers a participant cancelling. If the host calls a class off, everyone who paid is refunded in full whatever the policy says: see [[guide:cancel-a-class|Cancel a class]].'
				}
			]
		},
		{
			heading: 'Cancel your own registration',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the event on the web. Where it says **You\'re registered**, press **Cancel registration**.',
						'Read the dialog. Inside the refund window it says you\'ll be refunded to your original payment method and that your spot opens up for someone on the waitlist.',
						'Press **Cancel registration** to go ahead, or **Keep my spot** to back out.'
					]
				},
				{
					type: 'p',
					text: 'Once it goes through you see **Refund started — it can take a few days to appear. Your spot has been released.** Until your bank confirms it, the page shows **Refund in progress**.'
				},
				{
					type: 'p',
					text: 'If you left checkout before paying, the same button cancels the pending registration instead: your held spot is released and no payment is taken.'
				}
			]
		},
		{
			heading: 'Outside the refund window',
			blocks: [
				{
					type: 'p',
					text: 'Past the window, or on a **No refunds** event, the app can\'t cancel your registration for you. The dialog warns you before you try, you keep your spot, and if you go ahead you\'ll see **This registration is past the refund window. Contact the host to cancel.**'
				}
			]
		},
		{
			heading: 'If a refund doesn\'t arrive',
			blocks: [
				{
					type: 'p',
					text: 'Occasionally a bank sends a refund back. The event page then shows **Your refund didn\'t reach you** and a notification says **A refund didn\'t go through — we\'ll be in touch**. You don\'t need to pay again; use **Contact billing** and it will be returned another way.'
				}
			]
		}
	],
	related: ['cancel-a-class', 'waitlist-and-claim-window', 'host-a-paid-yoga-class', 'host-a-paid-gym-class', 'get-paid-with-stripe']
};
