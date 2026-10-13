import type { Guide } from '../types';

export const guide: Guide = {
	id: 'racing-in-a-race',
	title: 'Racing in a live race',
	summary: 'Sign up, pick your course, start recording after GO and let your phone or watch time you over the finish line.',
	kind: 'how-to',
	category: 'races',
	audience: ['participant', 'runner'],
	platforms: ['web', 'android', 'ios', 'wear', 'apple-watch'],
	routes: ['/clubs/[slug]/events/[id]'],
	sections: [
		{
			heading: 'Which devices can race',
			blocks: [
				{
					type: 'list',
					items: [
						'Android phone app: full support. It shows the race banner, sends your live position and finishes you automatically.',
						'iPhone app: runs the same code as Android, but it has not been tested on an iPhone in a real race yet.',
						'Wear OS watch: full support on the wrist, including the automatic finish. You still sign up and choose your course on the web or the phone.',
						'Apple Watch: early support only. It shows the race banner, sends your position and reports your time through your iPhone, but it has no automatic finish and has not been proven in a real race. Carry your phone as a backup.',
						'Web: use it to sign up, pick a course and see results. A browser cannot record a run.'
					]
				}
			]
		},
		{
			heading: 'Sign up and pick a course',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the race event.',
						"If there is more than one course, choose yours from **Your course** on the web. In the phone app you are asked to **Pick your course** when you tap **I'm in**.",
						"Tap **I'm in**. Only an **I'm in** sign-up gets race alerts on your device; **Maybe** does not."
					]
				},
				{
					type: 'p',
					text: 'Changed your mind? On the web, choose a different course from **Your course** (you will see "Course updated."). In the phone app, tap **Change course**. Settle on your course before you start recording: your phone or watch reads it when your race recording begins, and your result goes on that course\'s board.'
				}
			]
		},
		{
			heading: 'Race armed and Race LIVE',
			blocks: [
				{
					type: 'p',
					text: 'When the host arms the race, the Run tab of the phone app shows **Race armed** with "waiting for GO". The Wear OS watch shows "RACE ARMED" above its Start button. When the host fires GO it changes to **Race LIVE** ("RACE LIVE" on the watch) with the elapsed time and "tap Start".'
				},
				{
					type: 'note',
					tone: 'caution',
					text: "Your phone does not start recording by itself. Press Start yourself once you see **Race LIVE**. If you start your phone's recording before GO, that run is not linked to the race: it sends no live position and no result. On a Wear OS watch, a run started early is picked up once the watch sees the race go live."
				},
				{
					type: 'p',
					text: "The phone app checks for races you said **I'm in** to that start within the next day. If the banner is slow to appear, keep the app open on the Run tab for a minute."
				}
			]
		},
		{
			heading: 'Finishing automatically',
			blocks: [
				{
					type: 'p',
					text: 'You do not need to press anything at the finish. Your phone or Wear OS watch finishes you when both of these are true:'
				},
				{
					type: 'list',
					items: [
						'you are within 30 m of the finish line, and',
						'you have covered at least 90% of your course distance.'
					]
				},
				{
					type: 'p',
					text: "Your time is taken at the moment you were closest to the finish, not the first moment you came within 30 m. The 90% rule stops a loop course, which starts where it finishes, from finishing you in the first second. The phone shows \"Finished!\" with your gun time, and your recording stops."
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'If your course has no route or no distance, there is no automatic finish. Use Stop and then **Finish race** when you cross the line.'
				}
			]
		},
		{
			heading: 'Stopping during the race',
			blocks: [
				{
					type: 'p',
					text: 'During a live race, Stop does not end your race. It pauses your recording and shows **Race paused**. The race clock keeps running.'
				},
				{
					type: 'list',
					items: [
						'**Resume race** carries on recording.',
						'**Finish race** ends your race now. If you have covered at least 90% of the course this is a manual finish at that moment.',
						'Below 90% the button reads **Finish as DNF**, and finishing records a DNF.'
					]
				},
				{
					type: 'p',
					text: 'On a Wear OS watch the paused screen offers "Go" to resume, and you hold **Finish** to finish.'
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Finishing before 90% of the course records a DNF. If you only stopped to tie a lace, choose **Resume race**.'
				}
			]
		},
		{
			heading: 'No signal at the finish',
			blocks: [
				{
					type: 'p',
					text: "Finish lines often have poor signal. Your phone and Wear OS watch save your result first and send it as soon as they reconnect, so it is not lost. It must reach us within 24 hours of the host ending the race. Don't sign out of the app before it has been sent."
				}
			]
		},
		{
			heading: 'Gun time, chip time and late starts',
			blocks: [
				{
					type: 'list',
					items: [
						'**Gun time** runs from the moment the host fired GO to your finish. It is the time you are ranked on.',
						'**Chip time** runs from when you pressed Start to your finish, including any pauses.',
						'If you start more than 5 minutes after GO, the phone app shows a late-start notice. Your gun time still counts from GO, so a late start makes it longer than your chip time.'
					]
				},
				{
					type: 'p',
					text: 'More on reading the board in [[guide:race-results-explained|Race results explained]].'
				}
			]
		},
		{
			heading: 'If the host ends the race first',
			blocks: [
				{
					type: 'p',
					text: 'If the host ends the race before you finish, your phone tells you so and your watch shows "Race ended". Your run keeps recording as a normal run, but your device sends no race result. If you had already sent a live position, the race marks you DNF.'
				}
			]
		}
	],
	related: ['set-up-a-race', 'race-results-explained', 'follow-a-race-live', 'using-help']
};
