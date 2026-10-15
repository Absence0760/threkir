<script lang="ts">
	import { untrack } from 'svelte';
	import {
		createNutritionPlan,
		updateNutritionPlan,
		type NutritionPlanInput,
	} from '#lib/core/data.ts';
	import { appErrorMessage } from '#lib/core/supabase_error.ts';
	import { lengthLimit, valueLimit, withinValueLimit } from '#lib/core/column_limits.ts';
	import { trackDirty } from '#lib/core/form_dirty.ts';
	import { floatOrNull } from '#lib/gym/numeric_input.ts';
	import { GOAL_PHASES, type PlanDraft } from '#lib/nutrition/meal_plan.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { NutritionGoalPhase, NutritionPlan } from '#lib/types.ts';
	import UnsavedChangesGuard from './UnsavedChangesGuard.svelte';

	interface Props {
		/// The plan being edited; absent for a new plan.
		plan?: NutritionPlan | null;
		/// Starting numbers for a new plan ("Save as plan" from the day view).
		seed?: PlanDraft | null;
		/// Offer "follow from today" on a new plan.
		offerFollow?: boolean;
		onsaved: (plan: NutritionPlan, follow: boolean) => void;
		oncancel: () => void;
	}

	let { plan = null, seed = null, offerFollow = false, onsaved, oncancel }: Props = $props();
	const uid = $props.id();

	type NumberField = string | number | null;

	const kcalBounds = valueLimit('nutrition_plans.target_calories');
	const gramBounds = valueLimit('nutrition_plans.target_protein_g');
	const titleMax = lengthLimit('nutrition_plans.title');
	const notesMax = lengthLimit('nutrition_plans.notes');

	const initial = untrack(() => plan);
	const draft = untrack(() => seed);
	let title = $state(initial?.title ?? '');
	let notes = $state(initial?.notes ?? '');
	let goalPhase = $state<NutritionGoalPhase>(initial?.goal_phase ?? draft?.goalPhase ?? 'maintain');
	let calories = $state<NumberField>(initial?.target_calories ?? draft?.targetCalories ?? null);
	let protein = $state<NumberField>(initial ? initial.target_protein_g : (draft?.targetProteinG ?? null));
	let carbs = $state<NumberField>(initial ? initial.target_carbs_g : (draft?.targetCarbsG ?? null));
	let fat = $state<NumberField>(initial ? initial.target_fat_g : (draft?.targetFatG ?? null));
	let trainingCalories = $state<NumberField>(initial?.training_calories ?? null);
	let trainingCarbs = $state<NumberField>(initial?.training_carbs_g ?? null);
	let follow = $state(untrack(() => offerFollow));
	let saving = $state(false);
	let error = $state('');

	const dirty = trackDirty(() => ({
		title,
		notes,
		goalPhase,
		calories,
		protein,
		carbs,
		fat,
		trainingCalories,
		trainingCarbs,
	}));

	type Parsed = { ok: true; value: number | null } | { ok: false };

	function parseGrams(v: NumberField): Parsed {
		const n = floatOrNull(v ?? '');
		if (n === null) return { ok: true, value: null };
		return withinValueLimit('nutrition_plans.target_protein_g', n) ? { ok: true, value: n } : { ok: false };
	}

	function parseKcal(v: NumberField, required: boolean): Parsed {
		const n = floatOrNull(v ?? '');
		if (n === null) return required ? { ok: false } : { ok: true, value: null };
		return withinValueLimit('nutrition_plans.target_calories', n) ? { ok: true, value: n } : { ok: false };
	}

	async function save() {
		if (saving) return;
		if (title.trim().length === 0) {
			error = m('nutrition.plan.titleRequired');
			return;
		}
		const kcal = parseKcal(calories, true);
		const trainKcal = parseKcal(trainingCalories, false);
		if (!kcal.ok || !trainKcal.ok || kcal.value === null) {
			error = m('nutrition.plan.caloriesRange', { min: kcalBounds.min, max: kcalBounds.max });
			return;
		}
		const grams = [protein, carbs, fat, trainingCarbs].map(parseGrams);
		if (grams.some((g) => !g.ok)) {
			error = m('nutrition.plan.gramsRange', { min: gramBounds.min, max: gramBounds.max });
			return;
		}
		const [p, c, f, tc] = grams.map((g) => (g.ok ? g.value : null));
		const input: NutritionPlanInput = {
			title: title.trim(),
			notes: notes.trim().length > 0 ? notes.trim() : null,
			goal_phase: goalPhase,
			target_calories: kcal.value,
			target_protein_g: p,
			target_carbs_g: c,
			target_fat_g: f,
			training_calories: trainKcal.value,
			training_carbs_g: tc,
		};
		error = '';
		saving = true;
		try {
			const saved = initial ? await updateNutritionPlan(initial.id, input) : await createNutritionPlan(input);
			dirty.rebaseline();
			onsaved(saved, !initial && follow);
		} catch (e) {
			console.error('meal plan save failed', e);
			error = appErrorMessage(e) ?? m('nutrition.plan.saveFailed');
		} finally {
			saving = false;
		}
	}
