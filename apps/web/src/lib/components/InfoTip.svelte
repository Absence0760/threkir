<script lang="ts">
	/// The small "(i)" a runner taps to find out what a feature IS and how to
	/// use it, without leaving the surface it sits on.
	///
	/// Deliberately a disclosure and not a `title=` tooltip: a native tooltip
	/// never appears on touch, which is where most of this app is read, and it
	/// cannot hold the "how to use it" sentence or a link to the guide.
	///
	/// Every string arrives translated — the component takes no message keys, so
	/// it can sit on a surface whose copy lives in a catalogue it knows nothing
	/// about.
	import { onDestroy, onMount } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';

	interface Props {
		/// Accessible name for the trigger. Must name the SUBJECT ("About
		/// Strava sync"), never just "info" — a screen-reader user meeting six
		/// of these on one page cannot tell them apart otherwise.
		label: string;
		title: string;
		/// What the feature is, then how to use it. One or more paragraphs.
		body: string | string[];
		/// Optional deep link to the fuller guide.
		learnHref?: string;
		learnLabel?: string;
		testId?: string;
	}
	let { label, title, body, learnHref, learnLabel, testId }: Props = $props();

	let open = $state(false);
	let trigger: HTMLButtonElement | null = $state(null);
	let panel: HTMLDivElement | null = $state(null);

	const paragraphs = $derived(Array.isArray(body) ? body : [body]);
	const panelId = `info-tip-${Math.random().toString(36).slice(2, 9)}`;

	function close(returnFocus: boolean) {
		if (!open) return;
		open = false;
		if (returnFocus) trigger?.focus();
	}

	function onDocPointer(e: MouseEvent) {
		if (!open) return;
		const target = e.target as Node | null;
		if (panel?.contains(target ?? null) || trigger?.contains(target ?? null)) return;
		// No focus return on a click elsewhere: the runner has already moved
		// their attention, and yanking focus back would fight the click.
		close(false);
	}

	function onKeydown(e: KeyboardEvent) {
		if (open && e.key === 'Escape') {
			e.preventDefault();
			close(true);
		}
	}

	onMount(() => {
		document.addEventListener('mousedown', onDocPointer);
		document.addEventListener('keydown', onKeydown);
	});
	onDestroy(() => {
		document.removeEventListener('mousedown', onDocPointer);
		document.removeEventListener('keydown', onKeydown);
	});
</script>

<span class="info-tip">
	<button
		bind:this={trigger}
		type="button"
		class="info-tip-trigger"
		aria-label={label}
		aria-expanded={open}
		aria-controls={panelId}
		data-testid={testId}
		onclick={() => (open = !open)}
	>
		<span class="material-symbols" aria-hidden="true">info</span>
	</button>

	{#if open}
		<div
			bind:this={panel}
			id={panelId}
			class="info-tip-panel"
			role="group"
			aria-label={title}
			data-testid={testId ? `${testId}-panel` : undefined}
		>
			<div class="info-tip-head">
				<h4>{title}</h4>
				<button
					type="button"
					class="info-tip-close"
					aria-label={m('modal.close')}
					onclick={() => close(true)}
				>
					<span class="material-symbols" aria-hidden="true">close</span>
				</button>
			</div>
			{#each paragraphs as paragraph (paragraph)}
				<p>{paragraph}</p>
			{/each}
			{#if learnHref && learnLabel}
				<a class="info-tip-learn" href={learnHref}>{learnLabel}</a>
			{/if}
		</div>
	{/if}
</span>

<style>
	.info-tip {
		position: relative;
		display: inline-flex;
		vertical-align: middle;
	}

	.info-tip-trigger {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		/* 2.25rem square rather than the icon's own size: this is a primary
		   touch target on a card a new runner is meant to reach for. */
		width: 2.25rem;
		height: 2.25rem;
		padding: 0;
		border: none;
		border-radius: 50%;
		background: transparent;
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: background var(--transition-fast), color var(--transition-fast);
	}
	.info-tip-trigger:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.info-tip-trigger:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.info-tip-trigger .material-symbols {
		font-size: 1.15rem;
	}

	.info-tip-panel {
		position: absolute;
		top: calc(100% + 0.35rem);
		inset-inline-start: 0;
		z-index: 60;
		width: max-content;
		/* Bounded on BOTH axes against the viewport, not just on max-width:
		   the panel is anchored inside cards that sit near the right edge at
		   phone widths, where a fixed 22rem would push the page into a
		   horizontal scroll. */
		max-width: min(22rem, calc(100vw - 2rem));
		padding: var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-lg);
		text-align: start;
	}

	.info-tip-head {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		margin-bottom: var(--space-xs);
	}

	.info-tip-panel h4 {
		flex: 1;
		margin: 0;
		font-size: 0.9rem;
		font-weight: 700;
		color: var(--color-text);
	}

	.info-tip-close {
		flex: none;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.75rem;
		height: 1.75rem;
		margin: -0.25rem -0.25rem 0 0;
		padding: 0;
		border: none;
		border-radius: 50%;
		background: transparent;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.info-tip-close:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.info-tip-close:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.info-tip-close .material-symbols {
		font-size: 1rem;
	}

	.info-tip-panel p {
		margin: 0 0 var(--space-xs);
		font-size: 0.85rem;
		line-height: 1.5;
		color: var(--color-text-secondary);
		white-space: normal;
	}
	.info-tip-panel p:last-of-type {
		margin-bottom: 0;
	}

	.info-tip-learn {
		display: inline-block;
		margin-top: var(--space-sm);
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-primary);
	}
</style>
