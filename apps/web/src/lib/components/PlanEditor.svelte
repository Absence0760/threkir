<script lang="ts">
	import { AI_CONSENT_HREF } from '#lib/core/ai_disclosure.ts';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { lengthLimit } from '#lib/core/column_limits.ts';
	import { onMount, untrack } from 'svelte';
	import { replaceState } from '$app/navigation';
	import { page } from '$app/state';
	import {
		createTrainingPlan,
		fetchMyOverlappingActivePlans,
		fetchRuns,
		type PlanOverlapChoice,
	} from '#lib/core/data.ts';
	import PlanOverlapDialog, { trimBlockedMessage } from '#lib/components/PlanOverlapDialog.svelte';
	import { attemptPlanCreate, type OverlapPlan } from '#lib/training/plan_overlap.ts';
	import MetricLabel from '#lib/components/MetricLabel.svelte';
	import {
		GOAL_DISTANCES_M,
		ULTRA_PRESETS,
		defaultPlanWeeks,
		isUltraDistance,
		walkRunDefaultWeeks,
		generatePlan,
		formatISO,
		parseISO,
		type UltraPresetId,
	} from '#lib/training/training.ts';
	import { RACE_GOAL_MAX_HOURS } from '#lib/training/plan_races.ts';
	import { workoutKindLabel, planPhaseLabel } from '#lib/training/workout_labels.ts';
	import type {
		GoalEvent,
		GeneratedPlan,
		WorkoutKind,
		TrainingGender,
	} from '#lib/training/training.ts';
	import { isSundayIso, nextSundayIso } from '#lib/training/plan_start.ts';
	import {
		CHRONIC_WINDOW_WEEKS,
		openingWeekVolumeM,
		peakWeekVolumeM,
		planRampCheck,
		recentRunVolume,
		shouldSurfaceRampNote,
		type RecentVolume,
	} from '#lib/training/plan_ramp.ts';
	import { parsePlanMarkdown, parsePlanJson } from '#lib/training/plan_serialize.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { ageFromDob } from '#lib/nutrition/nutrition_targets.ts';
	import { healthUseDob } from '#lib/core/health_consent.ts';
	import { supabase } from '#lib/core/supabase.ts';
	import { fmtKm, fmtPace, getUnit } from '#lib/format/units.svelte.ts';
	import { paceMinutesSeconds } from '#lib/format/pace_format.ts';
	import { m as t } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import { coachEnabled } from '#lib/coach/coach_flag.ts';
	import { aiPlanEnabled } from '#lib/training/ai_plan_flag.ts';
	import {
		PlanRequestError,
		requestPlanInputs,
		type PlanRequestAssumption,
		type PlanRequestInputs,
	} from '#lib/training/plan_request_client.ts';
	import { racePlanPreset, type RacePlanRefusal } from '#lib/training/race_plan_preset.ts';

	// Persona-hunt Round 3 finding Woman #3. Pull the runner's gender
	// off user_profiles so generatePlan can apply the gender-aware
	// pace calibration when available. We don't ask in the wizard
	// (the runner already set it in Settings → Preferences alongside
	// the segments-leaderboard demographics). null → unmodified
	// (male-curve) paces, matching pre-fix behaviour.
	let viewerGender = $state<TrainingGender>(null);
	// Persona-hunt finding Older #30. Age drives the masters recovery
	// calibration in generatePlan — wider hard-day spacing + a 3-week
	// build/recover cycle for 50+. Like gender, it's read off the profile
	// rather than asked in the wizard. null → the standard
	// (younger-physiology) schedule. Reshaping the plan around the runner's
	// age is an Art 9 health inference, so the date comes through
	// `healthUseDob` rather than off the age record directly (§ 722).
	let viewerAge = $state<number | null>(null);
	// The runner's chronic weekly volume, so the preview can say whether the
	// plan's opening week is a step the runner's current training supports.
	// Null until loaded (and on failure) — the note self-hides rather than
	// grading against a base it doesn't have.
	let recentVolume = $state<RecentVolume | null>(null);
	onMount(async () => {
		if (!auth.user) return;
		// Self-read via get_my_profile(): gender / the age record / the consent
		// stamp are all deny-by-default for direct authenticated SELECTs
		// (column lockdown, 20260707_001), and the RPC returns the whole row so
		// the stamp arrives with the date.
		const { data } = await supabase.rpc('get_my_profile', undefined, { get: true }).maybeSingle();
		const g = (data as { gender?: string | null } | null)?.gender;
		if (g === 'male' || g === 'female' || g === 'prefer_not_to_say') viewerGender = g;
		// Parse by calendar components — new Date('YYYY-MM-DD') is UTC midnight,
		// and reading it back through local getters shifts the birthday a day
		// early in negative-UTC offsets, misfiring the masters (50) gate.
		const age = ageFromDob(healthUseDob(data), Date.now());
		if (age !== null) viewerAge = age;
	});

	// Its own mount effect, and its own catch: the volume read is an advisory
	// layer over the wizard, so neither a profile failure above nor a failure
	// here may take the other — or the plan preview — down with it.
	onMount(async () => {
		if (!auth.user) return;
		try {
			const fromIso = new Date(
				Date.now() - CHRONIC_WINDOW_WEEKS * 7 * 86_400_000,
			).toISOString();
			const runs = await fetchRuns({
				columns: ['started_at', 'distance_m', 'activity_type'] as const,
				startedAtFrom: fromIso,
			});
			recentVolume = recentRunVolume(runs, Date.now());
		} catch (e) {
			console.error('Recent-volume read for the plan ramp note failed', e);
		}
	});

	const METRES_PER_MILE = 1609.344;
	let distanceUnit = $derived(getUnit());
	let distancePerUnit = $derived(distanceUnit === 'mi' ? METRES_PER_MILE : 1000);
	let distanceStep = $derived(distanceUnit === 'mi' ? '0.1' : '0.5');

	function metresToDistanceInput(metres: number | null | undefined): string {
		if (metres == null) return '';
		return String(Math.round((metres / distancePerUnit) * 10) / 10);
	}
	function distanceInputToMetres(raw: string): number | null {
		if (raw === '') return null;
		const num = parseFloat(raw);
		if (Number.isNaN(num)) return null;
		return Math.max(0, num * distancePerUnit);
	}

	interface Props {
		oncreated?: (plan: { id: string }) => void;
		oncancel?: () => void;
		// Preselect the goal + beginner toggle on mount (the onboarding
		// "create my training plan" deep-link keys these off primary_goal).
		// Absent → the normal defaults below.
		initialGoalEvent?: GoalEvent;
		/// An ultra goal distance (past the marathon) to preselect, as the race
		/// calendar hands one over. Ignored for any other distance.
		initialGoalDistanceM?: number | null;
		initialBeginnerWalkRun?: boolean;
		// Preset the schedule so the plan's race week lands on a known race
		// day (the race-calendar "train for this race" deep-link). The start
		// date is already Sunday-aligned by `racePlanPreset`; it still goes
		// through the same snap on change as a hand-typed one.
		initialName?: string;
		initialStartDate?: string;
		initialWeeks?: number;
		// A plain-English plan description handed over by a deep link (the
		// coach's plan handoff). With the assistant live it prefills the box
		// and runs one fill on mount; with it off it is ignored.
		initialDescription?: string;
	}
	let {
		oncreated,
		oncancel,
		initialGoalEvent,
		initialGoalDistanceM,
		initialBeginnerWalkRun,
		initialName,
		initialStartDate,
		initialWeeks,
		initialDescription,
	}: Props = $props();

	// The initial* props seed the form once; the fields are edited locally after.
	let name = $state(untrack(() => initialName ?? ''));
	// An ultra goal is stored as `custom` plus its distance — the distance
	// is what the generator plans from — and `ultraChoice` remembers which
	// wizard entry the runner picked, so the select can show it.
	type UltraChoice = UltraPresetId | 'ultra_other';
	const initialUltra = untrack(() =>
		initialGoalDistanceM != null && isUltraDistance(initialGoalDistanceM) ? initialGoalDistanceM : null,
	);
	let ultraChoice = $state<UltraChoice | null>(
		initialUltra == null ? null : (ultraPresetFor(initialUltra) ?? 'ultra_other'),
	);
	let ultraDistanceM = $state<number | null>(initialUltra);
	let goalEvent = $state<GoalEvent>(
		untrack(() => (initialUltra != null ? 'custom' : (initialGoalEvent ?? 'distance_half'))),
	);

	/// The preset a distance is, to the metre, or null.
	function ultraPresetFor(distanceM: number): UltraPresetId | null {
		return ULTRA_PRESETS.find((p) => Math.abs(p.distanceM - distanceM) < 1)?.id ?? null;
	}

	function onGoalChange(e: Event) {
		exitImportMode();
		const value = (e.currentTarget as HTMLSelectElement).value;
		if (value === 'ultra_other' || ULTRA_PRESETS.some((p) => p.id === value)) {
			const preset = ULTRA_PRESETS.find((p) => p.id === value);
			ultraChoice = value as UltraChoice;
			goalEvent = 'custom';
			ultraDistanceM = preset?.distanceM ?? ultraDistanceM ?? 70_000;
			return;
		}
		ultraChoice = null;
		goalEvent = value as GoalEvent;
	}
	let startDate = $state(untrack(() => initialStartDate ?? defaultStart()));
	let daysPerWeek = $state(4);

	let targetHours = $state<number | null>(null);
	let targetMin = $state<number | null>(null);
	let targetSec = $state<number | null>(null);

	let recent5kMin = $state<number | null>(null);
	let recent5kSec = $state<number | null>(null);
	// Returning runners type an old PR; the engine would treat it as current
	// fitness and prescribe paces that are too fast (injury risk — comeback
	// persona #24). The time only anchors paces once the runner confirms it
	// reflects current fitness; otherwise we fall back to goal-based paces.
	let recent5kConfirmed = $state(false);
	// Beginner / return-to-run: generate a C25K-style walk-run plan (persona #22).
	let beginnerWalkRun = $state(untrack(() => initialBeginnerWalkRun ?? false));

	let weekOverride = $state<number | null>(untrack(() => initialWeeks ?? null));
	let busy = $state(false);
	let error = $state<string | null>(null);

	// "Describe the plan you want". The AI is the interface, never the planner:
	// it only fills the fields below, and the generator builds the plan from
	// them exactly as it does for a hand-filled form. Every failure leaves the
	// manual form as it was.
	const showAiPlan = coachEnabled() && aiPlanEnabled();
	const handedDescription = untrack(() => (showAiPlan ? (initialDescription?.trim() ?? '') : ''));
	let aiRequest = $state(handedDescription);
	let aiBox = $state<HTMLDetailsElement | null>(null);
	let aiBusy = $state(false);
	let aiError = $state<{ message: string; consent: boolean } | null>(null);
	let aiApplied = $state<{
		assumptions: PlanRequestAssumption[];
		raceNote: string | null;
		recent5kFilled: boolean;
	} | null>(null);
	// The runner's own plan name always beats the extracted one.
	let nameTouched = $state(false);
	// The start date the last AI fill derived from a race date. A later fill
	// without a race date puts it back, so the plan stops being sized for a
	// race the new description no longer mentions; a date the runner picked
	// by hand is left alone.
	let aiRaceStart = $state<string | null>(null);

	const AI_ASSUMPTION_KEYS: Record<PlanRequestAssumption, MessageKey> = {
		goal_event_default: 'planEditor.aiAssumptionGoalEventDefault',
		days_per_week_default: 'planEditor.aiAssumptionDaysDefault',
		days_per_week_clamped: 'planEditor.aiAssumptionDaysClamped',
		weeks_clamped: 'planEditor.aiAssumptionWeeksClamped',
		race_date_dropped: 'planEditor.aiAssumptionRaceDateDropped',
		goal_time_dropped: 'planEditor.aiAssumptionGoalTimeDropped',
		recent_5k_dropped: 'planEditor.aiAssumptionRecent5kDropped',
		beginner_5k: 'planEditor.aiAssumptionBeginner5k',
	};
	const RACE_REFUSAL_KEYS: Record<RacePlanRefusal, MessageKey> = {
		past: 'planEditor.aiRacePast',
		too_soon: 'planEditor.aiRaceTooSoon',
		invalid: 'planEditor.aiRaceInvalid',
	};

	function addDaysIso(iso: string, days: number): string {
		const d = parseISO(iso);
		d.setDate(d.getDate() + days);
		return formatISO(d);
	}

	/// Presets the start date + length so race week contains race day, and
	/// returns the note saying so — or why it could not.
	function applyRaceDate(raceDate: string, requestedWeeks: number | null): string {
		const result = racePlanPreset({
			raceDateIso: raceDate,
			distanceM: goalDistance,
			todayIso: todayIso(),
		});
		if (!result.ok) return t(RACE_REFUSAL_KEYS[result.reason]);
		let { weeks: presetWeeks, startDate: presetStart } = result.preset;
		// A shorter plan the runner asked for still ends on race week: start
		// later rather than earlier. A longer one cannot fit, so the preset wins.
		if (requestedWeeks != null && requestedWeeks < presetWeeks) {
			presetStart = addDaysIso(presetStart, (presetWeeks - requestedWeeks) * 7);
			presetWeeks = requestedWeeks;
		}
		startDate = presetStart;
		aiRaceStart = presetStart;
		startSnapped = false;
		weekOverride = presetWeeks;
		return t('planEditor.aiRaceApplied', {
			date: parseISO(raceDate).toLocaleDateString(activeFormatLocale(), { dateStyle: 'medium' }),
		});
	}

	function applyPlanInputs(inputs: PlanRequestInputs) {
		exitImportMode();
		beginnerWalkRun = inputs.beginnerWalkRun;
		goalEvent = inputs.goalEvent;
		ultraChoice = null;
		daysPerWeek = inputs.daysPerWeek;
		// A fill replaces the shape of the plan, not just the fields this
		// description happened to name: a second fill must not inherit the
		// first one's length, race start or goal time.
		weekOverride = inputs.weeks;
		if (!inputs.raceDate && aiRaceStart !== null && startDate === aiRaceStart) {
			startDate = defaultStart();
		}
		aiRaceStart = null;
		if (inputs.goalTimeSec != null) {
			targetHours = Math.floor(inputs.goalTimeSec / 3600);
			targetMin = Math.floor((inputs.goalTimeSec % 3600) / 60);
			targetSec = inputs.goalTimeSec % 60;
		} else {
			targetHours = null;
			targetMin = null;
			targetSec = null;
		}
		if (inputs.recent5kSec != null) {
			recent5kMin = Math.floor(inputs.recent5kSec / 60);
			recent5kSec = inputs.recent5kSec % 60;
			// Never ticked for the runner: whether the time reflects their
			// fitness today is theirs to confirm, and an unconfirmed time keeps
			// the paces on the conservative goal-based fallback.
			recent5kConfirmed = false;
		}
		if (inputs.planName && (!nameTouched || !name.trim())) name = inputs.planName;
		const raceNote = inputs.raceDate ? applyRaceDate(inputs.raceDate, inputs.weeks) : null;
		aiApplied = {
			assumptions: inputs.assumptions,
			raceNote,
			recent5kFilled: inputs.recent5kSec != null,
		};
	}

	function aiErrorFor(e: unknown): { message: string; consent: boolean } {
		const kind = e instanceof PlanRequestError ? e.kind : 'unavailable';
		if (kind === 'consent') return { message: t('planEditor.aiErrorConsent'), consent: true };
		if (kind === 'daily_limit') return { message: t('planEditor.aiErrorDailyLimit'), consent: false };
		return { message: t('planEditor.aiErrorFallback'), consent: false };
	}

	// A deep-linked description spends a Coach message, so it runs once and
	// leaves the URL: a reload or a back-navigation must not run it again.
	// The strip waits a macrotask because SvelteKit refuses replaceState until
	// its router has finished starting, which is after the first mount.
	function stripDescribeParam() {
		const url = new URL(page.url.href);
		if (!url.searchParams.has('describe')) return;
		url.searchParams.delete('describe');
		try {
			replaceState(`${url.pathname}${url.search}${url.hash}`, page.state);
		} catch (e) {
			console.error('Clearing the plan description from the URL failed', { message: thrownMessage(e) });
		}
	}

	onMount(() => {
		if (!handedDescription) return;
		if (aiBox) {
			aiBox.open = true;
			aiBox.scrollIntoView({ block: 'start' });
		}
		void fillFromDescription();
		setTimeout(stripDescribeParam, 0);
	});

	async function fillFromDescription() {
		const text = aiRequest.trim();
		if (!text || aiBusy) return;
		aiBusy = true;
		aiError = null;
		aiApplied = null;
		let inputs: PlanRequestInputs;
		try {
			inputs = await requestPlanInputs(text, todayIso());
		} catch (e) {
			if (!(e instanceof PlanRequestError)) {
				console.error('Plan assistant request failed', { message: thrownMessage(e) });
			}
			aiError = aiErrorFor(e);
			aiBusy = false;
			return;
		}
		// Its own catch: a fill that throws part-way must not take the editor
		// down with it — the fields already set stay, the runner edits the rest.
		try {
			applyPlanInputs(inputs);
		} catch (e) {
			console.error('Applying plan assistant inputs failed', { message: thrownMessage(e) });
			aiError = { message: t('planEditor.aiErrorFallback'), consent: false };
		} finally {
			aiBusy = false;
		}
	}

	// Editable plan state. The auto-generator produces a candidate
	// outline whenever core form inputs change; the user can then
	// tweak individual workouts before clicking Create plan. Touching
	// any non-week input regenerates and discards user edits — matches
	// the "if you change the goal, the schedule changes" expectation.
	let plan = $state<GeneratedPlan | null>(null);
	let expandedWeek = $state<number | null>(null);

	// Paste-import state. When `importedMode` is on, the auto-generate
	// effect stands down so a pasted plan isn't clobbered; changing any
	// core form input exits import mode and hands control back to the
	// generator. `importedGoalDistanceM` carries the parsed goal distance
	// (the generator's `goalDistance` derived is wrong for a custom event).
	let showImport = $state(false);
	let importText = $state('');
	let importError = $state<string | null>(null);
	let importedMode = $state(false);
	let importedGoalDistanceM = $state<number | null>(null);

	function loadFromText() {
		importError = null;
		const text = importText.trim();
		if (!text) return;
		try {
			const parsed = text.startsWith('{') ? parsePlanJson(text) : parsePlanMarkdown(text);
			name = parsed.name;
			goalEvent = parsed.goalEvent;
			const pastedUltra = parsed.goalEvent === 'custom' && isUltraDistance(parsed.goalDistanceM);
			ultraChoice = pastedUltra ? (ultraPresetFor(parsed.goalDistanceM) ?? 'ultra_other') : null;
			ultraDistanceM = pastedUltra ? parsed.goalDistanceM : ultraDistanceM;
			startDate = parsed.startDate;
			importedGoalDistanceM = parsed.goalDistanceM;
			if (parsed.goalTimeSec != null && parsed.goalTimeSec > 0) {
				targetHours = Math.floor(parsed.goalTimeSec / 3600);
				targetMin = Math.floor((parsed.goalTimeSec % 3600) / 60);
				targetSec = parsed.goalTimeSec % 60;
			}
			importedMode = true;
			plan = parsed.generated;
			expandedWeek = null;
			showImport = false;
		} catch (e) {
			importError = describeError(e);
		}
	}

	/// Changing a core input means the runner wants the generator back —
	/// drop import mode so the reactive effect regenerates from the form.
	function exitImportMode() {
		if (importedMode) {
			importedMode = false;
			importedGoalDistanceM = null;
		}
	}

	const KIND_OPTIONS: WorkoutKind[] = [
		'easy',
		'long',
		'recovery',
		'tempo',
		'interval',
		'marathon_pace',
		'race',
		'rest',
	];

	function paceToInput(secPerKm: number | null): string {
		if (secPerKm == null || secPerKm <= 0) return '';
		return paceMinutesSeconds(secPerKm);
	}

	function inputToPace(raw: string): number | null {
		const trimmed = raw.trim();
		if (!trimmed) return null;
		const m = trimmed.match(/^(\d{1,2}):(\d{2})$/);
		if (!m) return null;
		return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
	}

	function paceInputHandler(weekIdx: number, woIdx: number) {
		return (e: Event) => {
			if (!plan) return;
			const value = (e.currentTarget as HTMLInputElement).value;
			const sec = inputToPace(value);
			plan.weeks[weekIdx].workouts[woIdx].target_pace_sec_per_km = sec;
		};
	}

	function describeError(e: unknown): string {
		return thrownMessage(e) || t('planEditor.errorCreateFailed');
	}

	// A brand-new runner ticking the walk-run box is not training for a half
	// (the default goal) — point them at 5K, the appropriate first-timer
	// target. One-shot on enable only, and only when the current goal is
	// longer than 5K, so it never clobbers a deliberate 5K choice and never
	// stops them re-picking 10K afterwards.
	function onBeginnerToggle(e: Event) {
		beginnerWalkRun = (e.currentTarget as HTMLInputElement).checked;
		if (beginnerWalkRun && goalDistance > GOAL_DISTANCES_M.distance_5k) {
			goalEvent = 'distance_5k';
			ultraChoice = null;
		}
	}

	function defaultStart(): string {
		const d = new Date();
		d.setDate(d.getDate() + 7);
		d.setDate(d.getDate() + ((7 - d.getDay()) % 7));
		return formatISO(d);
	}

	// The generator hard-anchors day 0 of the start week to the Sunday long
	// run (rest=Mon, quality=Tue/Thu). A non-Sunday start silently shifts
	// every day-role, so the long run lands on a weekday. The <input
	// type="date"> can't restrict to Sundays, so snap the chosen date
	// forward to the upcoming Sunday on change — the reactive preview then
	// regenerates from the aligned date, keeping what the user sees in sync
	// with what's saved. (Persona round-5 intermediate.)
	let startSnapped = $state(false);
	function alignStartToSunday() {
		if (!startDate) return;
		if (isSundayIso(startDate)) {
			startSnapped = false;
			return;
		}
		startDate = nextSundayIso(startDate);
		startSnapped = true;
	}

	let goalDistance = $derived(
		goalEvent !== 'custom'
			? GOAL_DISTANCES_M[goalEvent]
			: ultraChoice != null
				? (ultraDistanceM ?? 0)
				: 10_000
	);
	// An ultra entry whose typed distance is not past the marathon plans
	// nothing: the generator would quietly build a road plan under an ultra
	// label.
	let ultraDistanceInvalid = $derived(ultraChoice != null && !isUltraDistance(goalDistance));
	// A beginner walk-run plan needs the full C25K progression length (9
	// weeks), not the 5k continuous-run default (8) — otherwise the final
	// graduation week is dropped. Persona round-5 runner-new. An explicit
	// override still wins.
	let weeks = $derived(
		weekOverride ??
			(beginnerWalkRun ? walkRunDefaultWeeks() : defaultPlanWeeks(goalEvent, goalDistance))
	);

	let goalTimeSec = $derived(
		targetHours != null || targetMin != null || targetSec != null
			? (targetHours ?? 0) * 3600 + (targetMin ?? 0) * 60 + (targetSec ?? 0)
			: null
	);
	let recent5kTotal = $derived(
		recent5kMin != null || recent5kSec != null
			? (recent5kMin ?? 0) * 60 + (recent5kSec ?? 0)
			: null
	);
	// Only anchor paces on the entered time once the runner confirms it's
	// current. An entered-but-unconfirmed time is treated as absent so paces
	// stay on the conservative goal-based fallback.
	let recent5kApplied = $derived(recent5kConfirmed ? recent5kTotal : null);
	let recent5kNeedsConfirm = $derived(recent5kTotal != null && !recent5kConfirmed);

	// A beginner walk-run plan is duration-based intervals, not pace-based —
	// the VDOT badge and the five Daniels pace zones are jargon the runner who
	// ticked "New to running?" can't parse and never uses. Detect it from the
	// plan itself (every session is a walk_run workout) so a pasted walk-run
	// plan is covered too, then hide the pace panel for it.
	let isWalkRunPlan = $derived(
		!!plan && plan.weeks.some((w) => w.workouts.some((wo) => wo.kind === 'walk_run'))
	);

	// How the plan compares with what the runner has actually been running.
	// Recomputes as the goal / days / weeks inputs change, so dropping a
	// training day shows the ramp easing in real time.
	let rampCheck = $derived(
		plan && recentVolume
			? planRampCheck(
					openingWeekVolumeM(plan.weeks),
					peakWeekVolumeM(plan.weeks),
					recentVolume
				)
			: null
	);
	let rampMessage = $derived.by(() => {
		if (!rampCheck || !shouldSurfaceRampNote(rampCheck, { beginnerWalkRun: isWalkRunPlan })) {
			return null;
		}
		const recent = fmtKm(rampCheck.recentWeeklyM, 0);
		// Each verdict quotes the week it was graded on: the safety warnings
		// are about the first step, the under-cooked one about the peak.
		if (rampCheck.verdict === 'under') {
			return t('planEditor.rampUnder', { peak: fmtKm(rampCheck.peakWeekM, 0), recent });
		}
		const opening = fmtKm(rampCheck.openingWeekM, 0);
		if (rampCheck.verdict === 'elevated') {
			return t('planEditor.rampElevated', { opening, recent });
		}
		return t('planEditor.rampHigh', { opening, recent });
	});

	// Re-generate the editable plan whenever any input that drives
	// generation changes. Replaces the previous $derived preview so we
	// can mutate workouts in-place; the user's edits live on `plan`
	// until they touch a top-level input again.
	$effect(() => {
		// Read every input we care about so the effect tracks them.
		void [goalEvent, goalDistance, ultraDistanceInvalid, goalTimeSec, recent5kApplied, startDate, daysPerWeek, weeks, viewerGender, beginnerWalkRun, importedMode];
		// A pasted plan owns `plan` until the runner edits a core input
		// (which flips importedMode off and re-runs this effect).
		if (importedMode) return;
		if (!startDate || ultraDistanceInvalid) {
			plan = null;
			return;
		}
		try {
			plan = generatePlan({
				goalEvent,
				goalDistanceM: goalDistance,
				goalTimeSec,
				recent5kSec: recent5kApplied,
				startDate,
				daysPerWeek,
				weeks,
				gender: viewerGender,
				age: viewerAge,
				beginnerWalkRun,
			});
			expandedWeek = null;
		} catch (_) {
			plan = null;
		}
	});

	const eventOptions: { value: GoalEvent; label: string }[] = $derived([
		{ value: 'distance_5k', label: '5K' },
		{ value: 'distance_10k', label: '10K' },
		{ value: 'distance_half', label: t('planEditor.halfMarathon') },
		{ value: 'distance_full', label: t('planEditor.marathon') }
	]);
	const ULTRA_LABELS: Record<UltraPresetId, string> = {
		ultra_50k: '50 km',
		ultra_56k: '56 km',
		ultra_90k: '90 km',
		ultra_100mi: '100 mi',
	};
	const ultraOptions: { value: UltraChoice; label: string }[] = $derived([
		...ULTRA_PRESETS.map((p) => ({ value: p.id as UltraChoice, label: ULTRA_LABELS[p.id] })),
		{ value: 'ultra_other', label: t('planEditor.ultraOther') },
	]);
	// Smallest distance the ultra input accepts, in the runner's unit: the
	// first tenth past the marathon.
	let ultraMinInput = $derived(
		String(Math.ceil((GOAL_DISTANCES_M.distance_full / distancePerUnit) * 10 + 0.001) / 10),
	);

	/// Active plans may chain but not overlap (decisions § 2008). The create
	/// asks the server to refuse any overlap; when it does, the dialog names
	/// the plans in the way, read fresh at that moment, and the runner's choice
	/// is sent back so the server resolves it in the same transaction as the
	/// insert (decisions § 2050). A plan created since an earlier look is
	/// therefore never replaced without being named first.
	let overlapping = $state<OverlapPlan[]>([]);

	async function submit(e: Event) {
		e.preventDefault();
		if (!name.trim() || !plan || busy) return;
		// Persona-hunt Intermediate #3: a startDate in the past
		// generates a plan anchored to elapsed weeks — the today-card +
		// progress ring report "you're already two workouts behind" the
		// moment the plan is created. The wizard's input has min=today
		// (set on the markup below) but a user that opened the modal
		// yesterday could submit a stale value before the page reloads,
		// and a future refactor that drops the markup-level min loses
		// the only guardrail. Validate at submit-time too.
		if (!importedMode && startDate && startDate < todayIso()) {
			error = t('planEditor.errorStartInPast');
			return;
		}
		// Defensive backstop: onchange snaps the date to a Sunday, but if a
		// non-Sunday slipped through (keyboard entry that didn't fire
		// onchange), snap now and re-show the preview rather than persisting
		// a misaligned plan. The reactive preview regenerates from the
		// aligned date, so ask the user to submit once more.
		if (!importedMode && startDate && !isSundayIso(startDate)) {
			alignStartToSunday();
			error = t('planEditor.errorStartMovedToSunday');
			return;
		}
		await proceedWithCreate('refuse');
	}

	function todayIso(): string {
		const d = new Date();
		return formatISO(d);
	}

	async function proceedWithCreate(overlap: PlanOverlapChoice) {
		busy = true;
		error = null;
		overlapping = [];
		const endDate = plan!.endDate;
		try {
			const outcome = await attemptPlanCreate(
				() =>
					createTrainingPlan({
						name: name.trim(),
						goalEvent,
						// A pasted plan's distance comes from the parse (the derived
						// `goalDistance` is wrong for a custom-event import).
						goalDistanceM: importedMode && importedGoalDistanceM ? importedGoalDistanceM : goalDistance,
						goalTimeSec,
						recent5kSec: recent5kApplied,
						startDate,
						daysPerWeek,
						generated: plan!,
						overlap,
					}),
				() => fetchMyOverlappingActivePlans(startDate, endDate)
			);
			if (outcome.kind === 'overlap') overlapping = outcome.overlapping;
			else if (outcome.kind === 'trimBlocked') error = trimBlockedMessage(outcome.overlapping, startDate);
			else oncreated?.(outcome.value);
		} catch (e: unknown) {
			error = describeError(e);
			console.error('Plan create failed', e);
		} finally {
			busy = false;
		}
	}

	function cancelOverlap() {
		overlapping = [];
	}
