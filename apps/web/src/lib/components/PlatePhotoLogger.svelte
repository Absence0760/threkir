<script lang="ts">
	import { createFoodEntry } from '#lib/core/data.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { entryTimestampFor } from '#lib/nutrition/diary_day.ts';
	import { MEAL_SLOTS, type MealSlot } from '#lib/nutrition/nutrition_totals.ts';
	import {
		PlatePhotoError,
		requestPlateEstimate,
		type PlateItem,
	} from '#lib/nutrition/plate_photo_client.ts';
	import { MAX_ITEM_NAME_CHARS, PLATE_ITEM_LIMITS } from '#lib/nutrition/plate_photo/estimate.ts';
	import { MAX_PLATE_NOTE_CHARS, type PlatePhotoErrorKind } from '#lib/nutrition/plate_photo/upload.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';

	interface Props {
		oncreated: () => void;
		diaryDate?: string;
	}
	let { oncreated, diaryDate }: Props = $props();

	// Review rows are plain strings bound to inputs, so an emptied field stays
	// empty (null on save) rather than snapping back to a model number.
	interface Draft {
		key: number;
		item_name: string;
		calories: string;
		protein_g: string;
		carbs_g: string;
		fat_g: string;
		lowConfidence: boolean;
		// The nutrients the review row does not show ride along unedited.
		rest: Pick<PlateItem, 'fiber_g' | 'sugar_g' | 'saturated_fat_g' | 'sodium_mg' | 'cholesterol_mg'>;
	}

	let file = $state<File | null>(null);
	let note = $state('');
	let estimating = $state(false);
	let saving = $state(false);
	let drafts = $state<Draft[] | null>(null);
	let mealSlot = $state<MealSlot>('lunch');
	let error = $state<PlatePhotoErrorKind | null>(null);
	let saveError = $state<string | null>(null);
	let fileInput = $state<HTMLInputElement | null>(null);
	let seq = 0;

	const ERROR_KEYS: Record<PlatePhotoErrorKind, MessageKey> = {
		not_authenticated: 'nutrition.platePhotoErrorUnavailable',
		consent: 'nutrition.platePhotoErrorConsent',
		pro_required: 'nutrition.platePhotoErrorPro',
		rate_limited: 'nutrition.platePhotoErrorRate',
		invalid: 'nutrition.platePhotoErrorInvalid',
		not_understood: 'nutrition.platePhotoErrorNotUnderstood',
		unavailable: 'nutrition.platePhotoErrorUnavailable',
	};

	const num = (v: number | null) => (v == null ? '' : String(v));

	function toDraft(item: PlateItem): Draft {
		return {
			key: ++seq,
			item_name: item.item_name,
			calories: num(item.calories),
			protein_g: num(item.protein_g),
			carbs_g: num(item.carbs_g),
			fat_g: num(item.fat_g),
			lowConfidence: item.confidence === 'low',
			rest: {
				fiber_g: item.fiber_g,
				sugar_g: item.sugar_g,
				saturated_fat_g: item.saturated_fat_g,
				sodium_mg: item.sodium_mg,
				cholesterol_mg: item.cholesterol_mg,
			},
		};
	}

	/// The same bound the server applies, so an edit cannot save what the
	/// estimate itself could not have proposed.
	function parseField(raw: string, max: number): number | null {
		const t = raw.trim();
		if (t === '') return null;
		const v = Number(t);
		if (!Number.isFinite(v) || v < 0) return null;
		return Math.min(v, max);
	}

	function onPick(e: Event) {
		const picked = (e.currentTarget as HTMLInputElement).files?.[0] ?? null;
		file = picked;
		drafts = null;
		error = null;
		saveError = null;
	}

	async function estimate() {
		if (!file || estimating) return;
		estimating = true;
		error = null;
		saveError = null;
		try {
			const result = await requestPlateEstimate(file, note.trim());
			drafts = result.items.map(toDraft);
			if (result.meal_slot) mealSlot = result.meal_slot;
		} catch (e) {
			error = e instanceof PlatePhotoError ? e.kind : 'unavailable';
			if (!(e instanceof PlatePhotoError)) console.error('plate photo failed', thrownMessage(e));
		} finally {
			estimating = false;
		}
	}

	function removeDraft(key: number) {
		drafts = (drafts ?? []).filter((d) => d.key !== key);
	}

	function discard() {
		drafts = null;
		file = null;
		note = '';
		saveError = null;
		if (fileInput) fileInput.value = '';
	}

	let saveable = $derived((drafts ?? []).filter((d) => d.item_name.trim().length > 0));

	async function save() {
		if (saving || saveable.length === 0) return;
		saving = true;
		saveError = null;
		const startedAt = diaryDate ? entryTimestampFor(diaryDate, new Date()) : undefined;
		const pending = [...saveable];
		let saved = 0;
		try {
			// One row per kept item, in order. A failure part-way stops and
			// leaves the unsaved rows on screen, so nothing is logged twice.
			for (const d of pending) {
				await createFoodEntry({
					item_name: d.item_name.trim().slice(0, MAX_ITEM_NAME_CHARS),
					meal_slot: mealSlot,
					calories: parseField(d.calories, PLATE_ITEM_LIMITS.calories.max),
					protein_g: parseField(d.protein_g, PLATE_ITEM_LIMITS.protein_g.max),
					carbs_g: parseField(d.carbs_g, PLATE_ITEM_LIMITS.carbs_g.max),
					fat_g: parseField(d.fat_g, PLATE_ITEM_LIMITS.fat_g.max),
					...d.rest,
					started_at: startedAt,
				});
				saved += 1;
				drafts = (drafts ?? []).filter((x) => x.key !== d.key);
			}
			discard();
			oncreated();
		} catch (e) {
			saveError = m('nutrition.platePhotoSavePartial', {
				saved,
				total: pending.length,
				error: thrownMessage(e),
			});
		} finally {
			saving = false;
		}
	}
