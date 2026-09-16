/// Topographic contour lines for the brand canvas, computed rather than drawn.
///
/// The canvas is a gradient, and a gradient alone has no surface — the
/// sign-in pane read as a coloured rectangle with copy on it. What belongs
/// behind a running product is the thing a runner already reads: contour
/// lines. A hand-drawn set of concentric blobs gives that away immediately,
/// because real contours are not concentric: they crowd where the ground is
/// steep, they pinch into saddles between two summits, and one level can
/// enclose two hills that the level above it separates.
///
/// So this samples an actual height field and traces its level sets with
/// marching squares. The saddles come out for free, because they are a
/// property of the field and not of the drawing.
///
/// Pure, deterministic, and free of any RNG: the same call returns the same
/// paths forever, which is what lets the output be a committed component
/// rather than a generated asset, and what lets a test assert its shape.
/// Nothing here fetches, so the pane owes no consent question for it (the
/// same reasoning as `MapBackdrop`).

/// A rounded hill. `h` is its peak height, `r` its falloff radius — both in
/// the same normalised 0..1 space as `x` / `y`, so the field is independent
/// of the pixel size it is later sampled at.
type Peak = { x: number; y: number; h: number; r: number };

/// Two summits and a lesser shoulder, placed off-centre and at different
/// radii. The pair close enough to interact is the point: their shared lower
/// levels enclose both, and the levels above them pinch apart into a saddle
/// across the middle of the canvas.
const PEAKS: Peak[] = [
	{ x: 0.26, y: 0.3, h: 1, r: 0.42 },
	{ x: 0.68, y: 0.62, h: 0.86, r: 0.38 },
	{ x: 0.92, y: 0.16, h: 0.44, r: 0.26 },
];

/// Height at a point, as the sum of every peak's Gaussian falloff plus two
/// low-frequency ripples.
///
/// The ripples are what stop the contours reading as tidy ovals: they bend
/// each level line without moving the summits, the way real ground does.
/// Their frequencies are deliberately not multiples of each other, so the
/// pattern does not visibly repeat across the canvas.
export function heightAt(x: number, y: number): number {
	let h = 0;
	for (const p of PEAKS) {
		const dx = (x - p.x) / p.r;
		const dy = (y - p.y) / p.r;
		h += p.h * Math.exp(-(dx * dx + dy * dy));
	}
	h += 0.055 * Math.sin(x * 7.3 + y * 2.1);
	h += 0.04 * Math.sin(y * 5.7 - x * 3.9);
	return h;
}

export type ContourOptions = {
	/// Width of the coordinate space the paths are emitted in (SVG user units).
	width: number;
	/// Height of that space.
	height: number;
	/// Sampling grid. Higher is smoother and costs path data; 48x48 is the
	/// point where a level line stops looking faceted at pane size.
	cols?: number;
	rows?: number;
	/// Height values to trace. One path string comes back per level that
	/// crosses the field at all.
	levels?: number[];
};

const DEFAULT_LEVELS = [0.12, 0.2, 0.3, 0.42, 0.55, 0.68, 0.8, 0.92, 1.04];

type Point = { x: number; y: number };
type Segment = [Point, Point];

/// Where along the edge from value `a` to value `b` the level sits. Linear,
/// which is what makes the traced line smooth rather than stepped — a
/// mid-edge crossing would quantise every contour to the sample grid.
function lerp(level: number, a: number, b: number): number {
	const span = b - a;
	// A zero span means both corners sit exactly on the level; the midpoint is
	// the only answer that cannot favour one corner over the other.
	return span === 0 ? 0.5 : (level - a) / span;
}

/// Marching squares over one cell, in the standard 16-case form collapsed to
/// "which edges does this level cross". Each corner is above or below the
/// level; the crossings always pair up into one or two segments.
function cellSegments(
	level: number,
	tl: number,
	tr: number,
	br: number,
	bl: number,
	x0: number,
	y0: number,
	dx: number,
	dy: number,
): Segment[] {
	const mask =
		(tl > level ? 8 : 0) | (tr > level ? 4 : 0) | (br > level ? 2 : 0) | (bl > level ? 1 : 0);
	if (mask === 0 || mask === 15) return [];

	const top = { x: x0 + dx * lerp(level, tl, tr), y: y0 };
	const right = { x: x0 + dx, y: y0 + dy * lerp(level, tr, br) };
	const bottom = { x: x0 + dx * lerp(level, bl, br), y: y0 + dy };
	const left = { x: x0, y: y0 + dy * lerp(level, tl, bl) };

	switch (mask) {
		case 1:
		case 14:
			return [[left, bottom]];
		case 2:
		case 13:
			return [[bottom, right]];
		case 3:
		case 12:
			return [[left, right]];
		case 4:
		case 11:
			return [[top, right]];
		case 6:
		case 9:
			return [[top, bottom]];
		case 7:
		case 8:
			return [[left, top]];
		// The two ambiguous saddles. Resolved by the cell's own average
		// height, which is the standard disambiguation and the one that keeps
		// a ridge continuous instead of snipping it into two corners.
		case 5:
			return (tl + tr + br + bl) / 4 > level
				? [
						[left, top],
						[bottom, right],
					]
				: [
						[left, bottom],
						[top, right],
					];
		case 10:
			return (tl + tr + br + bl) / 4 > level
				? [
						[top, right],
						[left, bottom],
					]
				: [
						[left, top],
						[bottom, right],
					];
		default:
			return [];
	}
}

