import type { Guide } from '../types';

export const guide: Guide = {
	id: 'recurring-events',
	title: 'Set up a recurring club event',
	summary: 'Turn a club event into a weekly, fortnightly or monthly series, RSVP to a single date, and call off one occurrence without touching the rest.',
	kind: 'how-to',
	category: 'clubs',
	audience: ['organiser', 'club-admin', 'participant'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/clubs/[slug]', '/clubs/[slug]/events/new', '/clubs/[slug]/events/[id]'],
	sections: [
		{
			heading: 'Create the series',
			blocks: [
				{
					type: 'p',
					text: 'Club owners, admins and event organisers can create events. A recurring event is one event that repeats, so everything you fill in applies to every date.',
				},
				{
					type: 'steps',
					items: [
						'Open your club on the web and select **New event**.',
						'Fill in the **Title**, **Start time** and the other details as for a one-off event. The start time you pick is the first date of the series.',
						'Under **Repeats**, choose **Weekly**, **Every 2 weeks** or **Monthly** instead of **One-off**.',
						'For a weekly or fortnightly series, pick the weekdays under **On these days:**. A monthly series repeats on the same day of the month as the start date.',
						'Decide where the series stops: set **Ends on** to a date, **End after** to a number of occurrences, or both, and whichever comes first wins. Leave both empty and it keeps repeating.',
						'Select **Create event**.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'The repeat pattern can only be chosen while the event is being created. **Edit event** changes the title, time, meeting point and other details for the whole series, but not how often it repeats.',
				},
				{
					type: 'p',
					text: 'In the phone app, tap **Create event** on the club\'s **Events** tab and choose **Weekly**, **Bi-weekly** or **Monthly** under **Recurrence**. The phone repeats the event on the weekday of its start date and has no end date or occurrence count, so use the web if the series needs to stop.',
				},
			],
		},
		{
			heading: 'RSVP to one date',
			blocks: [
				{
					type: 'p',
					text: 'Each date in a series has its own RSVPs, attendee list, capacity and results.',
				},
				{
					type: 'steps',
					items: [
						'Open the event and use **Pick an occurrence** to choose the date. The next few dates are shown, and **Show all** expands to every upcoming date in the next year.',
						'Choose **I\'m in**, **Maybe** or **Can\'t make it** for that date.',
					],
				},
				{
					type: 'p',
					text: 'To put the dates in your own calendar, select **Add to calendar**. On a series you can choose **Add this occurrence** for one date or **Add whole series** for every date.',
				},
			],
		},
		{
			heading: 'Cancel one occurrence',
			blocks: [
				{
					type: 'p',
					text: 'If one date can\'t go ahead, call off just that date and leave the rest of the series alone.',
				},
				{
					type: 'steps',
					items: [
						'Open the event on the web and pick the date you need to cancel.',
						'Select **Cancel this occurrence**.',
						'Add a **Reason (optional)**, such as a flooded course or a public holiday, and confirm. Select **Keep it** if you change your mind.',
					],
				},
				{
					type: 'p',
					text: 'Everyone who RSVP\'d to that date, whether going, maybe or waitlisted, gets a notification. The date shows **This occurrence was cancelled.** and nobody can RSVP to it. To bring it back, open the date and select **Reinstate this occurrence**.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Cancelling and reinstating a date is web-only. **Delete event** removes every occurrence of the series, not just one.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'If the event is a paid class, cancelling an occurrence refunds everyone registered for it in full. See [[guide:host-a-paid-yoga-class|Host a paid yoga class]].',
				},
			],
		},
	],
	related: ['create-a-club', 'invite-members-and-roles', 'host-a-paid-yoga-class'],
};
