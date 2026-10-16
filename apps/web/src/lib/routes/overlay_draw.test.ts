import { test } from 'node:test';
import assert from 'node:assert/strict';

import { OverlayDrawState, type OverlayStep } from './overlay_draw.ts';

// A fake style that throws the way MapLibre's addSource does when the
// overlays are added twice, so each case reads as the crash it guards against.
function harness() {
	const state = new OverlayDrawState();
	let onStyle = false;
	const fits: boolean[] = [];
	const apply = (step: OverlayStep) => {
		if (step.clear) onStyle = false;
		if (step.draw) {
			if (onStyle) throw new Error('Source "trace" already exists');
			onStyle = true;
			fits.push(step.fit);
		}
	};
	return {
		state,
		fits,
		load: () => apply(state.styleReady(true)),
		trackChanged: () => apply(state.trackChanged()),
		setStyle: () => {
			state.styleSwapped();
			onStyle = false;
		},
		styleLoad: () => apply(state.styleReady(false)),
	};
}

test('a track change after load redraws and refits', () => {
	const h = harness();
	h.load();
	h.trackChanged();
	assert.deepEqual(h.fits, [true, true]);
});

test('a track change before load waits for load to draw it, once', () => {
	const h = harness();
	h.trackChanged();
	assert.deepEqual(h.fits, []);
	h.load();
	assert.deepEqual(h.fits, [true]);
});

test('two track changes before load still draw once', () => {
	const h = harness();
	h.trackChanged();
	h.trackChanged();
	h.load();
	assert.deepEqual(h.fits, [true]);
});

test('a track change while a swapped style loads is drawn by style.load, with the refit it owed', () => {
	const h = harness();
	h.load();
	h.setStyle();
	h.trackChanged();
	h.styleLoad();
	assert.deepEqual(h.fits, [true, true]);
});

test('a style swap with no track change keeps the camera where the runner left it', () => {
	const h = harness();
	h.load();
	h.setStyle();
	h.styleLoad();
	assert.deepEqual(h.fits, [true, false]);
});

// The settings-driven map style lands asynchronously on a cold page load, so
// `setStyle` can run before the initial `load`. MapLibre then reports the new
// style ready twice: its `style.load`, and the map's `load`.
test('a style swap before load draws on style.load and redraws on load without adding twice', () => {
	const h = harness();
	h.setStyle();
	h.styleLoad();
	h.load();
	assert.deepEqual(h.fits, [false, true]);
});

test('two style swaps before the first loads answer one style.load twice without adding twice', () => {
	const h = harness();
	h.load();
	h.setStyle();
	h.setStyle();
	h.styleLoad();
	h.styleLoad();
	assert.deepEqual(h.fits, [true, false, false]);
});
