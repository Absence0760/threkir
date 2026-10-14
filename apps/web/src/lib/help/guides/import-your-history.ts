import type { Guide } from '../types';

export const guide: Guide = {
	id: 'import-your-history',
	title: 'Import your running history',
	summary: 'Bring your past runs in from Strava, a Garmin export, or your phone\'s health app, and know what happens to GPX files.',
	kind: 'how-to',
	category: 'running',
	audience: ['runner'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/settings/integrations', '/routes'],
	sections: [
		{
			heading: 'Connect Strava for recent and new runs',
			blocks: [
				{
					type: 'steps',
					items: [
						'On the web open [[route:/settings/integrations|Integrations]] in Settings and select **Connect** on the Strava card, or in the phone app open **Integrations** in the **You** tab and tap Strava.',
						'Sign in to Strava and allow access.',
						'Your last 90 days of runs, walks and hikes are copied across, and new Strava activities follow automatically.',
					],
				},
				{
					type: 'p',
					text: 'Select **Sync now** to pull again. On the web, **How far back to sync** reaches up to a year back.',
				},
				{
					type: 'illustration',
					id: 'import-your-history',
					alt: 'Runs from a watch, a connected account and a file all flow into one list of runs.',
				},
			],
		},
		{
			heading: 'Bring in your whole Strava archive',
			blocks: [
				{
					type: 'p',
					text: 'Connecting Strava only reaches recent activity. For years of history, use a Strava data export.',
				},
				{
					type: 'steps',
					items: [
						'In Strava, go to Settings, My Account, and request your archive. Strava emails you a link to a zip file.',
						'On the web, open [[route:/settings/integrations|Integrations]], find **Bulk import from a Strava export** and select **Choose Strava export zip**. In the phone app, open **Account** in the **You** tab, then **Import from another app**, and tap **Import Strava ZIP**.',
						'Wait for the import to finish. Runs you already have, for example from your Strava connection, are skipped, so it is safe to run it again.',
					],
				},
			],
		},
		{
			heading: 'Garmin and FIT files',
			blocks: [
				{
					type: 'p',
					text: 'An automatic Garmin Connect link isn\'t available yet because Garmin has to approve it. Until then you can import Garmin files on the web.',
				},
				{
					type: 'steps',
					items: [
						'In Garmin Connect, either export one activity with Export Original, which gives you a .fit file, or request your full data export from Garmin Account Management.',
						'On the web, open [[route:/settings/integrations|Integrations]], find **Bulk import from a Garmin export** and select **Choose Garmin export**.',
						'Pick the .fit file or the zip. Activities you already imported are skipped.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'On Android, workouts your Garmin, Samsung or Fitbit app writes to Health Connect can come in through **Import from another app** too. On an iPhone the same card reads Apple Health.',
				},
			],
		},
		{
			heading: 'GPX and other single files',
			blocks: [
				{
					type: 'p',
					text: 'A single GPX, KML, KMZ, GeoJSON or TCX file is imported as a route you can follow, not as a run in your history. Open [[route:/routes|Routes]] on the web or the routes list in the app and import it there.',
				},
				{
					type: 'p',
					text: 'GPX and TCX files inside a Strava or Garmin export zip are read as runs, so the bulk imports above are the way to add a history of GPX activities.',
				},
			],
		},
		{
			heading: 'If something doesn\'t import',
			blocks: [
				{
					type: 'p',
					text: 'When some activities are left out, the import lists each one and why, such as a dropped connection or a file that couldn\'t be read. Run the import again to retry them: anything that already landed is skipped, so nothing is duplicated.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Imported runs follow your default run privacy, so check it before a big import if you don\'t want years of runs to appear publicly at once. See [[guide:your-data-and-privacy|Your data and privacy]].',
				},
			],
		},
	],
	related: ['record-your-first-run', 'link-ultrasignup-results', 'your-data-and-privacy'],
};
