<script lang="ts">
	import { effective } from '$lib/settings/settings';
	import { m } from '$lib/i18n/store.svelte';
	import { ACTIVITY_TYPES } from '$lib/runs/activity_type';
	import { activityTypeLabel } from '$lib/runs/activity_type.svelte';
	import {
		VOICE_CUE_IDS,
		VOICE_FEEDBACK_ENABLED_DEFAULT,
		isVoiceCueEnabled,
		readVoiceCueMap,
		setVoiceCueEnabled,
		type VoiceCueId,
		type VoiceCueMap,
	} from '$lib/settings/voice_cues';
	import type { MessageKey } from '$lib/i18n/messages';
	import { createPrefsPage } from '$lib/settings/prefs_page.svelte';
	import PrefsPage from '$lib/components/settings/PrefsPage.svelte';

	let preferredUnit = $state<'km' | 'mi'>('km');
	let defaultActivity = $state<'run' | 'walk' | 'hike' | 'cycle' | 'stroller'>('run');
	let voiceFeedbackEnabled = $state(VOICE_FEEDBACK_ENABLED_DEFAULT);
	// 'full' (default) speaks every cue; 'minimal' drops the chatty in-rep
	// progress + pace-drift nudges on the recording clients (round-5 older).
	let voiceFeedbackVerbosity = $state('full');
	// Canonical store is km (`voice_feedback_interval_km`); the field shows and
	// accepts the runner's unit, so a miles runner entering 1 gets 1-mile
	// splits, not 1 km.
	const KM_PER_MI = 1.609344;
	let voiceFeedbackIntervalKm = $state('1.0');
	// Sparse map of cue id -> bool; an absent id is ON (voice_cues.ts).
	let voiceCueTypes = $state<VoiceCueMap>({});
	// Keyed by VoiceCueId so the compiler refuses a cue id with no label —
	// a missing row would be a cue the runner can never turn off.
	const VOICE_CUE_LABELS: Record<VoiceCueId, { label: MessageKey; hint: MessageKey }> = {
		splits: { label: 'prefs.cue.splits', hint: 'prefs.cue.splitsHint' },
		start_finish: { label: 'prefs.cue.startFinish', hint: 'prefs.cue.startFinishHint' },
		off_route: { label: 'prefs.cue.offRoute', hint: 'prefs.cue.offRouteHint' },
		pace_alerts: { label: 'prefs.cue.paceAlerts', hint: 'prefs.cue.paceAlertsHint' },
		workout_steps: { label: 'prefs.cue.workoutSteps', hint: 'prefs.cue.workoutStepsHint' },
		cutoff_catch_up: { label: 'prefs.cue.cutoffCatchUp', hint: 'prefs.cue.cutoffCatchUpHint' },
		marker_targets: { label: 'prefs.cue.markerTargets', hint: 'prefs.cue.markerTargetsHint' },
		phase_transitions: {
			label: 'prefs.cue.phaseTransitions',
			hint: 'prefs.cue.phaseTransitionsHint',
		},
		guided_run: { label: 'prefs.cue.guidedRun', hint: 'prefs.cue.guidedRunHint' },
	};

	const prefs = createPrefsPage(async ({ settings, preferredUnit: unit }) => {
		preferredUnit = unit;
		defaultActivity = effective(settings, 'default_activity_type', 'run') ?? 'run';
		voiceFeedbackEnabled =
			effective(settings, 'voice_feedback_enabled', VOICE_FEEDBACK_ENABLED_DEFAULT) ??
			VOICE_FEEDBACK_ENABLED_DEFAULT;
		voiceFeedbackVerbosity = effective<string>(settings, 'voice_feedback_verbosity', 'full') ?? 'full';
		voiceFeedbackIntervalKm = (
			effective<number>(settings, 'voice_feedback_interval_km', 1.0) ?? 1.0
		).toString();
		voiceCueTypes = readVoiceCueMap(effective<unknown>(settings, 'voice_cue_types'));
	});

	function toggleVoiceCue(id: VoiceCueId, on: boolean) {
		voiceCueTypes = setVoiceCueEnabled(voiceCueTypes, id, on);
		prefs.save({ voice_cue_types: voiceCueTypes });
	}
