import type { Guide } from '../types';

export const guide: Guide = {
	id: 'using-help',
	title: 'Finding help in the app',
	summary: 'Where the help guides live, how to search them, and how to jump from a screen to the guide that explains it.',
	kind: 'start',
	category: 'account',
	audience: ['everyone'],
	platforms: ['web'],
	routes: ['/help', '/help/search'],
	sections: [
		{
			heading: 'Opening help',
			blocks: [
				{
					type: 'steps',
					items: [
						'Select your name at the bottom of the sidebar. In a narrow window the sidebar shrinks to icons, so select the round avatar with your initial instead.',
						'Choose **Help** in the menu that opens.',
					],
				},
				{
					type: 'p',
					text: 'The contents page lists every guide by topic. The chips under **Show guides for** narrow the list to the guides written for you, such as **Organisers** or **Spectators**; **All** shows everything again.',
				},
			],
		},
		{
			heading: 'Searching the guides',
			blocks: [
				{
					type: 'p',
					text: 'Type a word or two into **Search the guides** at the top of [[route:/help|Help]] and press **Search**. Guides with your words in the title come first, then guides that mention them in the summary, then the rest.',
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Capitals and accents do not matter, so *cafe* finds *Café*. Every word you type has to appear somewhere in a guide for it to be listed.',
				},
			],
		},
		{
			heading: 'Help from the screen you are on',
			blocks: [
				{
					type: 'p',
					text: 'A screen that has a guide shows a **How this works** link near its title. It opens the guide for that screen; where several guides cover it, it opens a short list to choose from.',
				},
				{
					type: 'p',
					text: 'Some cards and settings carry a small round *i* button. It explains the feature in a sentence or two, and when a guide goes further it ends with **Read the guide**.',
				},
			],
		},
		{
			heading: 'Reading a guide',
			blocks: [
				{
					type: 'list',
					items: [
						'The badges under the title say which apps the guide applies to and whether you need something first, such as Pro or a club admin role.',
						'**On this page** lists the sections of a longer guide and jumps to the one you pick.',
						'**Related guides** at the end points to what you are likely to need next.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'Guides are shown in the language the app is set to. A guide that has not been translated into it yet is shown in English, with a note at the top saying so.',
				},
			],
		},
	],
};
