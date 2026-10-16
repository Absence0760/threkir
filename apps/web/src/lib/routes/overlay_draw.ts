// When a MapLibre map may draw its overlays, and whether a draw has to clear
// the previous one first. Kept out of the component so every ordering of the
// three events can be pinned without a browser: Playwright can hold tiles to
// open one window, but not the others (decisions § 2043).
//
// The style carries no overlays from map creation until the first ready
// event, and none from `setStyle` until its `style.load`. In those windows a
// ready handler is already pending that draws whatever track is current when
// it fires, so a track change only records that the camera owes a refit.
//
// A style can be reported ready twice: `setStyle` before the initial `load`
// fires `style.load` for the new style and then `load` for the map. The
// second report redraws over a clean slate instead of adding the sources again.

export type OverlayStep = {
	/// Remove the overlays already on the style before drawing.
	clear: boolean;
	/// Draw the current track's overlays now.
	draw: boolean;
	/// Fit the camera to the track as part of the draw.
	fit: boolean;
};

const DEFER: OverlayStep = { clear: false, draw: false, fit: false };

export class OverlayDrawState {
	#onStyle = false;
	#refitPending = false;

	/// `load`, or the `style.load` after a `setStyle`.
	styleReady(fit: boolean): OverlayStep {
		const step = { clear: this.#onStyle, draw: true, fit: fit || this.#refitPending };
		this.#onStyle = true;
		this.#refitPending = false;
		return step;
	}

	/// `setStyle` has been called: the new style starts without overlays.
	styleSwapped(): void {
		this.#onStyle = false;
	}

	/// The track being shown changed.
	trackChanged(): OverlayStep {
		if (!this.#onStyle) {
			this.#refitPending = true;
			return DEFER;
		}
		return { clear: true, draw: true, fit: true };
	}
}
