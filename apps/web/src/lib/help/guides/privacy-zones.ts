import type { Guide } from '../types';

export const guide: Guide = {
	id: 'privacy-zones',
	title: 'Hide your home with privacy zones',
	summary: 'Draw a circle around home, work or anywhere else so the start and end of your runs and routes inside it are hidden from everyone but you.',
	kind: 'how-to',
	category: 'running',
	audience: ['runner'],
	platforms: ['web', 'android', 'ios'],
	routes: ['/settings/privacy'],
	sections: [
		{
			heading: 'What a privacy zone does',
			blocks: [
				{
					type: 'p',
					text: 'A privacy zone is a circle on the map. When a run or route starts or ends inside one, that part of the track is cut off before anyone else sees it, so the line appears to begin and end at the edge of the circle.',
				},
				{
					type: 'list',
					items: [
						'It applies to what other people see: shared runs and routes, your public profile, the feed, heatmaps and the live tracking page.',
						'It applies to runs you have already recorded as well as new ones, because the track is trimmed each time someone else views it.',
						'You always see your own full track, and files you export for yourself keep the full track too.',
					],
				},
				{
					type: 'illustration',
					id: 'privacy-zones',
					alt: 'A route line starts at a house inside a circle. The part inside the circle is hidden from other people, so the line they see begins at the circle\'s edge.',
				},
			],
		},
		{
			heading: 'Add a zone on the web',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open [[route:/settings/privacy|Privacy & sharing]] in Settings.',
						'Under **Privacy zones**, select **Add a zone**.',
						'Click the map where the zone should be centred, or select **Use current location**, then drag the marker to fine-tune it.',
						'Set the **Radius**. Anything inside the red circle is hidden from public shares.',
						'Select **Add zone**. The zone is saved straight away.',
					],
				},
				{
					type: 'p',
					text: 'To delete a zone, select **Remove** beside it and confirm. Removing a zone shows that area on public shares again.',
				},
			],
		},
		{
			heading: 'Add a zone on the phone app',
			blocks: [
				{
					type: 'steps',
					items: [
						'Open the **You** tab, then **Preferences**, and under **Privacy & sharing** tap **Privacy zones**.',
						'Tap the map to drop a zone. Use **Search places…** or **Locate me** to move the map first.',
						'Adjust the **Radius** slider.',
						'Tap **Save**. Nothing changes until you save.',
					],
				},
				{
					type: 'p',
					text: 'To delete a zone, tap its marker and confirm, or use **Clear all** to remove every zone at once. Then tap **Save**; removing a zone shows that area on public shares again.',
				},
			],
		},
		{
			heading: 'Choosing a good zone',
			blocks: [
				{
					type: 'list',
					items: [
						'Centre the zone near, rather than exactly on, your front door, so the edge of the circle doesn\'t point straight at your house.',
						'Make it big enough to cover a few streets. A tiny circle can still give your home away.',
						'Add one for anywhere you regularly start from, such as work or a friend\'s house.',
					],
				},
				{
					type: 'note',
					tone: 'caution',
					text: 'Zones trim the map line only. A run\'s title, description and photos are shown as you wrote them, so leave addresses out of those.',
				},
			],
		},
	],
	related: ['your-data-and-privacy', 'live-tracking-and-safety', 'record-your-first-run'],
};
