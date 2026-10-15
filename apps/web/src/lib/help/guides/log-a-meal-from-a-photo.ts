import type { Guide } from '../types';

export const guide: Guide = {
	id: 'log-a-meal-from-a-photo',
	title: 'Log a meal from a photo',
	summary: 'Photograph your plate, let Threkir estimate what is on it, then check and edit every item before it goes into your food log.',
	kind: 'how-to',
	category: 'running',
	audience: ['runner'],
	requires: ['pro'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/nutrition/log'],
	sections: [
		{
			heading: 'Before you start',
			blocks: [
				{
					type: 'list',
					items: [
						'Logging from a photo is part of Pro. Logging food by hand stays free.',
						'It uses AI, so it needs the latest AI disclosure. If you are asked to accept it, open Settings → Account and accept it there.',
						'The photo is used only to estimate what is on the plate. Location and camera details are removed before it is sent, and Threkir does not keep the photo.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'It may not be switched on yet. If you don\'t see **Log from a photo**, it isn\'t available to you.',
				},
			],
		},
		{
			heading: 'On the web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the [[route:/nutrition/log|Log food]] page.',
						'Under **Log from a photo**, select **Choose a photo** and pick a picture of your meal.',
						'Add a **Note (optional)** if it helps, such as half portion.',
						'Select **Estimate**.',
					],
				},
			],
		},
		{
			heading: 'On the phone app',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open **Fitness**, choose the **Nutrition** tab and tap the camera button, **Log from a photo**.',
						'Tap **Take a photo** or **Choose a photo**.',
						'Add a **Note (optional)** if it helps, then tap **Estimate**.',
					],
				},
			],
		},
		{
			heading: 'Check before you save',
			blocks: [
				{
					type: 'p',
					text: 'Under **Check these before saving**, each food is listed with its calories, protein, carbs and fat. They are estimates, so check them.',
				},
				{
					type: 'list',
					items: [
						'Change any name or number that looks wrong. Items marked **Low confidence** are the ones most worth a second look.',
						'Remove anything that isn\'t on your plate.',
						'Choose the **Meal** the food belongs to.',
						'Select **Save entries** to add what is left to your food log. Nothing is saved before that.',
					],
				},
				{
					type: 'note',
					tone: 'tip',
					text: 'If no food is recognised, or you have logged a lot of photos in the last hour, add the meal by hand as usual.',
				},
			],
		},
	],
	related: ['what-pro-includes', 'your-data-and-privacy'],
};