</script>

<form onsubmit={submit} class="plan-editor">
	<!-- Spans both columns: a pasted plan is a wide Markdown table, and the
	     22rem form column wrapped every row of it. -->
	<details class="import-box import-wide" bind:open={showImport}>
		<summary id="plan-import-title">{t('planEditor.importTitle')}</summary>
		<p class="hint" id="plan-import-hint">{t('planEditor.importHint')}</p>
		<textarea
			aria-labelledby="plan-import-title"
			class="import-text"
			bind:value={importText}
			rows="14"
			wrap="off"
			placeholder={t('planEditor.importPlaceholder')}
			aria-describedby="plan-import-hint"
		></textarea>
		{#if importError}
			<p class="error">{importError}</p>
		{/if}
		<button type="button" class="btn btn-secondary" onclick={loadFromText}>
			{t('planEditor.importLoad')}
		</button>
	</details>
	<div class="grid">
		<section class="form">
			{#if showAiPlan}
				<details class="import-box ai-box" id="ai-plan" bind:this={aiBox} open>
					<summary>{t('planEditor.aiTitle')}</summary>
					<p class="hint" id="plan-ai-hint">{t('planEditor.aiHint')}</p>
					<label class="visually-hidden" for="plan-ai-request">{t('planEditor.aiTitle')}</label>
					<textarea
						id="plan-ai-request"
						class="ai-text"
						bind:value={aiRequest}
						rows="3"
						maxlength="600"
						placeholder={t('planEditor.aiPlaceholder')}
						aria-describedby="plan-ai-hint"
						disabled={aiBusy}
					></textarea>
					<button
						type="button"
						class="btn btn-secondary"
						onclick={fillFromDescription}
						disabled={aiBusy || !aiRequest.trim()}
						aria-busy={aiBusy}
					>
						{aiBusy ? t('planEditor.aiWorking') : t('planEditor.aiButton')}
					</button>
					{#if aiError}
						<p class="error ai-error" role="alert">
							{aiError.message}
							{#if aiError.consent}
								<a href={AI_CONSENT_HREF}>{t('planEditor.aiErrorConsentLink')}</a>
							{/if}
						</p>
					{/if}
					{#if aiApplied}
						<div class="ai-applied" role="status">
							<p class="ai-applied-title">{t('planEditor.aiAppliedTitle')}</p>
							<ul>
								<li>{t('planEditor.aiAppliedGenerator')}</li>
								{#if aiApplied.raceNote}
									<li>{aiApplied.raceNote}</li>
								{/if}
								{#if aiApplied.recent5kFilled}
									<li>{t('planEditor.aiAppliedRecent5k')}</li>
								{/if}
								{#each aiApplied.assumptions as a (a)}
									<li>{t(AI_ASSUMPTION_KEYS[a])}</li>
								{/each}
							</ul>
						</div>
					{/if}
				</details>
			{/if}
			{#if importedMode}
				<p class="imported-note" role="status">{t('planEditor.importedNote')}</p>
			{/if}

			<div class="field">
				<label>
					<span>{t('planEditor.planName')}</span>
					<input
						type="text"
						bind:value={name}
						oninput={() => (nameTouched = true)}
						placeholder={t('planEditor.planNamePlaceholder')}
						required
						maxlength={lengthLimit('training_plans.name')}
						aria-describedby="plan-name-hint"
					/>
				</label>
				<p class="hint" id="plan-name-hint">{t('planEditor.planNameHint')}</p>
			</div>

			<div class="field">
				<label>
					<span>{t('planEditor.goalRace')}</span>
					<select value={ultraChoice ?? goalEvent} onchange={onGoalChange} aria-describedby="goal-race-hint">
						<optgroup label={t('planEditor.goalGroupRoad')}>
							{#each eventOptions as opt}
								<option value={opt.value}>{opt.label}</option>
							{/each}
						</optgroup>
						<optgroup label={t('planEditor.goalGroupUltra')}>
							{#each ultraOptions as opt}
								<option value={opt.value}>{opt.label}</option>
							{/each}
						</optgroup>
					</select>
				</label>
				<p class="hint" id="goal-race-hint">{t('planEditor.goalRaceHint')}</p>
			</div>

			{#if ultraChoice}
				<div class="field">
					<label>
						<span>{t('planEditor.ultraDistance', { unit: distanceUnit })}</span>
						<input
							type="number"
							min={ultraMinInput}
							step="0.1"
							value={metresToDistanceInput(ultraDistanceM)}
							oninput={(e) => {
								exitImportMode();
								ultraDistanceM = distanceInputToMetres((e.currentTarget as HTMLInputElement).value);
							}}
							aria-describedby="ultra-distance-hint"
							aria-invalid={ultraDistanceInvalid}
							data-testid="plan-ultra-distance"
						/>
					</label>
					<p class="hint" id="ultra-distance-hint">{t('planEditor.ultraDistanceHint')}</p>
					{#if ultraDistanceInvalid}
						<p class="hint warn" role="alert">{t('planEditor.ultraDistanceTooShort')}</p>
					{/if}
				</div>
			{/if}

			<div class="field">
				<label>
					<span>{t('planEditor.startDate')} <span class="optional">{t('planEditor.firstWeekBeginsSunday')}</span></span>
					<input
						type="date"
						bind:value={startDate}
						min={importedMode ? undefined : todayIso()}
						onchange={() => { exitImportMode(); alignStartToSunday(); }}
						required
						aria-describedby="start-date-hint"
					/>
					{#if startSnapped}
						<span class="field-note">{t('planEditor.movedToNextSunday')}</span>
					{/if}
				</label>
				<p class="hint" id="start-date-hint">{t('planEditor.startDateHint')}</p>
			</div>

			<div class="field">
				<label>
					<span>{t('planEditor.daysPerWeek')}</span>
					<select bind:value={daysPerWeek} onchange={exitImportMode} aria-describedby="days-per-week-hint">
						{#each [3, 4, 5, 6, 7] as n}
							<option value={n}>{t('planEditor.nDays', { n })}</option>
						{/each}
					</select>
				</label>
				<p class="hint" id="days-per-week-hint">{t('planEditor.daysPerWeekHint')}</p>
			</div>

			<fieldset>
				<legend>{t('planEditor.goalTime')} <span class="optional">{t('planEditor.optional')}</span></legend>
				<p class="hint" id="goal-time-hint">{t('planEditor.goalTimeHint')}</p>
				<div class="time-row">
					<input type="number" min="0" max={RACE_GOAL_MAX_HOURS} bind:value={targetHours} placeholder={t('planEditor.placeholderHours')} aria-describedby="goal-time-hint" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={targetMin} placeholder={t('planEditor.placeholderMinutes')} aria-describedby="goal-time-hint" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={targetSec} placeholder={t('planEditor.placeholderSeconds')} aria-describedby="goal-time-hint" />
				</div>
			</fieldset>

			<label class="beginner-toggle">
				<input type="checkbox" checked={beginnerWalkRun} onchange={onBeginnerToggle} />
				<span>
					<span class="beginner-title">{t('planEditor.beginnerTitle')}</span>
					<span class="hint">
						{t('planEditor.beginnerHint')}
					</span>
				</span>
			</label>

			<fieldset>
				<legend>{t('planEditor.recent5kTime')} <span class="optional">{t('planEditor.optional')}</span></legend>
				<p class="hint" id="recent-5k-hint"><MetricLabel metric="riegel" sentence="planEditor.recent5kHint" /></p>
				<div class="time-row">
					<input type="number" min="0" max="59" bind:value={recent5kMin} placeholder={t('planEditor.placeholderMinutes')} aria-describedby="recent-5k-hint" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={recent5kSec} placeholder={t('planEditor.placeholderSeconds')} aria-describedby="recent-5k-hint" />
				</div>
				{#if recent5kTotal != null}
					<label class="confirm-recent">
						<input type="checkbox" bind:checked={recent5kConfirmed} />
						<span>
							{t('planEditor.recent5kConfirm')}
							<span class="hint">{t('planEditor.recent5kConfirmHint')}</span>
						</span>
					</label>
				{/if}
				{#if recent5kNeedsConfirm}
					<p class="hint warn" role="status">
						{t('planEditor.recent5kWarn')}
					</p>
				{/if}
			</fieldset>

			<div class="field">
				<label>
					<span>{t('planEditor.overrideTotalWeeks')} <span class="optional">{t('planEditor.optional')}</span></span>
					<input
						type="number"
						min="4"
						max="24"
						bind:value={weekOverride}
						placeholder={String(defaultPlanWeeks(goalEvent, goalDistance))}
						aria-describedby="override-weeks-hint"
					/>
				</label>
				<p class="hint" id="override-weeks-hint">{t('planEditor.overrideTotalWeeksHint')}</p>
			</div>

			{#if error}
				<p class="error">{error}</p>
			{/if}

			<div class="actions">
				{#if oncancel}
					<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>{t('planEditor.cancel')}</button>
				{/if}
				<button type="submit" class="btn btn-primary" disabled={!name.trim() || !plan || busy}>
					{busy ? t('planEditor.creating') : t('planEditor.createPlan')}
				</button>
			</div>
		</section>

		<aside class="preview">
			<h2>{t('planEditor.previewAndEdit')}</h2>
			{#if plan}
				{#if !isWalkRunPlan}
					<div class="paces">
						<div class="pace-row"><span>{t('planEditor.paceEasy')}</span><strong>{fmtPace(plan.paces.easy)}</strong></div>
						<div class="pace-row"><span>{t('planEditor.paceMarathon')}</span><strong>{fmtPace(plan.paces.marathon)}</strong></div>
						<div class="pace-row"><span>{t('planEditor.paceTempo')}</span><strong>{fmtPace(plan.paces.tempo)}</strong></div>
						<div class="pace-row"><span>{t('planEditor.paceInterval')}</span><strong>{fmtPace(plan.paces.interval)}</strong></div>
						<div class="pace-row"><span>{t('planEditor.paceRepetition')}</span><strong>{fmtPace(plan.paces.repetition)}</strong></div>
					</div>

					{#if plan.pacesAreFallback}
						<p class="paces-estimated" role="status">
							{t('planEditor.pacesEstimated')}
						</p>
					{/if}

					{#if plan.vdot}
						<p class="vdot"><MetricLabel metric="vdot" /> <strong>{plan.vdot.toFixed(1)}</strong></p>
					{/if}
				{/if}

				{#if rampMessage}
					<div class="ramp-note" role="status">
						<h3>{t('planEditor.rampLabel')}</h3>
						<p>{rampMessage}</p>
					</div>
				{/if}

				<div class="outline-head">
					<h3>{t('planEditor.weekOutline')}</h3>
					<MetricLabel metric="planPhases" />
				</div>
				<p class="outline-hint" id="week-outline-hint">
					{t('planEditor.outlineHint')}
				</p>
				<ul class="weeks">
					{#each plan.weeks as w, weekIdx (w.week_index)}
						{@const sessionCount = w.workouts.filter((x) => x.kind !== 'rest').length}
						<li class="week-item" class:expanded={expandedWeek === weekIdx}>
							<button
								type="button"
								class="week-row"
								onclick={() => (expandedWeek = expandedWeek === weekIdx ? null : weekIdx)}
							>
								<span class="week-num">#{w.week_index + 1}</span>
								<span class="week-phase">{planPhaseLabel(w.phase)}</span>
								<span class="week-km">{fmtKm(w.target_volume_m, 0)}</span>
								<span class="week-workouts">
									{t(sessionCount === 1 ? 'planEditor.nSessionsOne' : 'planEditor.nSessionsMany', { n: sessionCount })}
								</span>
								<span class="caret material-symbols">
									{expandedWeek === weekIdx ? 'expand_less' : 'expand_more'}
								</span>
							</button>

							{#if expandedWeek === weekIdx}
								<div class="week-editor">
									{#each w.workouts as wo, woIdx (woIdx)}
										<div class="wo-row">
											<div class="wo-date">
												{parseISO(wo.scheduled_date).toLocaleDateString(activeFormatLocale(), {
													weekday: 'short',
													month: 'short',
													day: 'numeric',
												})}
											</div>
											<label class="wo-field">
												<span>{t('planEditor.runType')}</span>
												<select bind:value={w.workouts[woIdx].kind} aria-describedby="week-outline-hint">
													{#each KIND_OPTIONS as k}
														<option value={k}>{workoutKindLabel(k)}</option>
													{/each}
												</select>
											</label>
											<label class="wo-field">
												<span>{t('planEditor.distance', { unit: distanceUnit })}</span>
												<input
													type="number"
													min="0"
													step={distanceStep}
													value={metresToDistanceInput(wo.target_distance_m)}
													aria-describedby="week-outline-hint"
													oninput={(e) => {
														w.workouts[woIdx].target_distance_m = distanceInputToMetres(
															(e.currentTarget as HTMLInputElement).value,
														);
													}}
													disabled={wo.kind === 'rest'}
												/>
											</label>
											<label class="wo-field">
												<span>{t('planEditor.paceMmSs')}</span>
												<input
													type="text"
													inputmode="numeric"
													pattern={'[0-9]{1,2}:[0-9]{2}'}
													placeholder="—"
													value={paceToInput(wo.target_pace_sec_per_km)}
													aria-describedby="week-outline-hint"
													oninput={paceInputHandler(weekIdx, woIdx)}
													disabled={wo.kind === 'rest'}
												/>
											</label>
											<label class="wo-field wo-notes">
												<span>{t('planEditor.notes')}</span>
												<input
													type="text"
													bind:value={w.workouts[woIdx].notes}
													placeholder="—"
													maxlength="200"
													aria-describedby="week-outline-hint"
												/>
											</label>
										</div>
									{/each}
								</div>
							{/if}
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">{t('planEditor.fillFormForPreview')}</p>
			{/if}
		</aside>
	</div>
</form>

<PlanOverlapDialog
	{overlapping}
	{startDate}
	onchoose={proceedWithCreate}
	oncancel={cancelOverlap}
/>

<style>
	.plan-editor {
		display: block;
	}
	.grid {
		display: grid;
		grid-template-columns: minmax(0, 22rem) minmax(0, 1fr);
		gap: var(--space-lg);
	}
	@media (max-width: 60rem) {
		.grid {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	.form,
	.preview {
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	label,
	fieldset {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		font-size: 0.9rem;
		font-weight: 600;
		/* The UA sheet gives every fieldset `min-width: min-content`, which
		   is what stops this one shrinking into its grid track. */
		min-width: 0;
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		min-width: 0;
	}
	.field .hint {
		margin-bottom: 0;
	}
	.optional {
		font-weight: 400;
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}
	.field-note {
		display: block;
		margin-top: var(--space-2xs);
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		font-weight: 400;
	}
	input[type='text'],
	input[type='date'],
	input[type='number'],
	select {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.55rem 0.75rem;
		font: inherit;
		color: inherit;
	}
	fieldset {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.8rem 1rem;
		background: var(--color-surface);
	}
	legend {
		font-weight: 600;
		padding: 0 0.4rem;
	}
	.hint {
		font-weight: 400;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin-bottom: 0.4rem;
	}
	/* Full-contrast text (not --color-warning, which is a light accent that
	   fails AA as body text on the cream surface); emphasis carries "warning". */
	.hint.warn {
		color: var(--color-text);
		font-weight: 500;
	}
	.confirm-recent {
		display: flex;
		align-items: flex-start;
		gap: 0.5rem;
		margin-top: 0.5rem;
		font-size: 0.85rem;
		font-weight: 400;
	}
	.beginner-toggle {
		display: flex;
		align-items: flex-start;
		gap: 0.6rem;
	}
	.beginner-toggle input { margin-top: 0.2rem; }
	.beginner-title { display: block; font-weight: 600; }
	.confirm-recent input {
		margin-top: 0.15rem;
	}
	.confirm-recent .hint {
		display: block;
		margin-bottom: 0;
	}
	.time-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.4rem;
	}
	.time-row input {
		width: 4rem;
		min-width: 0;
		text-align: center;
	}
	.time-row span {
		font-weight: 700;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.6rem;
	}
	.error {
		color: var(--color-danger-text);
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
	}
	.import-box {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		padding: 0.4rem 0.7rem;
	}
	.import-box summary {
		cursor: pointer;
		font-weight: 600;
		font-size: 0.9rem;
		padding: 0.25rem 0;
	}
	.import-box[open] summary {
		margin-bottom: 0.4rem;
	}
	.import-wide {
		margin-bottom: var(--space-lg);
	}
	.import-text {
		width: 100%;
		box-sizing: border-box;
		font-family: var(--font-mono);
		font-size: 0.8rem;
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: 0.5rem;
		color: var(--color-text);
		resize: vertical;
		white-space: pre;
		overflow-x: auto;
		margin-bottom: 0.5rem;
	}
	.ai-text {
		width: 100%;
		box-sizing: border-box;
		font: inherit;
		font-size: 0.9rem;
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: 0.5rem;
		color: var(--color-text);
		resize: vertical;
		margin-bottom: 0.5rem;
	}
	.ai-error {
		margin-top: 0.5rem;
	}
	.ai-error a {
		color: inherit;
		font-weight: 600;
	}
	.ai-applied {
		margin-top: 0.5rem;
		font-size: 0.85rem;
	}
	.ai-applied-title {
		font-weight: 600;
		color: var(--color-primary);
		margin: 0 0 0.25rem;
	}
	.ai-applied ul {
		margin: 0;
		padding-inline-start: 1.1rem;
		color: var(--color-text-secondary);
	}
	.imported-note {
		font-size: 0.82rem;
		font-weight: 500;
		color: var(--color-primary);
		margin: 0;
	}
	.preview h2 {
		font-size: 1.1rem;
	}
	.preview h3 {
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		margin-top: var(--space-md);
	}
	.paces {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(9rem, 100%), 1fr));
		gap: 0.4rem 0.8rem;
	}
	.pace-row {
		display: flex;
		justify-content: space-between;
		padding: 0.3rem 0.55rem;
		background: var(--color-surface);
		border-radius: var(--radius-md);
		font-size: 0.88rem;
	}
	.vdot {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-top: -0.2rem;
	}
	/* Full-contrast body text (not --color-warning, which fails AA as body
	   text on the surface); weight carries the "this is a caveat" emphasis. */
	.paces-estimated {
		color: var(--color-text);
		font-weight: 500;
		font-size: 0.82rem;
		margin: 0;
	}
	.outline-head {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-xs) var(--space-md);
		margin-top: var(--space-md);
	}
	.outline-head h3 {
		margin: 0;
	}
	.outline-head :global(.metric-label) {
		font-size: 0.78rem;
		color: var(--color-text-secondary);
	}
	.outline-hint {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		margin: 0 0 0.4rem 0;
	}
	/* Full-contrast body text on a plain rule, not a coloured alert panel:
	   the note is advisory on a surface that already carries the fallback-
	   paces disclosure, and a second tinted band would out-shout the plan
	   preview it is annotating. */
	.ramp-note {
		border-inline-start: 3px solid var(--color-border);
		padding-inline-start: 0.7rem;
		margin: 0.6rem 0 0 0;
	}
	.ramp-note h3 {
		margin: 0 0 0.2rem 0;
	}
	.ramp-note p {
		color: var(--color-text);
		font-weight: 500;
		font-size: 0.82rem;
		margin: 0;
	}
	.weeks {
		list-style: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.week-item {
		background: var(--color-surface);
		border-radius: var(--radius-md);
		border: 1px solid var(--color-border);
		min-width: 0;
		overflow: hidden;
	}
	.week-item.expanded {
		border-color: var(--color-primary);
	}
	.week-row {
		display: grid;
		grid-template-columns: 2rem minmax(0, 1fr) auto auto auto;
		gap: 0.5rem;
		align-items: center;
		font-size: 0.85rem;
		padding: 0.45rem 0.6rem;
		background: transparent;
		border: none;
		cursor: pointer;
		text-align: start;
		width: 100%;
		color: inherit;
		font: inherit;
	}
	.week-row:hover {
		background: var(--color-bg-secondary);
	}
	.week-num {
		font-weight: 700;
		color: var(--color-primary);
	}
	.week-phase {
		color: var(--color-text-secondary);
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.week-km {
		color: var(--color-text);
		text-align: end;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.week-workouts {
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
		white-space: nowrap;
	}
	.caret {
		color: var(--color-text-tertiary);
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}
	.week-editor {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		padding: 0.5rem 0.75rem 0.75rem;
		background: var(--color-bg-secondary);
		border-top: 1px solid var(--color-border);
	}
	.wo-row {
		/* Date + run type + distance + pace on one row; notes always
		   wraps to its own line so the four primary fields aren't
		   squeezed against each other and the run-type dropdown has
		   room to display its longer labels (e.g. "Marathon Pace"). */
		display: grid;
		grid-template-columns: minmax(5.5rem, auto) minmax(8rem, 1.3fr) minmax(6rem, 1fr) minmax(6rem, 1fr);
		gap: 0.5rem;
		align-items: end;
		padding: 0.55rem 0.6rem;
		background: var(--color-surface);
		border-radius: var(--radius-sm);
	}
	.wo-notes {
		grid-column: 1 / -1;
	}
	@media (max-width: 50rem) {
		.wo-row {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	.wo-date {
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		white-space: nowrap;
	}
	.wo-field {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		font-size: var(--font-size-section-label);
		font-weight: 600;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		min-width: 0;
	}
	.wo-field input,
	.wo-field select {
		padding: 0.35rem 0.5rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 0.85rem;
		text-transform: none;
		letter-spacing: 0;
		font-weight: 400;
		min-width: 0;
	}
	.wo-field input:disabled,
	.wo-field select:disabled {
		opacity: 0.5;
	}
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