/// Round to a fixed grid so two segments that share an endpoint produce the
/// same key. Without this the chaining below never joins anything, because
/// the two computations of one crossing differ in the last bits.
function key(p: Point): string {
	return `${p.x.toFixed(3)},${p.y.toFixed(3)}`;
}

/// Join loose segments end-to-end into polylines. A level set is made of
/// closed loops (and open ones where it runs off the canvas edge); emitting
/// each segment as its own `<path>` would work and would also be thousands
/// of DOM nodes, so they are chained first.
function chain(segments: Segment[]): Point[][] {
	const byStart = new Map<string, Segment[]>();
	for (const seg of segments) {
		for (const [from, to] of [seg, [seg[1], seg[0]] as Segment]) {
			const k = key(from);
			const bucket = byStart.get(k);
			if (bucket) bucket.push([from, to]);
			else byStart.set(k, [[from, to]]);
		}
	}

	const used = new Set<string>();
	/// A segment is identified by its unordered endpoint pair, so walking it
	/// forwards and later finding its reverse does not traverse it twice.
	const edgeKey = (a: Point, b: Point) => [key(a), key(b)].sort().join('|');

	const lines: Point[][] = [];
	for (const seg of segments) {
		if (used.has(edgeKey(seg[0], seg[1]))) continue;
		used.add(edgeKey(seg[0], seg[1]));

		const line = [seg[0], seg[1]];
		// Extend from the tail, then from the head, until neither end has an
		// unused continuation. Every crossing is shared by exactly two cells,
		// so a walk terminates either by closing the loop or by reaching the
		// canvas edge.
		for (const atHead of [false, true]) {
			for (;;) {
				const tip = atHead ? line[0] : line[line.length - 1];
				const next = (byStart.get(key(tip)) ?? []).find(
					(cand) => !used.has(edgeKey(cand[0], cand[1])),
				);
				if (!next) break;
				used.add(edgeKey(next[0], next[1]));
				if (atHead) line.unshift(next[1]);
				else line.push(next[1]);
			}
		}
		lines.push(line);
	}
	return lines;
}

/// One SVG `d` string per traced level, coarsest ground first.
///
/// A level that crosses nothing is dropped rather than emitted empty, so a
/// caller can index the result as "the contours that exist" and a `levels`
/// list reaching above the terrain costs nothing.
export function contourPaths(opts: ContourOptions): string[] {
	const { width, height } = opts;
	const cols = opts.cols ?? 48;
	const rows = opts.rows ?? 48;
	const levels = opts.levels ?? DEFAULT_LEVELS;

	// Sample once and trace every level off the same grid: the field is the
	// expensive part and it does not depend on the level.
	const grid: number[][] = [];
	for (let r = 0; r <= rows; r++) {
		const row: number[] = [];
		for (let c = 0; c <= cols; c++) row.push(heightAt(c / cols, r / rows));
		grid.push(row);
	}

	const dx = width / cols;
	const dy = height / rows;
	const out: string[] = [];

	for (const level of levels) {
		const segments: Segment[] = [];
		for (let r = 0; r < rows; r++) {
			for (let c = 0; c < cols; c++) {
				segments.push(
					...cellSegments(
						level,
						grid[r][c],
						grid[r][c + 1],
						grid[r + 1][c + 1],
						grid[r + 1][c],
						c * dx,
						r * dy,
						dx,
						dy,
					),
				);
			}
		}
		if (segments.length === 0) continue;

		const d = chain(segments)
			.filter((line) => line.length > 2)
			.map(
				(line) =>
					'M' +
					line.map((p) => `${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join('L') +
					// Close only a line whose ends actually meet: an open contour
					// runs off the canvas and a Z would draw a chord across it.
					(key(line[0]) === key(line[line.length - 1]) ? 'Z' : ''),
			)
			.join('');
		if (d) out.push(d);
	}

	return out;
}
