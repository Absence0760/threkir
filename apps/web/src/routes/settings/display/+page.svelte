<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { effective } from '$lib/settings/settings';
	import { applyTheme, loadTheme, type Theme } from '$lib/settings/theme';
	import { m, currentLocale, setLocale } from '$lib/i18n/store.svelte';
	import { SUPPORTED_LOCALES, LOCALE_LABELS, type Locale } from '$lib/i18n/locale';
	import { setUnit, setWeightUnit } from '$lib/format/units.svelte';
	import { defaultWeekStartForLocale } from '$lib/format/locale_defaults';
	import { defaultWeightUnitForDistanceUnit } from '$lib/format/weight';
	import { setMapStyle } from '$lib/routes/map-style.svelte';
	import { setUndoWindowS } from '$lib/stores/undo.svelte';
	import { undoWindowSFromPref, DEFAULT_UNDO_WINDOW_S } from '$lib/core/undo_queue';
	import { showToast } from '$lib/stores/toast.svelte';
	import { createPrefsPage } from '$lib/settings/prefs_page.svelte';
	import PrefsPage from '$lib/components/settings/PrefsPage.svelte';

	let preferredUnit = $state<'km' | 'mi'>('km');
	let weightUnit = $state<'kg' | 'lbs'>('kg');
	let paceFormat = $state<'min_per_km' | 'min_per_mi' | 'kph' | 'mph'>('min_per_km');
	let weekStartDay = $state<'monday' | 'sunday'>('monday');
	let mapStyle = $state<'streets' | 'satellite' | 'outdoors' | 'dark'>('streets');
	// WCAG 2.2.1 "Turn off": the 0 choice removes the undo window's time
	// limit entirely, so reaching Undo never means beating a countdown.
	let undoWindowS = $state<number>(DEFAULT_UNDO_WINDOW_S);
	let showCalories = $state(true);

	// Theme is per-browser (localStorage), not the cross-device bag: a dark
	// laptop beside a light tablet is a common setup a synced value would fight.
	let theme = $state<Theme>('auto');

	// Language is per-browser like theme. The applied tag is mirrored into the
	// universal bag (`locale`) only so the server can localise email
	// (decisions § 120); it is never read back to drive the UI.
	let language = $state<Locale>('en');

	const prefs = createPrefsPage(async ({ settings, preferredUnit: unit }) => {
		preferredUnit = unit;
		setUnit(unit);
		// Unset weight_unit follows the distance unit (lbs for imperial) rather
		// than a hard-coded kg — matches +layout + onboarding (issue #488).
		const storedWeightUnit = effective<string>(settings, 'weight_unit');
		weightUnit =
			storedWeightUnit === 'lbs' || storedWeightUnit === 'kg'
				? storedWeightUnit
				: defaultWeightUnitForDistanceUnit(unit);
		setWeightUnit(weightUnit);
		paceFormat = effective(settings, 'units_pace_format', 'min_per_km') ?? 'min_per_km';
		// A new account has no stored week_start_day, so the locale convention
		// decides (Sunday-first for US/CA, Monday for ISO) rather than Monday.
		weekStartDay =
			effective(settings, 'week_start_day', defaultWeekStartForLocale(navigator.language)) ??
			'monday';
		mapStyle = effective(settings, 'map_style', 'streets') ?? 'streets';
		setMapStyle(mapStyle);
		undoWindowS = undoWindowSFromPref(effective<number>(settings, 'undo_window_s'));
		setUndoWindowS(undoWindowS);
		showCalories = effective<boolean>(settings, 'show_calories', true) !== false;
	});

	onMount(() => {
		theme = loadTheme();
		language = currentLocale();
	});

	function changeTheme(next: Theme) {
		theme = next;
		applyTheme(next);
	}

	async function changeLanguage(next: Locale) {
		await setLocale(next);
		// Reflect the locale that actually applied: if its chunk failed to
		// load, setLocale keeps the current one and the select snaps back.
		language = currentLocale();
		if (auth.user) prefs.save({ locale: language });
	}

	// Picking a distance unit snaps a min-per-unit pace format to match (a
	// speed format is a deliberate choice and is left alone), flips the
	// app-wide signal, and dual-writes the profile column the leaderboard RPCs
	// read. The column write is awaited so the "Saved" cue, and a reload after
	// it, reflect the change deterministically.
	async function pickDistanceUnit(next: 'km' | 'mi') {
		preferredUnit = next;
		if (paceFormat !== 'kph' && paceFormat !== 'mph') {
			paceFormat = next === 'mi' ? 'min_per_mi' : 'min_per_km';
		}
		setUnit(next);
		if (auth.user) {
			prefs.status = 'saving';
			try {
				const { error } = await supabase
					.from('user_profiles')
					.update({ preferred_unit: next })
					.eq('id', auth.user.id);
				if (error) throw error;
			} catch (e) {
				prefs.status = 'idle';
				showToast(m('prefs.saveFailed', { error: (e as Error).message }), 'error');
				return;
			}
		}
		prefs.save({ preferred_unit: next, units_pace_format: paceFormat });
	}

	// Weight unit is display + entry only; storage stays canonical kg.
	function pickWeightUnit(next: 'kg' | 'lbs') {
		weightUnit = next;
		setWeightUnit(next);
		prefs.save({ weight_unit: next });
	}
</script>

