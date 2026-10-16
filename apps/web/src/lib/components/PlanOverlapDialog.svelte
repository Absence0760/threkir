<script lang="ts">
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { parseISO } from '#lib/training/training.ts';
	import { canTrimOverlap, overlapTrimDate, type OverlapPlan } from '#lib/training/plan_overlap.ts';
	import { m } from '#lib/i18n/store.svelte.ts';

	/// Asks what to do with the active plans a new plan's window overlaps
	/// (decisions § 2008, § 2050): end them the day before the new start, replace
	/// them, or cancel. Every create path — the wizard, a starter plan, a club
	/// template, a public-library clone — shows this same dialog, and passes
	/// the answer to the server, which resolves the overlap in the same
	/// transaction as the write.
	interface Props {
		overlapping: OverlapPlan[];
		startDate: string;
		onchoose: (choice: 'replace' | 'trim') => void | Promise<void>;
		oncancel: () => void;
		'data-testid'?: string;
	}

	let {
		overlapping,
		startDate,
		onchoose,
		oncancel,
		'data-testid': testId = 'plan-overlap-dialog',
	}: Props = $props();

	const trimTo = $derived(startDate ? overlapTrimDate(startDate) : '');
	const canTrim = $derived(canTrimOverlap(overlapping, startDate));
	const fmtDay = (iso: string) =>
		parseISO(iso).toLocaleDateString(activeFormatLocale(), { dateStyle: 'medium' });
	const message = $derived(
		m('planEditor.overlapMessage', {
			plans: overlapping
				.map((p) =>
					m('planEditor.overlapPlanItem', {
						name: p.name,
						start: fmtDay(p.start_date),
						end: fmtDay(p.end_date)
					})
				)
				.join(', ')
		}) + (canTrim ? '' : ' ' + m('planEditor.overlapNoTrim'))
	);
	const trimLabel = $derived(
		overlapping.length === 1
			? m('planEditor.overlapTrimOne', { name: overlapping[0].name, date: trimTo ? fmtDay(trimTo) : '' })
			: m('planEditor.overlapTrimMany', { date: trimTo ? fmtDay(trimTo) : '' })
	);
</script>

<ConfirmDialog
	open={overlapping.length > 0}
	title={m('planEditor.overlapTitle')}
	{message}
	confirmLabel={m('planEditor.replacePlan')}
	cancelLabel={m('common.cancel')}
	altLabel={canTrim ? trimLabel : undefined}
	onalt={canTrim ? () => onchoose('trim') : undefined}
	danger={true}
	onconfirm={() => onchoose('replace')}
	{oncancel}
	data-testid={testId}
/>
