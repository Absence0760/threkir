import type { Guide } from '../types';

export const guide: Guide = {
	id: 'link-ultrasignup-results',
	title: 'Link your UltraSignup results',
	summary: 'Find your UltraSignup profile by name, confirm which person is you, then import an ultra or trail result from the race calendar.',
	kind: 'how-to',
	category: 'running',
	audience: ['runner'],
	platforms: ['web'],
	routes: ['/settings/integrations', '/races', '/runs/[id]'],
	sections: [
		{
			heading: 'Before you start',
			blocks: [
				{
					type: 'note',
					tone: 'caution',
					text: 'UltraSignup import is web-only and is switched off until it has been enabled. If the UltraSignup card is missing from Integrations, or says **UltraSignup import isn\'t available yet. parkrun and manual paste still work.**, you can still add a result by pasting it on the race calendar.',
				},
				{
					type: 'p',
					text: 'UltraSignup handles entries and results for many trail and ultra races. Linking your profile once means you never type your name or bib again when importing a result.',
				},
			],
		},
		{
			heading: 'Link your profile',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open [[route:/settings/integrations|Integrations]] in Settings and find the UltraSignup card.',
						'Under **Find your UltraSignup profile**, enter your **First name** and **Last name** exactly as you enter races, then select **Find me**.',
						'UltraSignup lists everyone with that name. Use each person\'s age, number of results and most recent races to spot yourself.',
						'Under **Which of these is you?**, select **This is me** on your entry.',
					],
				},
				{
					type: 'p',
					text: 'The card now shows **Linked as** with your name and UltraSignup number. If you picked the wrong person, select **Unlink** and search again. Runs you already imported stay when you unlink.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'If you see **UltraSignup has nobody by that name. Check the spelling you race under.**, try the exact spelling on your race entries, including any middle name or hyphen.',
				},
			],
		},
		{
			heading: 'Import a result from the race calendar',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open [[route:/races|Races]] and find the race you ran.',
						'Select **Import my result**. The importer shows who it is importing as.',
						'Confirm the import. Only your own result for that race comes across, matched on UltraSignup\'s race id and the race date.',
					],
				},
				{
					type: 'p',
					text: 'The result arrives as a run with your official time and placings. If you recorded the race yourself, open that run instead: when it matches a race in the calendar, the run asks whether this was that race, and selecting **Import result** adds the official result to the run you already have rather than creating a second one.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Only finished results are imported, and a race whose id or date doesn\'t match is skipped rather than guessed. Very few UltraSignup races are in the calendar yet, so your race may not be listed; use **Paste your result** on the race calendar instead.',
				},
				{
					type: 'p',
					text: 'If you see **Link your UltraSignup profile in Settings first, then import from here.**, link your profile as above and come back.',
				},
			],
		},
	],
	related: ['import-your-history', 'racing-in-a-race', 'your-data-and-privacy'],
};
