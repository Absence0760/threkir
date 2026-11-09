<script lang="ts">
	import Modal from './Modal.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { formatDistance } from '#lib/format/units.svelte.ts';
	import { formatDuration } from '#lib/format/time.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { AID_SERVICES, kindSpec } from '#lib/routes/route_markers.ts';
	import { courseDriveEnabled } from '#lib/routes/course_drive_flag.ts';
	import { checkDrivable } from '#lib/routes/course_drive_check.ts';
	import {
		MAPS_WAYPOINT_CAP,
		buildDriveNotes,
		mapsLegUrl,
		mapsStartUrl,
		planDriveLegs,
		type CourseStretch,
		type DriveNote,
		type DrivePoint,
		type MapsApp,
	} from '#lib/routes/course_drive.ts';
	import type { RouteMarker } from '#lib/types.ts';

	let {
		points,
		markers,
		title,
	}: {
		/// The line the page already renders: `clip_route_for_viewer`'s output
		/// for a non-owner, so the hand-off can show no more than the map does.
		points: readonly DrivePoint[];
		/// `route_markers_for_viewer` rows, already redacted for this viewer.
		markers: readonly RouteMarker[];
		title: string;
	} = $props();

	const enabled = courseDriveEnabled();
	let open = $state(false);
	let app = $state<MapsApp>('google');
	let check = $state<'idle' | 'checking' | 'done' | 'failed'>('idle');
	let stretches = $state<CourseStretch[]>([]);
	let controller: AbortController | null = null;

	const usable = $derived(points.filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lng)));
	const coarsePointer =
		typeof window !== 'undefined' && window.matchMedia?.('(pointer: coarse)').matches === true;
	const cap = $derived(
		app === 'google'
			? coarsePointer
				? MAPS_WAYPOINT_CAP.googleMobileWeb
				: MAPS_WAYPOINT_CAP.google
			: MAPS_WAYPOINT_CAP[app],
	);
	const legs = $derived(planDriveLegs(usable, cap));
	const notes = $derived(
		buildDriveNotes(
			markers.map((mk) => ({
				kind: mk.kind,
				label: mk.label,
				lat: mk.lat,
				lng: mk.lng,
				position_m: mk.position_m,
				meta: mk.meta,
			})),
			usable,
		),
	);

	async function openDialog() {
		open = true;
		if (check !== 'idle' || !auth.user) {
			if (!auth.user) check = 'failed';
			return;
		}
		check = 'checking';
		controller = new AbortController();
		const result = await checkDrivable(usable, controller.signal);
		if (result === null) {
			check = 'failed';
		} else {
			stretches = result;
			check = 'done';
		}
	}

	function closeDialog() {
		open = false;
	}

	$effect(() => () => controller?.abort());

	function serviceLabel(s: string): string {
		return (AID_SERVICES as string[]).includes(s) ? m(`routeMarker.service.${s}` as 'routeMarker.service.water') : s;
	}

	function noteDetail(n: DriveNote): string | null {
		if (n.services.length > 0) return n.services.map(serviceLabel).join(', ');
		if (n.cutoff?.clock) return m('courseDrive.cutoffClock', { clock: n.cutoff.clock });
		if (n.cutoff?.elapsedS != null) {
			return m('courseDrive.cutoffElapsed', { time: formatDuration(n.cutoff.elapsedS) });
		}
		if (n.climb) {
			return m('courseDrive.climbDetail', {
				distance: formatDistance(n.climb.lengthM),
				grade: String(n.climb.gradePct),
			});
		}
		return null;
	}
</script>

