/// Where everything sits on the recap share image, for both aspects. The web
/// SVG (`recap_share_image.ts`) and the mobile painter
/// (`apps/mobile_android/lib/recap_card_layout.dart`) both read their
/// coordinates from here, so a square card and a story look the same on
/// either platform. Every y is a text baseline in a canvas `width` x `height`
/// pixels across.
///
/// The story keeps its content clear of the top and bottom bands a story
/// viewer draws its own UI over (the progress bar and the reply box), and
/// carries the site address in the space below the grid; the square card has
/// no footer, as it never did.

export type RecapCardAspect = 'square' | 'story';

export const RECAP_CARD_ASPECTS: readonly RecapCardAspect[] = ['square', 'story'];

export interface RecapCardLayout {
	width: number;
	height: number;
	pad: number;
	brandY: number;
	kickerY: number;
	heroY: number;
	subheadY: number;
	gridTop: number;
	colW: number;
	rowH: number;
	/// Gap from a cell's label baseline down to its value baseline.
	valueDy: number;
	footerY: number | null;
}

const WIDTH = 1080;
const PAD = 72;

export function recapCardLayout(aspect: RecapCardAspect): RecapCardLayout {
	const story = aspect === 'story';
	const height = story ? 1920 : WIDTH;
	const top = story ? 360 : PAD;
	const gridGap = story ? 160 : 0;
	return {
		width: WIDTH,
		height,
		pad: PAD,
		brandY: top + 28,
		kickerY: top + 110,
		heroY: top + 280,
		subheadY: top + 350,
		gridTop: top + 440 + gridGap,
		colW: (WIDTH - PAD * 2) / 2,
		rowH: story ? 200 : 150,
		valueDy: 58,
		footerY: story ? height - 300 : null,
	};
}

/// The label and value baselines of stat cell `index` in the two-column grid.
export function recapCellOrigin(
	layout: RecapCardLayout,
	index: number,
): { x: number; labelY: number; valueY: number } {
	const col = index % 2;
	const row = Math.floor(index / 2);
	const labelY = layout.gridTop + row * layout.rowH;
	return { x: layout.pad + col * layout.colW, labelY, valueY: labelY + layout.valueDy };
}
