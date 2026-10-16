import type { Guide } from '../types';

export const guide: Guide = {
	id: 'adjust-a-plan-with-ai',
	title: 'Adjust a training plan with AI',
	summary: 'Describe a change to your plan in your own words, check every suggested edit, and save only when you agree with it.',
	kind: 'how-to',
	category: 'running',
	audience: ['runner'],
	platforms: ['web'],
	routes: ['/plans/[id]'],
	sections: [
		{
			heading: 'What it can change',
			blocks: [
				{
					type: 'p',
					text: 'Adjust with AI turns a request such as *move my long run to Saturday* or *make next week easier* into edits to a plan you have saved. It can move a workout to another day in the same week, swap two days, scale a week up or down a little, make a week a recovery week, or skip a workout.',
				},
				{
					type: 'p',
					text: 'Threkir\'s own plan rules carry out each change. The AI never writes a workout, a distance or a pace, so a request like *add a hill session* is answered with a note that it can\'t do that. Use **Edit plan** for anything else.',
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Adjust with AI is on the web only, and it may not be switched on yet. If **Adjust with AI** is not listed under **Adjust plan**, it isn\'t available to you.',
				},
			],
		},
		{
			heading: 'Ask for a change',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open your plan on the web and select **Adjust plan**.',
						'Choose **Adjust with AI**.',
						'Type what you want changed, then select **Suggest changes**.',
						'Read the **Suggested changes**: each workout that moves, is skipped or is eased, and each week target that changes, before and after.',
						'Select **Apply AI-suggested changes** to save them. Until you do, nothing in your plan has changed; select **Cancel** to leave it as it was.',
					],
				},
			],
		},
		{
			heading: 'Safety checks before saving',
			blocks: [
				{
					type: 'list',
					items: [
						'Changes that would push a week into the high injury-risk range for your recent training can\'t be applied. The page says which week.',
						'If the changes make a week harder than your recent training supports, or put two hard sessions on back-to-back days, you are asked **Apply harder changes?** and have to choose **Apply anyway**.',
						'A suggestion that couldn\'t be applied safely is left out, and the page tells you so.',
					],
				},
			],
		},
		{
			heading: 'What it uses',
			blocks: [
				{
					type: 'list',
					items: [
						'Each request uses one of your daily AI Coach messages, the same allowance as the Coach.',
						'It needs the latest AI disclosure. If you are asked to accept it, select **Review it in Settings** and accept it there.',
						'Only your plan\'s upcoming workouts and the change you typed are sent to the AI.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'You can also ask the Coach to change your plan. It replies with a link that opens Adjust with AI with your request already filled in.',
				},
			],
		},
	],
	related: ['what-pro-includes', 'your-data-and-privacy'],
};
