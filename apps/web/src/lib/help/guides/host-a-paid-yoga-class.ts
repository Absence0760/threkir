import type { Guide } from '../types';

export const guide: Guide = {
	id: 'host-a-paid-yoga-class',
	title: 'Host a paid yoga or pilates class',
	summary: 'Schedule a recurring class for your club, cap the mats, set a drop-in price and refund policy, and attach a timed sequence people can follow.',
	kind: 'how-to',
	category: 'paid-classes',
	audience: ['instructor', 'organiser'],
	requires: ['stripe-connected', 'paid-rail-live'],
	platforms: ['web'],
	routes: ['/clubs/[slug]', '/clubs/[slug]/events/new', '/clubs/[slug]/events/[id]', '/settings/payouts', '/sessions/[id]'],
	sections: [
		{
			heading: 'Before you start',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'Paid classes are not live yet. Taking money needs your own Stripe account connected ([[guide:get-paid-with-stripe|Get paid for the events you host]]) and the platform\'s paid rail switched on. Until then the **Charge for this event** switch stays off and you can still run the class for free.'
				},
				{
					type: 'list',
					items: [
						'You need to be an admin or event organiser of the club. The club page tells you which with **You\'re an admin** or **You\'re an event organiser**.',
						'Price, capacity, the repeat schedule and the session plan are all set on the web. The phone app can create a class and shows it to members, but it has no price, capacity or session plan fields.',
						'Build your sequence first if you want to attach one: see [[guide:build-a-session-plan|Build a session plan]].'
					]
				}
			]
		},
		{
			heading: 'Create the class',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open your club, go to the **Events** tab and press **New event**.',
						'Under **Event type**, pick **Class**. Route, distance, pace and race results disappear, because a class doesn\'t need them.',
						'Fill in **Discipline**, for example "Reformer pilates". It names the style on the listing.',
						'Optionally set **Default workout length** in minutes. With a discipline or a length set, attendees get a **Log this as a workout** button on the class page.',
						'Optionally pick a **Session plan** to attach your timed sequence. Left on **None**, the class runs without one.',
						'Give it a **Title**, then the **Date**, **Start time**, **Duration** and a **Meeting point** a stranger could find, such as the studio address.'
					]
				}
			]
		},
		{
			heading: 'Schedule, capacity and price',
			blocks: [
				{
					type: 'steps',
					items: [
						'Under **Repeats**, choose **Weekly**, **Every 2 weeks** or **Monthly**, then the days and when the series ends with **Ends on** or **End after**. The schedule can only be chosen while you are creating the event.',
						'Set **Capacity** to the number of mats. Once that many people are registered, the next person joins a waitlist instead.',
						'Turn on **Charge for this event** and enter the **Price** and **Currency**. Both are fixed once the event is created, so check them now.',
						'Set **Stop sales (minutes before start)**. Zero keeps registration open right up to the start.',
						'Choose a **Refund policy**: **Full refund until start time**, **Full refund until 24h before** or **No refunds**. See [[guide:refund-policies|Refund policies]].',
						'Press **Create event**.'
					]
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Paid registration is for in-person classes only. Each occurrence of a repeating class is paid for separately, like a drop-in.'
				}
			]
		},
		{
			heading: 'What your attendees see',
			blocks: [
				{
					type: 'list',
					items: [
						'The discipline, time, place, the **Price** and a line about cancellation, such as **Free cancellation until 24 hours before the start**.',
						'A button reading *Register · $22* (with your price) that takes them to checkout. When they come back it says **Payment confirmed — you\'re registered.**',
						'**Sold out** when the mats are taken, with **Join the waitlist** while sales are open ([[guide:waitlist-and-claim-window|how the waitlist works]]), and **Registration closed** once sales stop.',
						'Your sequence under **Session sequence**. They can open it and press **Start session** to follow along at home.'
					]
				},
				{
					type: 'p',
					text: 'Registering and paying happen on the web. The phone app shows the class but has no register button yet.'
				}
			]
		},
		{
			heading: 'On the day and after',
			blocks: [
				{
					type: 'list',
					items: [
						'Mark who came: [[guide:take-attendance|Take attendance]].',
						'Need to call one off? [[guide:cancel-a-class|Cancel a class]] refunds everyone who paid.',
						'The money goes to your own payout account, minus the platform fee, and shows under **Earnings** in [[route:/settings/payouts|Payouts]].'
					]
				},
				{
					type: 'p',
					text: 'Forgot the plan at creation? On the class page, organisers can use **Attach to a class event** in the **Session sequence** card to pick one later.'
				}
			]
		}
	],
	related: ['get-paid-with-stripe', 'build-a-session-plan', 'refund-policies', 'waitlist-and-claim-window', 'cancel-a-class', 'take-attendance']
};
