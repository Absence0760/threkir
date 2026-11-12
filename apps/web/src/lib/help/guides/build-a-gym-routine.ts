import type { Guide } from '../types';

export const guide: Guide = {
	id: 'build-a-gym-routine',
	title: 'Build a gym routine',
	summary: 'Turn a workout you teach or repeat into a reusable routine with sets, reps, load, rest and supersets, then run it guided or share it with your club.',
	kind: 'how-to',
	category: 'instructors',
	audience: ['instructor', 'runner'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/gym/routines', '/gym/routines/new', '/gym/routines/[id]', '/gym/session/[routineId]', '/plans/new', '/gym/[id]'],
	sections: [
		{
			heading: 'Two ways to start',
			blocks: [
				{
					type: 'list',
					items: [
						'From scratch: open [[route:/gym/routines|Routines]] and press **New routine**. On the web you can also go to [[route:/plans/new|New plan]] and pick **Gym routine**.',
						'From a workout you already logged: open it in your gym log and press **Save as routine**. Its exercises and sets become the routine\'s targets. **Repeat last** starts a new log from the same workout instead.'
					]
				},
				{
					type: 'p',
					text: 'On the phone app, open the gym screen and tap **Routines**, then **New routine**.'
				}
			]
		},
		{
			heading: 'Fill it in',
			blocks: [
				{
					type: 'steps',
					items: [
						'Give it a **Routine name**, named after the day rather than the first exercise, for example "Bootcamp A".',
						'Type the first exercise name. Reuse a name you already log, so your records for that lift stay in one place.',
						'Pick what it is **Measured by**: weight and reps, bodyweight, time, or distance. The set rows change to ask for the matching target.',
						'For each set, give a **Set type** and its targets, such as **Target reps** and weight, and a **Rest (s)**. Press **Add set** for more sets.',
						'To run two exercises back to back, turn on **Superset with the next exercise** on the first one.',
						'Press **Add exercise** for the next one, and repeat.',
						'Optionally open **Advanced** and choose a **Progression** rule, which suggests next session\'s numbers from this one\'s result. Left on None, your targets stay exactly as typed.',
						'Add any **Notes (optional)** and press **Save routine**.'
					]
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Each set row is a target, not a log. It is what a session started from the routine is filled in with, and you can still change the numbers as you go.'
				}
			]
		},
		{
			heading: 'Run it',
			blocks: [
				{
					type: 'p',
					text: 'Open the routine and press **Start routine** (on the phone app, **Start session**). You are guided one set at a time with your target shown: log what you did and press **Complete set**, or **Skip set**, with a rest timer between sets. Press **Finish** at the end and the session is saved to your gym log, with how it compared to the plan.'
				}
			]
		},
		{
			heading: 'Share it with a class',
			blocks: [
				{
					type: 'list',
					items: [
						'**Publish to a club**: choose the club from **Pick a club…** and press **Publish**. It shows on that club\'s **Templates** tab under **Gym routine templates**, where members press **Adopt** to get their own copy. Edits to a copy don\'t change your original.',
						'**Publish to public library**: anyone signed in can preview and adopt it. Your logged workouts stay private.'
					]
				},
				{
					type: 'p',
					text: 'Running a paid class around the routine? See [[guide:host-a-paid-gym-class|Host a paid HIIT, strength or bootcamp class]].'
				}
			]
		}
	],
	related: ['host-a-paid-gym-class', 'build-a-session-plan', 'take-attendance']
};
