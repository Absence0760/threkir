<script lang="ts">
	/// A derived metric's name, with its plain-English definition one tap or
	/// one keypress away (#902 §1). The definition comes from the registry in
	/// `lib/metrics/metric_registry.ts`, and `metric_label_guard.test.ts` fails
	/// the unit job when a registered name renders anywhere but through here.
	///
	/// A toggletip, not a tooltip. The trigger is a real button, so touch and
	/// keyboard both open it; the definition is written into a live region that
	/// was mounted before it, so a screen reader announces it (decisions § 736);
	/// Escape closes it and returns focus, an outside press closes it without
	/// taking focus back, the same contract as `InfoTip` (decisions § 1622).
	///
	/// The panel goes to the top layer through the Popover API where the
	/// browser has it. These names sit in table headers inside horizontally
	/// scrolling wrappers and in cards that lift on hover, and an absolutely
	/// positioned panel is clipped by the first and dragged by the second. It
	/// stays in the DOM beside its trigger either way, so reading order, focus
	/// order and the live region are the same with or without the API.
	import { untrack } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
	import { METRICS, splitAtTerm, type MetricEntry, type MetricId } from '$lib/metrics/metric_registry';
	import { metricName } from '$lib/metrics/metric_name';

	interface Props {
		metric: MetricId;
		/// A second spelling of the name, from the entry's `variants`.
		variant?: string;
		/// The name alone, for a site inside a control that cannot hold a
		/// second one. The guard requires an interactive label for the same
		/// metric elsewhere in the same file, so the definition stays reachable.
		plain?: boolean;
		/// A catalogue sentence from the entry's `sentences`; the name renders
		/// where its `{term}` placeholder sits.
		sentence?: MessageKey;
		params?: Record<string, string | number>;
		/// The id of the input this name captions. The name then renders as that
		/// input's `<label>`, with the disclosure beside the label rather than
		/// inside it, where it would take the label's click and its name.
		labelFor?: string;
	}
	let { metric, variant, plain = false, sentence, params, labelFor }: Props = $props();

	const entry: MetricEntry = $derived(METRICS[metric]);
	const name = $derived(metricName(metric, variant, params));
	const parts = $derived(sentence ? splitAtTerm(m(sentence, params)) : null);

	const uid = $props.id();
	let open = $state(false);
	let trigger: HTMLButtonElement | null = $state(null);
	let panel: HTMLSpanElement | null = $state(null);

	const GAP_PX = 6;
	const EDGE_PX = 8;

	function supportsPopover(el: HTMLElement): boolean {
		return typeof el.showPopover === 'function';
	}

	function place() {
		if (!trigger || !panel) return;
		const anchor = trigger.getBoundingClientRect();
		const box = panel.getBoundingClientRect();
		const rtl = getComputedStyle(trigger).direction === 'rtl';
		let top = anchor.bottom + GAP_PX;
		if (top + box.height > innerHeight - EDGE_PX && anchor.top - GAP_PX - box.height >= EDGE_PX) {
			top = anchor.top - GAP_PX - box.height;
		}
		const start = rtl ? anchor.right - box.width : anchor.left;
		const left = Math.min(Math.max(start, EDGE_PX), Math.max(EDGE_PX, innerWidth - box.width - EDGE_PX));
		panel.style.top = `${Math.round(top)}px`;
		panel.style.left = `${Math.round(left)}px`;
	}

	function close(returnFocus: boolean) {
		if (!open) return;
		open = false;
		if (returnFocus) trigger?.focus();
	}

	function toggle(e: MouseEvent) {
		// A label can sit inside a card that is itself a link; the press is for
		// the definition, not a navigation.
		e.preventDefault();
		e.stopPropagation();
		open = !open;
	}

	function onDocPointer(e: PointerEvent) {
		const target = e.target as Node | null;
		if (panel?.contains(target) || trigger?.contains(target)) return;
		close(false);
	}

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') {
			e.preventDefault();
			close(true);
		}
	}

	// The listeners live only while the panel is open, and the effect's
	// teardown removes them on close and on unmount alike. An `onDestroy` would
	// also run in the server renderer, where there is no `document`, and throw
	// on every server-rendered page that shows a metric name.
	$effect(() => {
		if (!open || !panel) return;
		if (supportsPopover(panel) && !panel.matches(':popover-open')) panel.showPopover();
		untrack(place);
		document.addEventListener('pointerdown', onDocPointer, true);
		document.addEventListener('keydown', onKeydown);
		addEventListener('scroll', place, { capture: true, passive: true });
		addEventListener('resize', place, { passive: true });
		return () => {
			document.removeEventListener('pointerdown', onDocPointer, true);
			document.removeEventListener('keydown', onKeydown);
			removeEventListener('scroll', place, true);
			removeEventListener('resize', place);
		};
	});
</script>

{#snippet text()}{#if labelFor}<label class="metric-caption" for={labelFor}>{name}</label>{:else}{name}{/if}{/snippet}

{#snippet label()}
	{#if plain}
		<span class="metric-label" data-metric={metric}>{@render text()}</span>
	{:else}
		<span class="metric-label" data-metric={metric}
			>{@render text()}<button
				bind:this={trigger}
				type="button"
				class="metric-info"
				aria-label={m('metricLabel.about', { name })}
				aria-expanded={open}
				aria-controls={uid}
				data-testid="metric-info-{metric}"
				onclick={toggle}
			>
				<span class="material-symbols" aria-hidden="true">info</span>
			</button><span id={uid} class="metric-live" role="status"
				>{#if open}<span
						bind:this={panel}
						class="metric-definition"
						popover="manual"
						data-testid="metric-definition-{metric}">{m(entry.definition)}</span
					>{/if}</span
			></span
		>
	{/if}
{/snippet}

{#if parts}{parts.before}{@render label()}{parts.after}{:else}{@render label()}{/if}

<style>
	.metric-label {
		display: inline;
	}

	/* A form layer styles every <label> as a stacked field; this one is a
	   caption inside a line and keeps whatever its container sets. */
	.metric-caption {
		display: inline;
		margin: 0;
		font: inherit;
		color: inherit;
		letter-spacing: inherit;
		text-transform: inherit;
	}

	.metric-info {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		vertical-align: middle;
		/* The negative block margin keeps a micro-label's line box the height it
		   was, so adding the disclosure does not push a tile's value down. */
		min-width: var(--tap-target-inline-min);
		min-height: var(--tap-target-inline-min);
		margin-block: -8px;
		margin-inline: 1px -6px;
		padding: 0;
		border: none;
		border-radius: 50%;
		background: transparent;
		color: var(--color-text-tertiary);
		cursor: pointer;
		transition:
			background var(--transition-fast),
			color var(--transition-fast);
	}
	.metric-info:hover,
	.metric-info[aria-expanded='true'] {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.metric-info:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.metric-info .material-symbols {
		font-size: 0.95rem;
	}

	/* Every inherited typographic property is reset: the name usually sits in
	   an uppercase, tracked micro-label, and the definition is a sentence. */
	.metric-definition {
		position: fixed;
		inset: auto;
		margin: 0;
		z-index: 70;
		display: block;
		box-sizing: border-box;
		width: max-content;
		max-width: min(20rem, calc(100vw - 16px));
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-lg);
		font-size: 0.85rem;
		font-weight: 400;
		font-style: normal;
		line-height: 1.45;
		letter-spacing: normal;
		text-transform: none;
		text-align: start;
		white-space: normal;
		overflow-wrap: anywhere;
	}

	@media print {
		.metric-info,
		.metric-definition {
			display: none;
		}
	}
</style>
