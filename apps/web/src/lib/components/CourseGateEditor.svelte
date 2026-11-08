<script lang="ts">
	// One course's timing lines in the event editor (#1305, decisions § 2390).
	// Each line is moved on the map (drag the centre, drag the handle to turn
	// it) or with the numeric inputs, which reach every value without a
	// pointer. Every change saves at once through set_event_course_gate /
	// reset_event_course_gate; the lines are not part of the event form.
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import CourseLinesMap from '#lib/components/CourseLinesMap.svelte';
	import {
		fetchRouteById,
		resetEventCourseGate,
		setEventCourseGate,
		type CourseLinesRow
	} from '#lib/core/data.ts';
	import {
		COURSE_GATE_DEFAULT_HALF_WIDTH_M,
		COURSE_GATE_HALF_WIDTH_MAX_M,
		COURSE_GATE_HALF_WIDTH_MIN_M,
		clampHalfWidth,
		courseGate,
		gateWarnings,
		normalizeBearing,
		type CourseGate,
		type CourseGateWarning,
		type GatePoint,
		type GateWhich,
		type SessionStartMode
	} from '#lib/races/course_gates.ts';
	import type { DrawnGate } from '#lib/races/course_gate_layers.ts';
	import type { Gate } from '#lib/geo/gate_crossing.ts';

	interface Props {
		courseId: string;
		courseName: string;
		routeId: string | null;
		lines: CourseLinesRow | null;
		/// The race's start mode; Host GO until #1306 adds the others.
		mode?: SessionStartMode;
		onchanged: () => void | Promise<void>;
	}

	let { courseId, courseName, routeId, lines, mode = 'host_go', onchanged }: Props = $props();

	let route = $state<GatePoint[] | null>(null);
	let routeFailed = $state(false);
	let editing = $state<GateWhich>('finish');
	let busy = $state(false);
	let placing = $state(false);
	let error = $state<string | null>(null);
	let getCenter: (() => GatePoint | null) | null = null;

	let formLat = $state<number | null>(null);
	let formLng = $state<number | null>(null);
	let formBearing = $state<number | null>(null);
	let formWidth = $state<number>(COURSE_GATE_DEFAULT_HALF_WIDTH_M);

	const start = $derived(lines ? courseGate(lines, 'start') : null);
	const finish = $derived(lines ? courseGate(lines, 'finish') : null);
	const edited = $derived(editing === 'start' ? start : finish);
	const selfCross = $derived(lines?.finish_line_self_cross ?? false);

	const drawn = $derived<DrawnGate[]>([
		...(start ? [{ which: 'start' as const, gate: start, courseId }] : []),
		...(finish ? [{ which: 'finish' as const, gate: finish, courseId }] : [])
	]);

	const warnings = $derived({
		start: gateWarnings({ which: 'start', gate: start, route, selfCross, mode }),
		finish: gateWarnings({ which: 'finish', gate: finish, route, selfCross, mode })
	});

	$effect(() => {
		const id = routeId;
		route = null;
		routeFailed = false;
		if (!id) return;
		fetchRouteById(id)
			.then((r) => {
				if (routeId !== id) return;
				const pts = (r?.waypoints ?? []).filter(
					(p): p is GatePoint => Number.isFinite(p?.lat) && Number.isFinite(p?.lng)
				);
				route = pts.map((p) => ({ lat: p.lat, lng: p.lng }));
			})
			.catch((e) => {
				console.warn('CourseGateEditor: route read failed', e);
				routeFailed = true;
			});
	});

	// The inputs follow the line being edited whenever the server's copy moves.
	$effect(() => {
		const g = edited;
		if (placing && !g) return;
		formLat = g ? round(g.lat, 6) : null;
		formLng = g ? round(g.lng, 6) : null;
		formBearing = g ? round(g.bearingDeg, 1) : null;
		formWidth = g ? g.halfWidthM : COURSE_GATE_DEFAULT_HALF_WIDTH_M;
	});

	function round(v: number, places: number): number {
		const f = 10 ** places;
		return Math.round(v * f) / f;
	}

	async function save(which: GateWhich, gate: Gate) {
		if (busy) return;
		busy = true;
		error = null;
		try {
			await setEventCourseGate(courseId, which, {
				lat: gate.lat,
				lng: gate.lng,
				bearingDeg: normalizeBearing(gate.bearingDeg),
				halfWidthM: clampHalfWidth(gate.halfWidthM)
			});
			placing = false;
			await onchanged();
		} catch (e) {
			error = errorCopy(e, m, 'courseLines.saveFailed', 'courseLines.saveFailed');
		} finally {
			busy = false;
		}
	}

	async function reset(which: GateWhich) {
		if (busy) return;
		busy = true;
		error = null;
		try {
			await resetEventCourseGate(courseId, which);
			await onchanged();
		} catch (e) {
			error = errorCopy(e, m, 'courseLines.saveFailed', 'courseLines.saveFailed');
		} finally {
			busy = false;
		}
	}

	// The editor sits inside the event form, so this is a group, not a form:
	// Enter in one of its inputs applies the line instead of saving the event.
	function onFormKey(e: KeyboardEvent) {
		if (e.key === 'Enter' && e.target instanceof HTMLInputElement) {
			e.preventDefault();
			applyForm();
		}
	}

	function applyForm() {
		if (
			formLat === null ||
			formLng === null ||
			formBearing === null ||
			!Number.isFinite(formLat) ||
			!Number.isFinite(formLng) ||
			!Number.isFinite(formBearing) ||
			Math.abs(formLat) > 90 ||
			Math.abs(formLng) > 180
		) {
			error = m('courseLines.positionInvalid');
			return;
		}
		void save(editing, { lat: formLat, lng: formLng, bearingDeg: formBearing, halfWidthM: formWidth });
	}

	/// Where a new line goes: where the map is looking, else beside the other
	/// line, else the route's end on that side.
	function placementPoint(which: GateWhich): GatePoint | null {
		const c = getCenter?.();
		if (c) return c;
		const other = which === 'start' ? finish : start;
		if (other) return { lat: other.lat, lng: other.lng };
		if (route && route.length > 0) return which === 'start' ? route[0] : route[route.length - 1];
		return null;
	}

	function place(which: GateWhich) {
		editing = which;
		error = null;
		const p = placementPoint(which);
		if (!p) {
			// Nowhere to put it yet (no map, no route, no other line): open the
			// inputs empty so the position can be typed.
			placing = true;
			formLat = null;
			formLng = null;
			formBearing = 0;
			formWidth = COURSE_GATE_DEFAULT_HALF_WIDTH_M;
			return;
		}
		const other = which === 'start' ? finish : start;
		void save(which, {
			lat: p.lat,
			lng: p.lng,
			bearingDeg: other?.bearingDeg ?? 0,
			halfWidthM: COURSE_GATE_DEFAULT_HALF_WIDTH_M
		});
	}

	const WARNING_COPY: Record<CourseGateWarning, () => string> = {
		far_from_route: () => m('courseLines.warnFarFromRoute'),
		against_route: () => m('courseLines.warnAgainstRoute'),
		self_cross: () => m('courseLines.warnSelfCross'),
		start_required: () => m('courseLines.warnStartRequired')
	};

	function sourceCopy(g: CourseGate | null): string {
		if (!g) return m('courseLines.sourceNone');
		return g.source === 'organiser' ? m('courseLines.sourceOrganiser') : m('courseLines.sourceDerived');
	}

	const ids = $derived({
		lat: `gate-lat-${courseId}`,
		lng: `gate-lng-${courseId}`,
		bearing: `gate-bearing-${courseId}`,
		width: `gate-width-${courseId}`,
		widthNum: `gate-width-num-${courseId}`
	});