</script>

<UnsavedChangesGuard isDirty={dirty.isDirty} />

<form
	class="editor-form meal-plan-editor"
	onsubmit={(e) => {
		e.preventDefault();
		void save();
	}}
	novalidate
>
	<div class="field">
		<label>
			<span>{m('nutrition.plan.titleLabel')}</span>
			<input
				type="text"
				bind:value={title}
				maxlength={titleMax}
				placeholder={m('nutrition.plan.titlePlaceholder')}
				data-testid="plan-title"
				aria-describedby="{uid}-title-hint"
			/>
		</label>
		<span class="field-hint" id="{uid}-title-hint">{m('nutrition.plan.titleHint')}</span>
	</div>

	<div class="field">
		<label>
			<span>{m('nutrition.plan.goalPhase')}</span>
			<select bind:value={goalPhase} data-testid="plan-goal-phase" aria-describedby="{uid}-phase-hint">
				{#each GOAL_PHASES as phase (phase)}
					<option value={phase}>{m(`nutrition.plan.phase_${phase}`)}</option>
				{/each}
			</select>
		</label>
		<span class="field-hint" id="{uid}-phase-hint">{m('nutrition.plan.goalPhaseHint')}</span>
	</div>

	<fieldset>
		<legend>{m('nutrition.plan.everyDayHeading')}</legend>
		<div class="field">
			<label>
				<span>{m('nutrition.plan.caloriesLabel')}</span>
				<input
					type="number"
					inputmode="numeric"
					min={kcalBounds.min}
					max={kcalBounds.max}
					step="1"
					bind:value={calories}
					data-testid="plan-calories"
					aria-describedby="{uid}-kcal-hint"
				/>
			</label>
			<span class="field-hint" id="{uid}-kcal-hint">{m('nutrition.plan.caloriesHint')}</span>
		</div>
		<div class="macro-grid">
			<label>
				<span>{m('nutrition.plan.proteinLabel')}</span>
				<input type="number" inputmode="numeric" min={gramBounds.min} max={gramBounds.max} step="1" bind:value={protein} data-testid="plan-protein" aria-describedby="{uid}-macro-hint" />
			</label>
			<label>
				<span>{m('nutrition.plan.carbsLabel')}</span>
				<input type="number" inputmode="numeric" min={gramBounds.min} max={gramBounds.max} step="1" bind:value={carbs} data-testid="plan-carbs" aria-describedby="{uid}-macro-hint" />
			</label>
			<label>
				<span>{m('nutrition.plan.fatLabel')}</span>
				<input type="number" inputmode="numeric" min={gramBounds.min} max={gramBounds.max} step="1" bind:value={fat} data-testid="plan-fat" aria-describedby="{uid}-macro-hint" />
			</label>
		</div>
		<span class="field-hint" id="{uid}-macro-hint">{m('nutrition.plan.macrosHint')}</span>
	</fieldset>

	<fieldset>
		<legend>{m('nutrition.plan.trainingHeading')}</legend>
		<div class="macro-grid">
			<label>
				<span>{m('nutrition.plan.trainingCaloriesLabel')}</span>
				<input type="number" inputmode="numeric" min={kcalBounds.min} max={kcalBounds.max} step="1" bind:value={trainingCalories} data-testid="plan-training-calories" aria-describedby="{uid}-training-hint" />
			</label>
			<label>
				<span>{m('nutrition.plan.trainingCarbsLabel')}</span>
				<input type="number" inputmode="numeric" min={gramBounds.min} max={gramBounds.max} step="1" bind:value={trainingCarbs} data-testid="plan-training-carbs" aria-describedby="{uid}-training-hint" />
			</label>
		</div>
		<span class="field-hint" id="{uid}-training-hint">{m('nutrition.plan.trainingHint')}</span>
	</fieldset>

	<label>
		<span>{m('nutrition.plan.notesLabel')}</span>
		<textarea rows="2" maxlength={notesMax} bind:value={notes}></textarea>
	</label>

	{#if !initial && offerFollow}
		<label class="toggle-row">
			<input type="checkbox" bind:checked={follow} data-testid="plan-follow-today" />
			<span>
				<strong>{m('nutrition.plan.followToday')}</strong>
				<span class="hint">{m('nutrition.plan.followTodayHint')}</span>
			</span>
		</label>
	{/if}

	{#if error}
		<p class="error" role="alert" data-testid="plan-error">{error}</p>
	{/if}

	<div class="actions">
		<button class="btn btn-outline" type="button" onclick={oncancel} disabled={saving}>{m('nutrition.cancel')}</button>
		<button class="btn btn-primary" type="submit" disabled={saving} data-testid="plan-save">{m('nutrition.plan.save')}</button>
	</div>
</form>

<style>
	.macro-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr));
		gap: var(--space-sm);
	}
</style>
