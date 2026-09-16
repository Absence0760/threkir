import { motion } from './motion.svelte';
import { easeOutCubic, readingAt, parseReading, staggerDelay } from './motion';

// DOM actions for the public pages. Every one of them obeys the same contract,
// recorded in conventions.md § Motion:
//
//   1. The resting state is the markup's own. An animation only ever moves an
//      element away from where it already is and back, so no JS, a failed
//      hydration, or reduced motion all leave the finished page.
//   2. Only code that can reveal an element may hide it — never a stylesheet.
//   3. Nothing starts while `motion.still` — checked when the motion would
//      begin, not only at mount, so pausing before scrolling holds too.

const EASE = 'cubic-bezier(0.22, 1, 0.36, 1)';

function canAnimate(): boolean {
	return (
		typeof window !== 'undefined' &&
		typeof IntersectionObserver !== 'undefined' &&
		typeof Element.prototype.animate === 'function' &&
		!motion.still
	);
}

export type RevealOptions = {
	/// Stagger the node's children matching this selector instead of the node.
	items?: string;
	delay?: number;
	distance?: number;
};

/// Fades content up as it scrolls into view. Content already on screen at
/// mount is left alone: hiding it would flash the painted page blank for a
/// frame to animate something the visitor has already seen.
///
/// A revealed target also plays its `[data-grow="x|y"]` descendants (bars that
/// rise from their baseline), `[data-draw]` SVG paths (lines that trace
/// themselves) and `[data-pop]` descendants (marks that scale in), so a
/// card's figure builds itself as the card arrives.
export function reveal(node: HTMLElement, options: RevealOptions = {}) {
	if (!canAnimate()) return;
	const { items, delay = 0, distance = 28 } = options;
	const targets = items ? [...node.querySelectorAll<HTMLElement>(items)] : [node];
	const fold = window.innerHeight * 0.92;
	const pending = targets.filter((el) => el.getBoundingClientRect().top > fold);
	if (!pending.length) return;

	for (const el of pending) el.style.opacity = '0';
	const plays: Animation[] = [];

	const observer = new IntersectionObserver(
		(entries) => {
			const arriving = entries.filter((e) => e.isIntersecting).map((e) => e.target as HTMLElement);
			arriving.forEach((el, i) => {
				observer.unobserve(el);
				el.style.opacity = '';
				// Paused after mount: arrive at rest rather than animate in.
				if (motion.still) return;
				const start = delay + staggerDelay(i, 90);
				plays.push(
					el.animate(
						[
							{ opacity: 0, transform: `translateY(${distance}px)` },
							{ opacity: 1, transform: 'none' },
						],
						{ duration: 720, delay: start, easing: EASE, fill: 'backwards' },
					),
				);
				el.querySelectorAll<HTMLElement>('[data-grow]').forEach((bar, j) => {
					const axis = bar.dataset.grow === 'x' ? 'scaleX' : 'scaleY';
					plays.push(
						bar.animate([{ transform: `${axis}(0)` }, { transform: `${axis}(1)` }], {
							duration: 620,
							delay: start + 240 + staggerDelay(j, 45, 700),
							easing: EASE,
							fill: 'backwards',
						}),
					);
				});
				el.querySelectorAll<SVGPathElement>('[data-draw] path').forEach((path) => {
					const length = path.getTotalLength?.() ?? 0;
					if (!length) return;
					plays.push(
						path.animate(
							[
								{ strokeDasharray: `${length}`, strokeDashoffset: `${length}` },
								{ strokeDasharray: `${length}`, strokeDashoffset: '0' },
							],
							{ duration: 1500, delay: start + 200, easing: EASE, fill: 'backwards' },
						),
					);
				});
				el.querySelectorAll<Element>('[data-pop]').forEach((mark, j) => {
					plays.push(
						mark.animate(
							[
								{ opacity: 0, transform: 'scale(0.4)' },
								{ opacity: 1, transform: 'none' },
							],
							{
								duration: 460,
								delay: start + 380 + staggerDelay(j, 110, 900),
								easing: EASE,
								fill: 'backwards',
							},
						),
					);
				});
			});
		},
		{ rootMargin: '0px 0px -8% 0px' },
	);
	for (const el of pending) observer.observe(el);

	return {
		destroy() {
			observer.disconnect();
			for (const play of plays) play.cancel();
			for (const el of pending) el.style.opacity = '';
		},
	};
}

