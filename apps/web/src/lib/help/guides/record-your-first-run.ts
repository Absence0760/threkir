import type { Guide } from '../types';

export const guide: Guide = {
	id: 'record-your-first-run',
	title: 'Record your first run',
	summary: 'Start a run on your phone, pause and stop it safely, get a good GPS signal, and see what gets saved afterwards.',
	kind: 'start',
	category: 'running',
	audience: ['runner'],
	platforms: ['android', 'ios'],
	sections: [
		{
			heading: 'Start recording',
			blocks: [
				{
					type: 'p',
					text: 'Runs are recorded in the phone app or on a watch. The web app shows your runs but cannot record one.',
				},
				{
					type: 'steps',
					items: [
						'Tap the big button in the middle of the bottom bar. It reads **Start run**, or **Log** if you have switched on gym or nutrition, in which case choose **Log run**.',
						'Tap **START**. The first time, your phone asks for location access: allow it, or the run records time only, with no distance or map.',
						'A three-second countdown runs while the GPS warms up, then the clock starts.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'On Android, choose **Allow all the time** for location. With access only while the app is open, distance you cover with the screen off is not counted, although the clock keeps running.',
				},
			],
		},
		{
			heading: 'Pausing and stopping',
			blocks: [
				{
					type: 'p',
					text: 'There is no auto-pause: the clock runs until you pause it. Use the pause button for a stop you want left out of your time, and the resume button to carry on.',
				},
				{
					type: 'p',
					text: 'Standing at a crossing without pausing does no harm. After the run, **Moving** time leaves out the stretches where you were standing still, and your pace is worked out from moving time.',
				},
				{
					type: 'steps',
					items: [
						'To finish, press and hold the stop button. The hint reads **Hold to stop**, so a stray tap in your pocket doesn\'t end the run.',
						'The **Run Complete** summary shows your distance, **Time**, **Moving** time, pace and any other stats your phone measured.',
						'Tap **Done** to go back to the start screen.',
					],
				},
			],
		},
		{
			heading: 'Getting a good GPS signal',
			blocks: [
				{
					type: 'list',
					items: [
						'Start outside, away from tall buildings and thick tree cover, so the countdown has a clear view of the sky.',
						'If you see **GPS signal lost — move to open sky**, keep going: the clock keeps running and distance picks up again when the signal returns.',
						'**Weak GPS — distance paused** means your position is too uncertain to count. Distance resumes as soon as the signal improves.',
						'Keep location services on and battery saving off for the app, so your phone doesn\'t stop the recording in the background.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'If the app closes mid-run, open it again: you are asked **Resume your run?** and can resume, finish now, or discard it.',
				},
			],
		},
		{
			heading: 'What gets saved',
			blocks: [
				{
					type: 'p',
					text: 'When you stop, the run is saved on your phone first, then uploaded to your account. The summary shows **Synced** once it is safely in the cloud, or **Saved offline.** if you are signed out. A run that couldn\'t upload stays on the phone and retries later.',
				},
				{
					type: 'list',
					items: [
						'Distance, elapsed time, moving time and pace.',
						'Your GPS track, which draws the map and splits.',
						'Elevation, steps, and heart rate if you paired a heart-rate strap.',
					],
				},
				{
					type: 'p',
					text: 'Who can see the run follows your **Default run privacy** setting, which you can change for any single run afterwards. To hide where you live, set up [[guide:privacy-zones|privacy zones]] before you share anything.',
				},
			],
		},
	],
	related: ['privacy-zones', 'live-tracking-and-safety', 'import-your-history'],
};