</script>

<section class="card plate-photo" aria-labelledby="plate-photo-heading" data-testid="plate-photo">
	<div class="head">
		<h2 id="plate-photo-heading">{m('nutrition.platePhotoHeading')}</h2>
		<span class="pro-badge">{m('nutrition.platePhotoProBadge')}</span>
	</div>
	<p class="intro">{m('nutrition.platePhotoIntro')}</p>

	{#if drafts === null}
		<div class="pick">
			<input
				bind:this={fileInput}
				type="file"
				accept="image/jpeg,image/png,image/webp"
				hidden
				onchange={onPick}
				data-testid="plate-photo-file"
			/>
			<button class="btn btn-outline file-btn" type="button" onclick={() => fileInput?.click()}>
				<span class="material-symbols" aria-hidden="true">photo_camera</span>
				<span class="file-name">{file ? file.name : m('nutrition.platePhotoChoose')}</span>
			</button>
			<label class="note">
				<span class="label-text">{m('nutrition.platePhotoNoteLabel')}</span>
				<input
					type="text"
					bind:value={note}
					maxlength={MAX_PLATE_NOTE_CHARS}
					placeholder={m('nutrition.platePhotoNotePlaceholder')}
				/>
			</label>
			<button
				class="btn btn-primary"
				type="button"
				disabled={!file || estimating}
				onclick={estimate}
				data-testid="plate-photo-estimate"
			>
				{estimating ? m('nutrition.platePhotoEstimating') : m('nutrition.platePhotoEstimate')}
			</button>
		</div>
	{:else if drafts.length === 0}
		<p class="empty" role="status">{m('nutrition.platePhotoEmpty')}</p>
		<button class="btn btn-outline btn-sm" type="button" onclick={discard}>{m('nutrition.platePhotoDiscard')}</button>
	{:else}
		<div class="review" data-testid="plate-photo-review">
			<h3>{m('nutrition.platePhotoReviewHeading')}</h3>
			<p class="hint">{m('nutrition.platePhotoReviewHint')}</p>
			<label class="slot">
				<span class="label-text">{m('nutrition.platePhotoMealSlot')}</span>
				<select bind:value={mealSlot} data-testid="plate-photo-slot">
					{#each MEAL_SLOTS as s (s)}
						<option value={s}>{m(`nutrition.slot_${s}`)}</option>
					{/each}
				</select>
			</label>
			<ul class="items">
				{#each drafts as d (d.key)}
					<li class="item" data-testid="plate-photo-item">
						<div class="item-head">
							<label class="name">
								<span class="sr-only">{m('nutrition.platePhotoItemName')}</span>
								<input type="text" bind:value={d.item_name} maxlength={MAX_ITEM_NAME_CHARS} />
							</label>
							<button
								class="icon-btn"
								type="button"
								aria-label={m('nutrition.platePhotoRemoveItem', { name: d.item_name })}
								onclick={() => removeDraft(d.key)}
							>
								<span class="material-symbols" aria-hidden="true">close</span>
							</button>
						</div>
						{#if d.lowConfidence}<span class="low">{m('nutrition.platePhotoConfidenceLow')}</span>{/if}
						<div class="macros">
							<label><span>{m('nutrition.platePhotoCalories')}</span><input type="number" inputmode="decimal" min="0" bind:value={d.calories} /></label>
							<label><span>{m('nutrition.platePhotoProtein')}</span><input type="number" inputmode="decimal" min="0" bind:value={d.protein_g} /></label>
							<label><span>{m('nutrition.platePhotoCarbs')}</span><input type="number" inputmode="decimal" min="0" bind:value={d.carbs_g} /></label>
							<label><span>{m('nutrition.platePhotoFat')}</span><input type="number" inputmode="decimal" min="0" bind:value={d.fat_g} /></label>
						</div>
					</li>
				{/each}
			</ul>
			<div class="actions">
				<button class="btn btn-outline" type="button" onclick={discard} disabled={saving}>
					{m('nutrition.platePhotoDiscard')}
				</button>
				<button
					class="btn btn-primary"
					type="button"
					onclick={save}
					disabled={saving || saveable.length === 0}
					data-testid="plate-photo-save"
				>
					{saving ? m('nutrition.platePhotoSaving') : m('nutrition.platePhotoSave', { n: saveable.length })}
				</button>
			</div>
		</div>
	{/if}

	{#if error}
		<p class="error" role="alert" data-testid="plate-photo-error">
			{m(ERROR_KEYS[error])}
			{#if error === 'consent'}<a href="/coach">{m('nutrition.platePhotoErrorConsentLink')}</a>{/if}
			{#if error === 'pro_required'}<a href="/settings/upgrade">{m('nutrition.platePhotoErrorProLink')}</a>{/if}
		</p>
	{/if}
	{#if saveError}<p class="error" role="alert">{saveError}</p>{/if}
</section>

<style>
	.plate-photo {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.head {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.head h2 {
		margin: 0;
		font-size: 1.1rem;
	}
	.pro-badge {
		font-size: 0.72rem;
		font-weight: 700;
		padding: 0.1rem 0.45rem;
		border-radius: 9999px;
		background: color-mix(in srgb, var(--color-primary) 14%, transparent);
		color: var(--color-primary);
	}
	.intro,
	.hint {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.pick {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.file-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		align-self: flex-start;
		max-width: 100%;
	}
	.file-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.note,
	.slot {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.pick .btn {
		align-self: flex-start;
	}
	.review h3 {
		margin: 0;
		font-size: 1rem;
	}
	.items {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.item {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.item-head {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.name {
		flex: 1;
		min-width: 0;
	}
	.name input {
		width: 100%;
	}
	.low {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.macros {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(6.5rem, 1fr));
		gap: var(--space-xs);
	}
	.macros label {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.macros input {
		width: 100%;
	}
	.icon-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: var(--tap-target-min);
		min-height: var(--tap-target-min);
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.empty {
		margin: 0;
	}
	.error {
		margin: 0;
		color: var(--color-danger-text);
		font-size: 0.9rem;
	}
	.error a {
		margin-inline-start: 0.35rem;
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
	}
</style>