/// Counts a printed figure up from zero the first time it is seen, landing on
/// the markup's own text. Only readings `parseReading` understands move.
export function countUp(node: HTMLElement, options: { delay?: number; duration?: number } = {}) {
	const final = node.textContent ?? '';
	if (!canAnimate() || !parseReading(final)) return;
	const { delay = 0, duration = 1300 } = options;
	let frame = 0;
	let started = false;

	const run = () => {
		const begin = performance.now() + delay;
		const step = (now: number) => {
			const t = (now - begin) / duration;
			node.textContent = t <= 0 ? readingAt(final, 0) : readingAt(final, easeOutCubic(t));
			if (t < 1) frame = requestAnimationFrame(step);
		};
		frame = requestAnimationFrame(step);
	};

	const observer = new IntersectionObserver((entries) => {
		if (started || !entries.some((e) => e.isIntersecting)) return;
		started = true;
		observer.disconnect();
		if (!motion.still) run();
	});
	observer.observe(node);

	return {
		destroy() {
			observer.disconnect();
			cancelAnimationFrame(frame);
			node.textContent = final;
		},
	};
}

/// Tracks the pointer across a card as --spot-x / --spot-y, for a highlight
/// that follows it. Pointer-driven, so it is interaction feedback rather than
/// autoplaying motion; still skipped for touch, where there is no hover.
export function spotlight(node: HTMLElement) {
	if (typeof window === 'undefined' || !window.matchMedia?.('(hover: hover)').matches) return;
	let frame = 0;
	const onMove = (event: PointerEvent) => {
		cancelAnimationFrame(frame);
		frame = requestAnimationFrame(() => {
			const box = node.getBoundingClientRect();
			node.style.setProperty('--spot-x', `${event.clientX - box.left}px`);
			node.style.setProperty('--spot-y', `${event.clientY - box.top}px`);
		});
	};
	node.addEventListener('pointermove', onMove);
	return {
		destroy() {
			cancelAnimationFrame(frame);
			node.removeEventListener('pointermove', onMove);
		},
	};
}

/// Tilts an element a few degrees toward the pointer, as --tilt-x / --tilt-y.
/// The listener sits on `area` (the hero) so the shot leans as the pointer
/// crosses the whole section, not only while it is over the frame.
export function tilt(node: HTMLElement, options: { max?: number } = {}) {
	if (typeof window === 'undefined' || !window.matchMedia?.('(hover: hover)').matches) return;
	const area = node.parentElement ?? node;
	const max = options.max ?? 4;
	let frame = 0;

	const reset = () => {
		node.style.setProperty('--tilt-x', '0deg');
		node.style.setProperty('--tilt-y', '0deg');
	};
	const onMove = (event: PointerEvent) => {
		if (motion.still) return reset();
		cancelAnimationFrame(frame);
		frame = requestAnimationFrame(() => {
			const box = area.getBoundingClientRect();
			const dx = (event.clientX - box.left) / box.width - 0.5;
			const dy = (event.clientY - box.top) / box.height - 0.5;
			node.style.setProperty('--tilt-x', `${(-dy * max).toFixed(2)}deg`);
			node.style.setProperty('--tilt-y', `${(dx * max).toFixed(2)}deg`);
		});
	};
	area.addEventListener('pointermove', onMove);
	area.addEventListener('pointerleave', reset);
	return {
		destroy() {
			cancelAnimationFrame(frame);
			area.removeEventListener('pointermove', onMove);
			area.removeEventListener('pointerleave', reset);
		},
	};
}
