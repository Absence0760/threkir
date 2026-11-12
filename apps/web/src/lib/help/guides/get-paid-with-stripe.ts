import type { Guide } from '../types';

export const guide: Guide = {
	id: 'get-paid-with-stripe',
	title: 'Get paid for the events you host',
	summary: 'Connect a Stripe payout account once so the classes and events you host can take payment, with the money going to you rather than the club.',
	kind: 'how-to',
	category: 'paid-classes',
	audience: ['organiser', 'instructor'],
	requires: ['stripe-connected', 'paid-rail-live'],
	platforms: ['web'],
	routes: ['/settings/payouts', '/clubs/[slug]'],
	sections: [
		{
			heading: 'Before you start',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Paid registration is not live yet. Charging for an event needs two things: your own Stripe account connected here, and the platform switching its paid rail on. Until both are true, nobody can be charged. If pressing **Set up payments** shows **Payments aren\'t configured on this build yet.**, the second one is still missing and there is nothing for you to do yet.'
				},
				{
					type: 'p',
					text: 'Payouts belong to *you*, not to a club. The money for an event goes to the person who hosts it, so a co-organiser who never hosts a class never sees money that isn\'t theirs, and you keep your earnings if you stop organising for a club. One payout account covers every club you host for and every kind of event, a [[guide:set-up-a-race|race]] included.'
				}
			]
		},
		{
			heading: 'Connect your payout account',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open [[route:/settings/payouts|Settings, Payouts]] on the web.',
						'Press **Set up payments**. You are taken to Stripe to enter your details and the bank account you want paid into.',
						'Finish Stripe\'s steps. When you come back, the page shows your status.',
						'If it says **Onboarding incomplete — finish to start charging** or **Your payout account needs attention before you can take payment**, press **Finish setting up payments** to go back to Stripe and pick up where you left off.'
					]
				}
			]
		},
		{
			heading: 'What the status means',
			blocks: [
				{
					type: 'list',
					items: [
						'**Ready to take payment**: Stripe has enabled charges on your account, and **Open Stripe dashboard** takes you to your Stripe account. This is what "charges enabled" means, and it is the only state in which the **Charge for this event** switch on a new event can be turned on.',
						'**Onboarding incomplete — finish to start charging**: Stripe still needs something from you before it will accept a charge.',
						'**Your payout account needs attention before you can take payment**: Stripe has restricted the account, usually because it wants more information. **Finish setting up payments** takes you to what it is asking for.'
					]
				},
				{
					type: 'p',
					text: 'Until you are ready to take payment, the event form shows **Set up payouts to charge for events.** with a **Set up payouts** link back to this page.'
				}
			]
		},
		{
			heading: 'Fees and who handles what',
			blocks: [
				{
					type: 'p',
					text: 'The platform takes a small fee from each registration, shown as **Platform fee** in your earnings. The platform is the merchant of record: the charge carries its name on your buyer\'s statement, refunds are issued by the platform under the refund policy you set on each event, and a disputed charge is taken from the platform\'s Stripe account, not yours. When an order is fully refunded, the platform fee on it is given back too.'
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Don\'t refund a buyer by hand in Stripe. Use the app\'s own paths ([[guide:refund-policies|a buyer\'s cancellation]] or [[guide:cancel-a-class|cancelling an occurrence]]), which reverse your payout and the platform fee together and keep your earnings figures right.'
				}
			]
		},
		{
			heading: 'See what you earned',
			blocks: [
				{
					type: 'p',
					text: 'The **Earnings** section on the same page shows what you were paid for your classes, one block per month and currency. A class is filed under the month it ran in its own timezone, not the month someone paid, so "my October classes" means the classes that happened in October.'
				},
				{
					type: 'list',
					items: [
						'**Registrations**, **Gross**, **Refunded** and **Platform fee** for the month, and **Net to you** at the end.',
						'A breakdown by class with **Class** and **When** columns.',
						'A refund the bank sent back is left out of the totals until it is resolved, and the section says how many there are.'
					]
				},
				{
					type: 'p',
					text: 'Before anyone has paid, it reads **No paid registrations yet. Once someone pays for one of your classes, it shows up here.** Earnings are on the web only for now.'
				}
			]
		}
	],
	related: ['host-a-paid-yoga-class', 'host-a-paid-gym-class', 'refund-policies', 'cancel-a-class', 'set-up-a-race']
};