</script>

<section class="gate-editor" data-testid="course-gate-editor" aria-label={m('courseLines.editorLabel', { name: courseName })}>
	<h4>{courseName}</h4>

	<CourseLinesMap
		gates={drawn}
		{route}
		editWhich={edited ? editing : null}
		onedit={(which, gate) => save(which, gate)}
		oncenter={(fn) => (getCenter = fn)}
		label={m('courseLines.mapLabel', { name: courseName })}
		testid="course-gate-map"
	/>
	{#if routeFailed}
		<p class="muted small">{m('courseLines.routeUnavailable')}</p>
	{/if}

	<div class="lines">
		{#each ['start', 'finish'] as const as which (which)}
			{@const g = which === 'start' ? start : finish}
			<div class="line-row" class:active={editing === which} data-testid="course-gate-{which}">
				<div class="line-head">
					<span class="swatch swatch-{which}" aria-hidden="true"></span>
					<strong>{which === 'start' ? m('courseLines.startLine') : m('courseLines.finishLine')}</strong>
					<span class="muted small" data-testid="course-gate-{which}-source">{sourceCopy(g)}</span>
				</div>
				<div class="line-actions">
					{#if g}
						<button
							type="button"
							class="btn btn-secondary btn-sm"
							aria-pressed={editing === which}
							onclick={() => (editing = which)}
							data-testid="course-gate-{which}-edit"
						>
							{m('courseLines.edit')}
						</button>
						{#if g.source === 'organiser'}
							<button
								type="button"
								class="btn-link"
								disabled={busy}
								onclick={() => reset(which)}
								data-testid="course-gate-{which}-reset"
							>
								{routeId ? m('courseLines.resetToRoute') : m('courseLines.remove')}
							</button>
						{/if}
					{:else}
						<button
							type="button"
							class="btn btn-secondary btn-sm"
							disabled={busy}
							onclick={() => place(which)}
							data-testid="course-gate-{which}-place"
						>
							{which === 'start' ? m('courseLines.placeStart') : m('courseLines.placeFinish')}
						</button>
					{/if}
				</div>
				{#each warnings[which] as w (w)}
					<p class="warn" role="status" data-testid="course-gate-warning-{w}">
						<span class="material-symbols" aria-hidden="true">warning</span>
						{WARNING_COPY[w]()}
					</p>
				{/each}
			</div>
		{/each}
	</div>

	{#if edited || placing}
		<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
		<div
			class="gate-form"
			role="group"
			aria-label={editing === 'start' ? m('courseLines.editingStart') : m('courseLines.editingFinish')}
			onkeydown={onFormKey}
			data-testid="course-gate-form"
		>
			<p class="muted small">
				{editing === 'start' ? m('courseLines.editingStart') : m('courseLines.editingFinish')}
			</p>
			<div class="grid">
				<label for={ids.lat}>{m('courseLines.latitude')}</label>
				<input id={ids.lat} type="number" step="0.000001" min="-90" max="90" bind:value={formLat} data-testid="course-gate-lat" />
				<label for={ids.lng}>{m('courseLines.longitude')}</label>
				<input id={ids.lng} type="number" step="0.000001" min="-180" max="180" bind:value={formLng} data-testid="course-gate-lng" />
				<label for={ids.bearing}>{m('courseLines.direction')}</label>
				<input
					id={ids.bearing}
					type="number"
					step="1"
					min="0"
					max="359"
					bind:value={formBearing}
					aria-describedby="{ids.bearing}-hint"
					data-testid="course-gate-bearing"
				/>
				<span id="{ids.bearing}-hint" class="muted small span2">{m('courseLines.directionHint')}</span>
				<label for={ids.width}>{m('courseLines.halfWidth')}</label>
				<div class="width">
					<input
						id={ids.width}
						type="range"
						min={COURSE_GATE_HALF_WIDTH_MIN_M}
						max={COURSE_GATE_HALF_WIDTH_MAX_M}
						step="1"
						bind:value={formWidth}
						data-testid="course-gate-width"
					/>
					<input
						id={ids.widthNum}
						type="number"
						min={COURSE_GATE_HALF_WIDTH_MIN_M}
						max={COURSE_GATE_HALF_WIDTH_MAX_M}
						step="1"
						bind:value={formWidth}
						aria-label={m('courseLines.halfWidthMetres')}
						data-testid="course-gate-width-number"
					/>
					<span aria-hidden="true">{m('courseLines.metresUnit')}</span>
				</div>
			</div>
			<button type="button" class="btn btn-primary btn-sm" disabled={busy} onclick={applyForm} data-testid="course-gate-apply">
				{m('courseLines.apply')}
			</button>
		</div>
	{/if}

	{#if error}
		<p class="error" role="alert" data-testid="course-gate-error">{error}</p>
	{/if}
</section>

<style>
	.gate-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.gate-editor h4 {
		margin: 0;
	}
	.lines {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.line-row {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		padding: var(--space-sm);
		border-radius: var(--radius-sm);
	}
	.line-row.active {
		background: var(--color-bg-secondary);
	}
	.line-head,
	.line-actions {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.swatch {
		width: 18px;
		height: 4px;
		border-radius: 2px;
	}
	.swatch-start {
		background: var(--color-success);
	}
	.swatch-finish {
		background: var(--color-danger);
	}
	.warn {
		display: flex;
		align-items: flex-start;
		gap: var(--space-xs);
		margin: 0;
		color: var(--color-warning-text);
	}
	.gate-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		align-items: flex-start;
	}
	.grid {
		display: grid;
		grid-template-columns: max-content minmax(0, 1fr);
		gap: var(--space-xs) var(--space-sm);
		align-items: center;
		width: 100%;
	}
	.span2 {
		grid-column: 1 / -1;
	}
	.width {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.width input[type='number'] {
		width: 5rem;
	}
	.small {
		font-size: 0.85rem;
	}
	.error {
		color: var(--color-danger-text);
		margin: 0;
	}
</style>
