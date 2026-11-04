<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';

	/// The dashboard's occasional jobs, adding a run after the fact and
	/// importing history, behind one labelled menu button at the top of the
	/// page rather than as two buttons on every visit's week lead
	/// (decisions § 2281). Same ARIA menu-button shape as the /history Log
	/// menu: arrow keys, Home / End, Escape back to the trigger.

	let open = $state(false);
	let trigger = $state<HTMLButtonElement | null>(null);
	let panel = $state<HTMLDivElement | null>(null);

	function items(): HTMLAnchorElement[] {
		return panel
			? Array.from(panel.querySelectorAll<HTMLAnchorElement>('[role="menuitem"]'))
			: [];
	}

	function focusItem(i: number) {
		const all = items();
		if (all.length === 0) return;
		all[(i + all.length) % all.length]?.focus();
	}

	async function toggle() {
		open = !open;
		if (open) {
			await tick();
			focusItem(0);
		}
	}

	function onPanelKeydown(e: KeyboardEvent) {
		const all = items();
		const cur = all.indexOf(document.activeElement as HTMLAnchorElement);
		if (e.key === 'ArrowDown') {
			e.preventDefault();
			focusItem(cur + 1);
		} else if (e.key === 'ArrowUp') {
			e.preventDefault();
			focusItem(cur - 1);
		} else if (e.key === 'Home') {
			e.preventDefault();
			focusItem(0);
		} else if (e.key === 'End') {
			e.preventDefault();
			focusItem(all.length - 1);
		}
	}

	onMount(() => {
		function onDocPointer(e: MouseEvent) {
			if (!open) return;
			const target = e.target as Node | null;
			if (panel?.contains(target) || trigger?.contains(target)) return;
			open = false;
		}
		function onDocKeydown(e: KeyboardEvent) {
			if (open && e.key === 'Escape') {
				open = false;
				trigger?.focus();
			}
		}
		document.addEventListener('mousedown', onDocPointer);
		document.addEventListener('keydown', onDocKeydown);
		return () => {
			document.removeEventListener('mousedown', onDocPointer);
			document.removeEventListener('keydown', onDocKeydown);
		};
	});
</script>

<div class="dash-actions" data-testid="dash-actions">
	<button
		bind:this={trigger}
		type="button"
		class="btn btn-outline dash-actions-trigger"
		aria-haspopup="menu"
		aria-expanded={open}
		onclick={toggle}
		onkeydown={(e) => {
			if (!open && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
				e.preventDefault();
				void toggle();
			}
		}}
		data-testid="dash-actions-trigger"
	>
		<span class="material-symbols" aria-hidden="true">add</span>
		{m('dash.actionsMenu')}
		<span class="material-symbols caret" class:open aria-hidden="true">expand_more</span>
	</button>
	{#if open}
		<div
			bind:this={panel}
			class="dash-actions-panel"
			role="menu"
			tabindex="-1"
			aria-label={m('dash.actionsMenu')}
			onkeydown={onPanelKeydown}
		>
			<a class="dash-actions-item" role="menuitem" href="/runs/new" data-testid="dash-actions-add">
				<span class="material-symbols" aria-hidden="true">edit_note</span>{m('dash.addARun')}
			</a>
			<a
				class="dash-actions-item"
				role="menuitem"
				href="/settings/integrations"
				data-testid="dash-actions-import"
			>
				<span class="material-symbols" aria-hidden="true">upload_file</span>{m('dash.importFromStravaGarmin')}
			</a>
		</div>
	{/if}
</div>

<style>
	.dash-actions {
		position: relative;
		display: inline-flex;
	}
	.dash-actions-trigger .caret {
		transition: transform var(--transition-fast);
	}
	.dash-actions-trigger .caret.open {
		transform: rotate(180deg);
	}
	.dash-actions-panel {
		position: absolute;
		top: calc(100% + 0.3rem);
		inset-inline-end: 0;
		z-index: 60;
		min-width: 14rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-lg);
		padding: 0.25rem;
		display: flex;
		flex-direction: column;
		gap: 0.05rem;
	}
	.dash-actions-item {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		min-height: var(--tap-target-min);
		padding: 0 var(--space-sm);
		border-radius: var(--radius-sm);
		color: var(--color-text);
		font-size: 0.9rem;
		text-decoration: none;
	}
	.dash-actions-item:hover,
	.dash-actions-item:focus-visible {
		background: var(--color-bg-secondary);
		outline: none;
	}
	.dash-actions-item .material-symbols {
		font-size: 1.15rem;
		color: var(--color-text-secondary);
	}
</style>
