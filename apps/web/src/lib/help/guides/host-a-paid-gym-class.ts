import type { Guide } from '../types';

export const guide: Guide = {
	id: 'host-a-paid-gym-class',
	title: 'Host a paid HIIT, strength or bootcamp class',
	summary: 'Schedule a recurring gym class with a spot limit and drop-in price, share the workout as a club routine, and let attendees log it to their own history.',
	kind: 'how-to',
	category: 'paid-classes',
	audience: ['instructor', 'organiser'],
	requires: ['stripe-connected', 'paid-rail-live'],
	platforms: ['web'],
	routes: ['/clubs/[slug]', '/clubs/[slug]/events/new', '/clubs/[slug]/events/[id]', '/gym/routines/[id]', '/plans/new'],
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
					type: 'p',
					text: 'You need to be an admin or event organiser of the club. Price, capacity and the repeat schedule are set on the web; the phone app can create a class but has no fields for them.'
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
						'Under **Event type**, pick **Class**. Route, distance, pace and race results are hidden for a class.',
						'Fill in **Discipline**, for example "HIIT" or "Bootcamp", and a **Title** people will recognise on the calendar.',
						'Set **Default workout length** to the class length in minutes. This is what lets attendees log the class in one tap afterwards.',
						'Set the **Date**, **Start time**, **Duration** and **Meeting point**.',
						'Under **Repeats**, pick **Weekly**, **Every 2 weeks** or **Monthly** and the days. You can only choose this while creating the event.',
						'Set **Capacity** to your racks, bikes or spots.',
						'Turn on **Charge for this event**, then set **Price**, **Currency**, **Stop sales (minutes before start)** and a **Refund policy**. Price and currency can\'t be changed after the event is created.',
						'Press **Create event**.'
					]
				}
			]
		},
		{
			heading: 'Share the workout with your class',
			blocks: [
				{
					type: 'p',
					text: 'A class can\'t carry a gym routine directly yet. Instead, publish your routine to the club, where members can copy it into their own routines and run it.'
				},
				{
					type: 'steps',
					items: [
						'Build the routine: see [[guide:build-a-gym-routine|Build a gym routine]].',
						'Open the routine, and under **Publish to a club** choose your club from **Pick a club…** and press **Publish**.',
						'It appears on the club\'s **Templates** tab under **Gym routine templates**, marked **Club template**. Members press **Adopt** to get their own copy.'
					]
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Club admins can also go straight to the **Templates** tab, press **Add template** and choose **Gym routine**. It is saved as a club template in one step.'
				}
			]
		},
		{
			heading: 'Attendees log the class to their own history',
			blocks: [
				{
					type: 'p',
					text: 'On the class page, any signed-in attendee sees **Log this as a workout**. It opens a gym log already named after the class, which they can adjust with their own sets and weights before saving. They then see **Added to your gym log**, and the class counts in their training history like any other workout. This works on the web and in the phone app.'
				},
				{
					type: 'p',
					text: 'Someone who adopted your routine can instead open it and press **Start routine** to be guided set by set; that session is saved to their gym log as well.'
				}
			]
		},
		{
			heading: 'Registration, the day itself and changes',
			blocks: [
				{
					type: 'list',
					items: [
						'Attendees register and pay on the web, see **You\'re registered**, and can cancel under your [[guide:refund-policies|refund policy]].',
						'When the spots are taken it shows **Sold out** and offers **Join the waitlist**: see [[guide:waitlist-and-claim-window|Waitlists and the 12-hour claim window]].',
						'Mark who turned up: [[guide:take-attendance|Take attendance]].',
						'Calling a session off refunds everyone who paid: [[guide:cancel-a-class|Cancel a class]].'
					]
				}
			]
		}
	],
	related: ['get-paid-with-stripe', 'build-a-gym-routine', 'refund-policies', 'waitlist-and-claim-window', 'cancel-a-class', 'take-attendance']
};
