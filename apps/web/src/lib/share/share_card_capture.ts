/// The map card paints an opaque gradient edge to edge, so a capture of it is
/// opaque in every pixel. A capture that is not drew the card somewhere other
/// than inside its own frame: `html-to-image` copies the node's computed style
/// onto its clone, and a card offset off-screen by its own `top`/`left` was
/// rasterised fully transparent, a blank PNG with nothing thrown. The editor
/// showed it as an empty box and offered to download it.
export const MIN_CARD_OPAQUE_FRACTION = 0.99;

/// The fraction of the pixels in `rgba` (four bytes a pixel) whose alpha is
/// at least 250; 0 for no pixels at all.
export function opaqueFraction(rgba: ArrayLike<number>): number {
	const pixels = Math.floor(rgba.length / 4);
	if (pixels === 0) return 0;
	let opaque = 0;
	for (let i = 3; i < pixels * 4; i += 4) {
		if (rgba[i] >= 250) opaque++;
	}
	return opaque / pixels;
}

/// Whether a capture of the map card drew the card.
export function isCompleteCardCapture(rgba: ArrayLike<number>): boolean {
	return opaqueFraction(rgba) >= MIN_CARD_OPAQUE_FRACTION;
}