<PrefsPage heading={m('prefs.unitsDisplayHeading')} tagline={m('prefs.displayTagline')} page={prefs}>
	<section class="card">
		<h2>{m('prefs.languageThemeHeading')}</h2>
		<div class="form-grid">
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.language')}</span>
					<select
						value={language}
						onchange={(e) => changeLanguage(e.currentTarget.value as Locale)}
						aria-describedby="language-hint"
						data-testid="language-select"
					>
						{#each SUPPORTED_LOCALES as loc}
							<option value={loc}>{LOCALE_LABELS[loc]}</option>
						{/each}
					</select>
				</label>
				<p class="hint" id="language-hint">{m('prefs.languageHint')}</p>
			</div>
			<div class="field">
				<span class="label-text">{m('prefs.theme')}</span>
				<div class="toggle-row" role="group" aria-label={m('prefs.theme')} aria-describedby="theme-hint">
					<button class="toggle-btn" class:active={theme === 'auto'} onclick={() => changeTheme('auto')} type="button">{m('prefs.themeAuto')}</button>
					<button class="toggle-btn" class:active={theme === 'light'} onclick={() => changeTheme('light')} type="button">{m('prefs.themeLight')}</button>
					<button class="toggle-btn" class:active={theme === 'dark'} onclick={() => changeTheme('dark')} type="button">{m('prefs.themeDark')}</button>
				</div>
				<p class="hint" id="theme-hint">{m('prefs.themeHint')}</p>
			</div>
		</div>
	</section>

	<section class="card">
		<h2>{m('prefs.unitsHeading')}</h2>
		<div class="form-grid">
			<div class="field">
				<span class="label-text">{m('prefs.distanceUnit')}</span>
				<div class="toggle-row" role="group" aria-label={m('prefs.distanceUnit')} aria-describedby="distance-unit-hint">
					<button class="toggle-btn" class:active={preferredUnit === 'km'} onclick={() => pickDistanceUnit('km')} type="button">{m('prefs.kilometres')}</button>
					<button class="toggle-btn" class:active={preferredUnit === 'mi'} onclick={() => pickDistanceUnit('mi')} type="button">{m('prefs.miles')}</button>
				</div>
				<p class="hint" id="distance-unit-hint">{m('prefs.distanceUnitHint')}</p>
			</div>
			<div class="field">
				<span class="label-text">{m('prefs.weightUnit')}</span>
				<div class="toggle-row" role="group" aria-label={m('prefs.weightUnit')} aria-describedby="weight-unit-hint">
					<button class="toggle-btn" class:active={weightUnit === 'kg'} onclick={() => pickWeightUnit('kg')} type="button">{m('prefs.kilograms')}</button>
					<button class="toggle-btn" class:active={weightUnit === 'lbs'} onclick={() => pickWeightUnit('lbs')} type="button">{m('prefs.pounds')}</button>
				</div>
				<p class="hint" id="weight-unit-hint">{m('prefs.weightUnitHint')}</p>
			</div>
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.paceFormat')}</span>
					<select bind:value={paceFormat} onchange={() => prefs.save({ units_pace_format: paceFormat })} aria-describedby="pace-format-hint">
						<option value="min_per_km">min/km</option>
						<option value="min_per_mi">min/mi</option>
						<option value="kph">km/h</option>
						<option value="mph">mph</option>
					</select>
				</label>
				<p class="hint" id="pace-format-hint">{m('prefs.paceFormatHint')}</p>
			</div>
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.weekStartsOn')}</span>
					<select bind:value={weekStartDay} onchange={() => prefs.save({ week_start_day: weekStartDay })} aria-describedby="week-start-hint">
						<option value="monday">{m('prefs.monday')}</option>
						<option value="sunday">{m('prefs.sunday')}</option>
					</select>
				</label>
				<p class="hint" id="week-start-hint">{m('prefs.weekStartsOnHint')}</p>
			</div>
		</div>
	</section>

	<section class="card">
		<h2>{m('prefs.mapsPagesHeading')}</h2>
		<div class="form-grid">
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.mapStyle')}</span>
					<select
						bind:value={mapStyle}
						aria-describedby="map-style-hint"
						onchange={() => {
							setMapStyle(mapStyle);
							prefs.save({ map_style: mapStyle });
						}}
					>
						<option value="streets">{m('prefs.mapStyleStreets')}</option>
						<option value="satellite">{m('prefs.mapStyleSatellite')}</option>
						<option value="outdoors">{m('prefs.mapStyleOutdoors')}</option>
						<option value="dark">{m('prefs.mapStyleDark')}</option>
					</select>
				</label>
				<p class="hint" id="map-style-hint">{m('prefs.mapStyleHint')}</p>
			</div>
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.undoWindow')}</span>
					<select
						bind:value={undoWindowS}
						data-testid="undo-window-select"
						aria-describedby="undo-window-hint"
						onchange={() => {
							setUndoWindowS(undoWindowS);
							prefs.save({ undo_window_s: undoWindowS });
						}}
					>
						<option value={8}>{m('prefs.undoWindow8s')}</option>
						<option value={30}>{m('prefs.undoWindow30s')}</option>
						<option value={0}>{m('prefs.undoWindowManual')}</option>
					</select>
				</label>
				<p class="hint" id="undo-window-hint">{m('prefs.undoWindowHelp')}</p>
			</div>
		</div>
		<label class="checkbox-row">
			<input type="checkbox" bind:checked={showCalories} onchange={() => prefs.save({ show_calories: showCalories })} />
			<span>
				{m('prefs.showCalories')}
				<span class="hint">{m('prefs.showCaloriesHint')}</span>
			</span>
		</label>
	</section>
</PrefsPage>
