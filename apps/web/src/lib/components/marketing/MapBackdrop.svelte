<script lang="ts">
	// A stylised basemap behind the product preview's route.
	//
	// TrackPreview draws a polyline and nothing else — in the app a real
	// basemap sits under it, fetched from MapTiler, and that fetch is held
	// until consent because the endpoint logs the requester IP. The landing
	// page is the highest-traffic anonymous surface in the product, so it is
	// the last place to fire that request before the banner is answered
	// (audit/cookie-consent). Without something behind it the route floated on
	// a flat panel and read as a tile layer that had failed to load.
	//
	// So this is drawn, not fetched: deterministic geometry, no network, no
	// third party, no consent question, and every colour a token, so it
	// follows the theme like the rest of the shot. It is plainly stylised
	// rather than dressed up as a real place.
	//
	// It is drawn the way a map is layered: water and parks, then building
	// blocks, then every road's casing, then every road's fill, so crossings
	// merge instead of stacking. Two street districts at different angles and
	// two arterials that ignore both are what keep it from reading as graph
	// paper.

	// Class names here deliberately avoid the Material Symbols vocabulary.
	// The icon-font generator treats any quoted single word in it as a render
	// site, so a class that happens to be a ligature pulls a glyph nothing
	// draws into the subset. Every class below is hyphenated for that reason.

	type Pt = [number, number];
	type District = { origin: Pt; angle: number; rows: number; cols: number; dy: number; dx: number };

	const DISTRICTS: District[] = [
		{ origin: [-14, 40], angle: -6, rows: 5, cols: 7, dy: 25, dx: 22 },
		{ origin: [128, -18], angle: 14, rows: 5, cols: 5, dy: 24, dx: 27 },
	];

	// Parks and the lake, as ellipses, so blocks can be kept out of them.
	const OPEN_GROUND = [
		{ cx: 176, cy: 108, rx: 34, ry: 20 },
		{ cx: 42, cy: 22, rx: 30, ry: 15 },
		{ cx: 214, cy: 30, rx: 22, ry: 13 },
	];

	function rotate([x, y]: Pt, [ox, oy]: Pt, degrees: number): Pt {
		const r = (degrees * Math.PI) / 180;
		return [ox + x * Math.cos(r) - y * Math.sin(r), oy + x * Math.sin(r) + y * Math.cos(r)];
	}

	function inOpenGround([x, y]: Pt): boolean {
		return OPEN_GROUND.some((e) => ((x - e.cx) / e.rx) ** 2 + ((y - e.cy) / e.ry) ** 2 < 1.2);
	}

	// A fixed hash, not Math.random: the same map on every render and in SSR.
	function hash(n: number): number {
		const v = Math.sin(n * 127.1 + 311.7) * 43758.5453;
		return v - Math.floor(v);
	}

	const streets: string[] = [];
	const blocks: { x: number; y: number; w: number; h: number; t: string }[] = [];

	DISTRICTS.forEach((d, di) => {
		const at = (p: Pt) => rotate(p, d.origin, d.angle).map((v) => v.toFixed(1)).join(' ');
		const width = d.cols * d.dx;
		const height = d.rows * d.dy;
		for (let r = 0; r <= d.rows; r++) streets.push(`M${at([0, r * d.dy])}L${at([width, r * d.dy])}`);
		for (let c = 0; c <= d.cols; c++) streets.push(`M${at([c * d.dx, 0])}L${at([c * d.dx, height])}`);

		for (let r = 0; r < d.rows; r++) {
			for (let c = 0; c < d.cols; c++) {
				const seed = di * 100 + r * 10 + c;
				const centre = rotate([(c + 0.5) * d.dx, (r + 0.5) * d.dy], d.origin, d.angle);
				if (inOpenGround(centre) || hash(seed) < 0.18) continue;
				const split = hash(seed + 0.5) > 0.55;
				const pad = 3.2;
				const w = d.dx - pad * 2;
				const h = d.dy - pad * 2;
				const t = `rotate(${d.angle} ${d.origin[0]} ${d.origin[1]})`;
				const x = d.origin[0] + c * d.dx + pad;
				const y = d.origin[1] + r * d.dy + pad;
				if (split) {
					blocks.push({ x, y, w: w * 0.46, h, t }, { x: x + w * 0.54, y, w: w * 0.46, h, t });
				} else {
					blocks.push({ x, y, w, h, t });
				}
			}
		}
	});

	const ARTERIALS = [
		'M-8 118 C 40 96, 86 104, 120 76 S 188 30, 252 44',
		'M92 -8 C 100 40, 128 70, 124 112 S 150 160, 170 172',
	];
</script>

<svg
	class="backdrop"
	viewBox="0 0 240 160"
	preserveAspectRatio="xMidYMid slice"
	aria-hidden="true"
	focusable="false"
>
	<path
		class="map-river"
		d="M-8 146 C 30 132, 64 150, 104 142 S 170 120, 206 136 S 236 150, 250 146"
	/>
	<ellipse class="map-lake" cx="214" cy="30" rx="20" ry="11" />
	{#each OPEN_GROUND.slice(0, 2) as e, i (i)}
		<ellipse class="map-park" cx={e.cx} cy={e.cy} rx={e.rx} ry={e.ry} />
	{/each}

	{#each blocks as b, i (i)}
		<rect class="map-block" x={b.x} y={b.y} width={b.w} height={b.h} rx="1.4" transform={b.t} />
	{/each}

	{#each streets as d, i (i)}
		<path class="map-street-casing" {d} />
	{/each}
	{#each ARTERIALS as d, i (i)}
		<path class="map-arterial-casing" {d} />
	{/each}
	{#each streets as d, i (i)}
		<path class="map-street" {d} />
	{/each}
	{#each ARTERIALS as d, i (i)}
		<path class="map-arterial" {d} />
	{/each}
</svg>

<style>
	.backdrop {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		display: block;
	}

	/* Deliberately quiet. The route is the subject; this only has to stop the
	   panel reading as an empty frame, and read as a place.

	   The -text variants, not the base tokens: contrast_guard bans a bare
	   accent as a fill or stroke because it fails AA wherever it lands on a
	   light surface. These are decorative, but the theme-aware variant is the
	   right value anyway — the base green is candy-bright on a paper map.

	   Road fills are the page ground (--color-bg) over a border-tinted casing:
	   lighter than the land in light mode and darker than it in dark, which
	   reads as a road in both, where --color-surface would vanish into the
	   dark land it equals. */
	.map-park {
		fill: var(--color-success-text);
		opacity: 0.2;
	}

	.map-river {
		fill: none;
		stroke: var(--color-accent-cyan-text);
		stroke-width: 12;
		stroke-linecap: round;
		opacity: 0.3;
	}

	.map-lake {
		fill: var(--color-accent-cyan-text);
		opacity: 0.3;
	}

	.map-block {
		fill: var(--color-text-tertiary);
		opacity: 0.11;
	}

	.map-street-casing,
	.map-arterial-casing,
	.map-street,
	.map-arterial {
		fill: none;
		stroke-linecap: round;
		stroke-linejoin: round;
	}

	.map-street-casing {
		stroke: var(--color-border);
		stroke-width: 2.8;
		opacity: 0.22;
	}

	.map-street {
		stroke: var(--color-bg);
		stroke-width: 1.8;
		opacity: 0.9;
	}

	.map-arterial-casing {
		stroke: var(--color-border);
		stroke-width: 6;
		opacity: 0.3;
	}

	.map-arterial {
		stroke: var(--color-bg);
		stroke-width: 4.2;
	}
</style>