</script>

<PrefsPage heading={m('prefs.activityRecordingHeading')} tagline={m('prefs.recordingTagline')} page={prefs}>
	<section class="card">
		<h2>{m('prefs.startingRunHeading')}</h2>
		<div class="form-grid">
			<label>
				<span class="label-text">{m('prefs.defaultActivity')}</span>
				<select bind:value={defaultActivity} onchange={() => prefs.save({ default_activity_type: defaultActivity })}>
					{#each ACTIVITY_TYPES as a}
						<option value={a}>{activityTypeLabel(a)}</option>
					{/each}
				</select>
			</label>
		</div>
	</section>

	<section class="card">
		<h2>{m('prefs.voiceFeedbackHeading')}</h2>
		<div class="form-grid">
			<label class="checkbox-label">
				<input type="checkbox" bind:checked={voiceFeedbackEnabled} onchange={() => prefs.save({ voice_feedback_enabled: voiceFeedbackEnabled })} />
				<span>{m('prefs.spokenSplits')}</span>
			</label>
			{#if voiceFeedbackEnabled}
				<label>
					<span class="label-text">{m('prefs.cueDetail')}</span>
					<select bind:value={voiceFeedbackVerbosity} onchange={() => prefs.save({ voice_feedback_verbosity: voiceFeedbackVerbosity })}>
						<option value="full">{m('prefs.cueDetailFull')}</option>
						<option value="minimal">{m('prefs.cueDetailMinimal')}</option>
					</select>
				</label>
				<label>
					<span class="label-text">{m('prefs.splitInterval', { unit: preferredUnit })}</span>
					<!-- min/max/step are in the displayed unit by design — a 0.5–10
					     range reads as round numbers whether the runner thinks in km
					     or mi (a miles runner gets 0.5–10 mile splits, stored as the
					     equivalent km). -->
					<input
						type="number"
						value={preferredUnit === 'mi'
							? (parseFloat(voiceFeedbackIntervalKm) / KM_PER_MI).toFixed(1)
							: voiceFeedbackIntervalKm}
						oninput={(e) => {
							const n = parseFloat(e.currentTarget.value);
							if (Number.isFinite(n)) {
								voiceFeedbackIntervalKm = (preferredUnit === 'mi' ? n * KM_PER_MI : n).toString();
							}
						}}
						step="0.5"
						min="0.5"
						max="10"
						onblur={() => prefs.save({ voice_feedback_interval_km: parseFloat(voiceFeedbackIntervalKm) || 1.0 })}
					/>
				</label>
				<fieldset class="cue-list" data-testid="voice-cue-types">
					<legend class="label-text">{m('prefs.voiceCueTypes')}</legend>
					<p class="section-hint">{m('prefs.voiceCueTypesHint')}</p>
					{#each VOICE_CUE_IDS as cueId (cueId)}
						<label class="checkbox-row">
							<input
								type="checkbox"
								data-testid="voice-cue-{cueId}"
								checked={isVoiceCueEnabled(voiceCueTypes, cueId)}
								onchange={(e) => toggleVoiceCue(cueId, e.currentTarget.checked)}
							/>
							<span>
								{m(VOICE_CUE_LABELS[cueId].label)}
								<span class="hint">{m(VOICE_CUE_LABELS[cueId].hint)}</span>
							</span>
						</label>
					{/each}
				</fieldset>
			{/if}
		</div>
	</section>
</PrefsPage>

<style>
	.checkbox-label { display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem; padding-top: 1.2rem; }
	.cue-list {
		grid-column: 1 / -1;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-md);
		margin: 0;
		min-inline-size: 0;
	}
	.cue-list .section-hint { margin-bottom: var(--space-xs); font-size: 0.8rem; }
</style>
