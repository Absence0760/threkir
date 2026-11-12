import type { Guide } from '../types';

export const guide: Guide = {
	id: 'cancel-a-class',
	title: 'Cancel a class and refund everyone who paid',
	summary: 'Call off one occurrence of a repeating class; everyone who paid for it is refunded in full automatically, with an hourly retry and a Refund now fallback.',
	kind: 'how-to',
	category: 'paid-classes',
	audience: ['organiser', 'instructor'],
	requires: ['stripe-connected', 'paid-rail-live'],
	platforms: ['web'],
	routes: ['/clubs/[slug]/events/[id]'],
	sections: [
		{
			heading: 'Before you start',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Paid classes are not live yet: they need the host\'s Stripe account connected and the platform\'s paid rail switched on. If payments aren\'t available when you try to cancel an occurrence that has paid registrations, you\'ll see **This occurrence has paid registrations and payments aren\'t available right now, so it can\'t be cancelled yet. Nothing has changed.** The class is left on, so nobody is left holding a payment for a class that isn\'t happening.'
				},
				{
					type: 'p',
					text: 'Cancelling is for admins and event organisers of the club, and it is done on the web. Free classes cancel the same way, just without the refunds.'
				}
			]
		},
		{
			heading: 'Cancel one occurrence',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the class on the web. If it repeats, use **Pick an occurrence** to choose the date you are calling off.',
						'Press **Cancel this occurrence**.',
						'The dialog explains that only this occurrence is called off and the rest of the series is unaffected. On a paid class it adds: **Everyone registered for this occurrence is refunded in full, whatever the refund policy says.**',
						'Optionally add a **Reason (optional)**, then press **Cancel this occurrence** again to confirm, or **Keep it** to back out.'
					]
				},
				{
					type: 'p',
					text: 'When it finishes you see how many people are being refunded, for example *Occurrence cancelled. 8 registrants are being refunded in full.* Anyone who was part-way through checkout has their held spot released and is not charged. Nobody on the waitlist is moved into a cancelled class.'
				}
			]
		},
		{
			heading: 'What your attendees are told',
			blocks: [
				{
					type: 'p',
					text: 'Everyone who RSVP\'d to that occurrence (going, maybe, or waitlisted) is notified. People who paid get a notification that reads like *An occurrence of "Tuesday Reformer" was cancelled — your payment is being refunded*, and the same wording goes out by email or push to anyone who gets those. It says *being* refunded because the refund is started at that moment and can take a few days to reach their bank.'
				}
			]
		},
		{
			heading: 'If a refund fails',
			blocks: [
				{
					type: 'p',
					text: 'The occurrence is still cancelled even if Stripe refuses a refund. You\'ll see a message saying how many refunds couldn\'t be started, and the class page gains a **Refunds on cancelled occurrences** card listing, per cancelled date, who hasn\'t been refunded yet, which refunds are in progress, and any the bank sent back.'
				},
				{
					type: 'list',
					items: [
						'The app retries every refund still owed on a cancelled class automatically, once an hour.',
						'You don\'t have to wait: press **Refund now** next to the occurrence to try again straight away. It never refunds anyone twice.',
						'A refund the bank sends back can\'t be retried this way; it is returned to the person another way.'
					]
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Don\'t refund people by hand from a Stripe dashboard. A refund made there can skip reversing your payout and the platform fee, and the app may then refund the rest on top. Use **Refund now** instead.'
				}
			]
		},
		{
			heading: 'One-off classes and whole series',
			blocks: [
				{
					type: 'p',
					text: '**Cancel this occurrence** is only offered on a repeating class. There is no single button to call off a whole series: cancel each upcoming occurrence that has registrations.'
				},
				{
					type: 'note',
					tone: 'caution',
					text: '**Delete event** is not a cancellation. It removes the event and all its occurrences and does not refund anyone who paid. Don\'t delete a paid class that still has registrations.'
				},
				{
					type: 'p',
					text: 'Changed your mind? **Reinstate this occurrence** puts a cancelled date back on the calendar, but refunds already made are not undone, so people will need to register again.'
				}
			]
		}
	],
	related: ['refund-policies', 'waitlist-and-claim-window', 'get-paid-with-stripe', 'host-a-paid-yoga-class', 'host-a-paid-gym-class']
};
