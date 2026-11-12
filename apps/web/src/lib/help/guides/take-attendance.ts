import type { Guide } from '../types';

export const guide: Guide = {
	id: 'take-attendance',
	title: 'Take attendance at a class',
	summary: 'Mark who actually came to each occurrence of a class, separately from who said they would, on the web or the phone app.',
	kind: 'how-to',
	category: 'instructors',
	audience: ['instructor', 'organiser'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/clubs/[slug]/events/[id]'],
	sections: [
		{
			heading: 'Who can take it, and where',
			blocks: [
				{
					type: 'p',
					text: 'Attendance is for events with the **Class** type, and only the club\'s admins and event organisers can mark it. It works the same on the web and in the phone app, so you can do it from your phone at the front of the room.'
				},
				{
					type: 'p',
					text: 'It is separate from the RSVP. Someone can be **Going**, or registered and paid, and still be marked as a no-show; marking attendance never changes their registration or refunds anyone.'
				}
			]
		},
		{
			heading: 'Mark who came',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the class. If it repeats, use **Pick an occurrence** to choose today\'s date, because attendance is recorded per occurrence.',
						'Scroll to the attendee list.',
						'Next to each person, press **Mark attended** or **Mark no-show**.',
						'Pressed the wrong one? Press the same button again to clear it.'
					]
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'You don\'t have to mark everyone. Anyone left unmarked simply has no attendance recorded.'
				}
			]
		},
		{
			heading: 'What others see',
			blocks: [
				{
					type: 'p',
					text: 'Other people looking at the class see an **Attended** or **No-show** label next to each name you marked, but can\'t change it.'
				},
				{
					type: 'p',
					text: 'Attendance doesn\'t add the class to anyone\'s training history. Attendees do that themselves with **Log this as a workout** on the class page, or by following the class\'s session plan: see [[guide:build-a-session-plan|Build a session plan]].'
				}
			]
		}
	],
	related: ['host-a-paid-yoga-class', 'host-a-paid-gym-class', 'build-a-session-plan', 'build-a-gym-routine']
};