{#if enabled && legs.length > 0}
	<button
		type="button"
		class="btn btn-outline btn-sm"
		data-testid="course-drive-open"
		aria-haspopup="dialog"
		onclick={openDialog}
	>
		<span class="material-symbols" aria-hidden="true">directions_car</span>
		{m('courseDrive.button')}
	</button>
	<Modal
		{open}
		title={m('courseDrive.dialogTitle', { title })}
		onclose={closeDialog}
		bodyClass="drive-body"
		data-testid="course-drive-dialog"
	>
		<p class="notice" data-testid="course-drive-notice">{m('courseDrive.notice')}</p>

		<fieldset class="apps">
			<legend>{m('courseDrive.appLabel')}</legend>
			<label><input type="radio" bind:group={app} value="google" />{m('courseDrive.appGoogle')}</label>
			<label><input type="radio" bind:group={app} value="apple" />{m('courseDrive.appApple')}</label>
			<label><input type="radio" bind:group={app} value="waze" />{m('courseDrive.appWaze')}</label>
		</fieldset>

		<a
			class="btn btn-outline btn-sm"
			href={mapsStartUrl(app, usable[0])}
			target="_blank"
			rel="noopener noreferrer"
			data-testid="course-drive-start"
		>
			{m('courseDrive.toStart')}
		</a>

		<section aria-labelledby="course-drive-legs">
			<h3 id="course-drive-legs">{m('courseDrive.legsHeading')}</h3>
			<ol class="legs" data-testid="course-drive-legs">
				{#each legs as leg (leg.index)}
					<li>
						<a href={mapsLegUrl(app, leg)} target="_blank" rel="noopener noreferrer">
							{m('courseDrive.leg', {
								n: String(leg.index + 1),
								from: formatDistance(leg.start.alongM),
								to: formatDistance(leg.end.alongM),
							})}
						</a>
					</li>
				{/each}
			</ol>
			<p class="hint">{m('courseDrive.guidanceOnly')}</p>
		</section>

		<section aria-live="polite" data-testid="course-drive-check" data-state={check}>
			{#if check === 'checking'}
				<p class="hint">{m('courseDrive.checking')}</p>
			{:else if check === 'failed'}
				<p class="hint">{m('courseDrive.checkFailed')}</p>
			{:else if check === 'done' && stretches.length === 0}
				<p class="hint">{m('courseDrive.allDrivable')}</p>
			{:else if check === 'done'}
				<h3>{m('courseDrive.undrivableHeading')}</h3>
				<ul data-testid="course-drive-undrivable">
					{#each stretches as s, i (i)}
						<li>
							{m('courseDrive.stretch', { from: formatDistance(s.startM), to: formatDistance(s.endM) })}
						</li>
					{/each}
				</ul>
			{/if}
		</section>

		<section class="drive-notes" aria-labelledby="course-drive-notes">
			<div class="notes-head">
				<h3 id="course-drive-notes">{m('courseDrive.notesHeading')}</h3>
				{#if notes.length > 0}
					<button type="button" class="btn btn-outline btn-sm print" onclick={() => window.print()}>
						<span class="material-symbols" aria-hidden="true">print</span>
						{m('courseDrive.print')}
					</button>
				{/if}
			</div>
			<p class="print-title">{title}</p>
			{#if notes.length === 0}
				<p class="hint">{m('courseDrive.noNotes')}</p>
			{:else}
				<ol class="notes" data-testid="course-drive-notes">
					{#each notes as n, i (i)}
						{@const detail = noteDetail(n)}
						<li>
							<span class="note-at">{formatDistance(n.alongM)}</span>
							<span class="note-kind">{m(kindSpec(n.kind).labelKey as 'routeMarker.kind.aid_station')}</span>
							{#if n.label}<span class="note-label">{n.label}</span>{/if}
							{#if detail}<span class="note-detail">{detail}</span>{/if}
						</li>
					{/each}
				</ol>
			{/if}
			<p class="hint">{m('courseDrive.appHint')}</p>
		</section>
	</Modal>
{/if}

<style>
	:global(.drive-body) {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.notice {
		margin: 0;
		padding: 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.88rem;
	}
	.apps {
		display: flex;
		flex-wrap: wrap;
		gap: 0.75rem;
		border: none;
		padding: 0;
		margin: 0;
	}
	.apps label {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
	}
	h3 {
		font-size: 0.95rem;
		margin: 0 0 0.5rem;
	}
	.legs,
	.notes {
		margin: 0;
		padding-inline-start: 1.25rem;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.notes li {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
	}
	.note-at {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
	.note-kind {
		color: var(--color-text-secondary);
	}
	.note-detail {
		color: var(--color-text-secondary);
	}
	.notes-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
	}
	.hint {
		margin: 0.25rem 0 0;
		font-size: 0.82rem;
		color: var(--color-text-secondary);
	}
	.print-title {
		display: none;
	}
	@media print {
		:global(body *) {
			visibility: hidden;
		}
		.drive-notes,
		.drive-notes :global(*) {
			visibility: visible;
		}
		.drive-notes {
			position: absolute;
			inset: 0 auto auto 0;
		}
		.print-title {
			display: block;
			font-weight: 600;
		}
		.print {
			display: none;
		}
	}
</style>
