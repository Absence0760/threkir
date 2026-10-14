import type { Guide } from '../types';

export const guide: Guide = {
	id: 'waitlist-and-claim-window',
	title: 'Waitlists and the 12-hour claim window',
	summary: 'How joining a full class works, how a freed place is held for you for 12 hours on a paid class, and what happens if you don\'t claim it.',
	kind: 'explainer',
	category: 'paid-classes',
	audience: ['participant', 'organiser', 'instructor'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/clubs/[slug]/events/[id]', '/notifications'],
	sections: [
		{
			heading: 'Free classes: you are moved in automatically',
			blocks: [
				{
					type: 'p',
					text: 'When a free class with a **Capacity** is full, pressing **I\'m in** puts you on the waitlist and your RSVP shows **Waitlisted**. When someone drops out, the earliest person on the waitlist is moved to **Going** automatically; there is nothing to claim. This works on the web and in the phone app.'
				}
			]
		},
		{
			heading: 'Paid classes: a place is held, then you pay',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Paid classes are not live yet: they need the host\'s Stripe account connected and the platform\'s paid rail switched on. Everything in this section applies once they are.'
				},
				{
					type: 'p',
					text: 'Nobody is charged just for being on a waitlist. Instead, when a place opens you are offered it and pay to take it.'
				},
				{
					type: 'steps',
					items: [
						'On a full paid class the page shows **Sold out**. While sales are still open, press **Join the waitlist**. You\'ll see **You\'re on the waitlist. If a place opens, we\'ll hold it for you and let you know.**',
						'When a place opens and you are first in line, you get a notification: *A place opened in "Tuesday Reformer" and is held for you — pay to claim it*.',
						'Open the class on the web. It says when your hold ends, for example *A place is held for you until Tue 6 May, 18:00. Pay to claim it, or it goes to the next person on the waitlist.*',
						'Press the claim button (it reads *Claim your place* with the price) and pay at checkout. Once paid you are registered like everyone else.'
					]
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Claiming happens on the web. The phone app shows the notification and opens the class, but it has no checkout yet, so open the class in a browser to pay.'
				},
				{
					type: 'illustration',
					id: 'waitlist-and-claim-window',
					alt: 'Three people wait in line. The first is offered the open place, which is held for them for a limited time.',
				},
			]
		},
		{
			heading: 'How long the hold lasts',
			blocks: [
				{
					type: 'list',
					items: [
						'You have 12 hours to claim, long enough that nobody loses a place by being asleep.',
						'The hold is cut short when sales close for that class (the host\'s stop-sales time before the start). No place is offered after sales close, because nobody could pay for it.',
						'While your place is held, nobody else can buy it, even though the class looks full to them.',
						'If you are part-way through checkout when the time runs out, the hold stays while that checkout is still open.'
					]
				}
			]
		},
		{
			heading: 'If you don\'t claim it',
			blocks: [
				{
					type: 'p',
					text: 'When the hold runs out, the place is offered to the next person on the waitlist and you leave the waitlist. If you still want in, press **Join the waitlist** again; you go to the back of the queue.'
				},
				{
					type: 'p',
					text: 'Changed your mind while you are still waiting? Press **Leave the waitlist**. It warns you that you\'ll lose your place in the queue; if you join again later, you go to the back. If a place is already being held for you and you don\'t want it, just let the hold run out.'
				}
			]
		},
		{
			heading: 'For hosts',
			blocks: [
				{
					type: 'list',
					items: [
						'The waitlist runs itself. Set a **Capacity** on the class and the rest happens automatically; the 12-hour window can\'t be changed per class.',
						'A held place counts against your capacity, so you never end up with more people than mats.',
						'If someone cancels with a refund, their place goes to the waitlist. If you cancel an occurrence, nobody from the waitlist is moved into it: see [[guide:cancel-a-class|Cancel a class]].'
					]
				}
			]
		}
	],
	related: ['refund-policies', 'cancel-a-class', 'host-a-paid-yoga-class', 'host-a-paid-gym-class']
};
