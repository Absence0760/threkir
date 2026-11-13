<script lang="ts">
	import type { Snippet } from 'svelte';

	// One row of a settings-style list, the web twin of ui_kit's `ListRow`
	// (conventions.md § Web settings rows; issue #1374). Same three shapes:
	//
	// - `kind="nav"` opens another page: optional leading `icon`, a one-line
	//   `subtitle`, a chevron (or an open-in-new glyph when `external`).
	// - `kind="value"` opens a picker: the current `value` is the subtitle,
	//   with an optional second line of `hint`.
	// - `kind="toggle"` is a switch that applies at once: a checkbox with
	//   `role="switch"`, so it is announced as on / off and Space flips it.
	//
	// A nav or value row with no `href` and no `onclick`, or `disabled`,
	// renders disabled and is not a link or a button at all, so it is never a
	// tappable row that silently does nothing; say why in its subtitle.
	//
	// The toggle's accessible name is its `title` alone and its `subtitle` is
	// its description (`aria-describedby`), so a screen reader reads "Private
	// profile, switch, off" and then the explanation rather than one long
	// name. `describedby` adds the id of an explanation that lives elsewhere on
	// the page (a group's shared hint). A nav or value row's link is named by
	// what it shows, title then subtitle, as ui_kit's tile is. The whole row
	// is the click target.
	//
	// `info` is the "(i)" slot (an `InfoTip`): the caller builds it, since its
	// label is localised, and the row places it outside the link or label, so
	// it is never part of the row's name and its own click stays its own.
	let {
		kind,
		title,
		subtitle,
		value,
		hint,
		icon,
		href,
		onclick,
		external = false,
		disabled = false,
		checked = $bindable(false),
		onchange,
		describedby,
		info,
		testid,
		rowTestid,
		class: extra = '',
	}: {
		kind: 'nav' | 'value' | 'toggle';
		/// What the row is called. Settings search matches on it.
		title: string;
		/// A nav or toggle row's one-line description.
		subtitle?: string;
		/// A value row's current value, shown as its subtitle.
		value?: string;
		/// A value row's second line, under the value.
		hint?: string;
		/// A Material Symbols ligature for a nav or value row, decorative.
		icon?: string;
		href?: string;
		onclick?: () => void;
		/// A nav row that leaves the app: opens in a new tab.
		external?: boolean;
		disabled?: boolean;
		/// A toggle row's state; bindable.
		checked?: boolean;
		/// A toggle row's change, after `checked` has been updated.
		onchange?: (checked: boolean) => void;
		describedby?: string;
		info?: Snippet;
		/// On the control: the toggle's input, the nav or value row's link or
		/// button.
		testid?: string;
		/// On the row itself.
		rowTestid?: string;
		class?: string;
	} = $props();

	const uid = $props.id();
	const titleId = `${uid}-title`;
	const subId = `${uid}-sub`;
	const inputId = `${uid}-input`;

	const second = $derived(kind === 'value' ? value : subtitle);
	// The switch's description: its own subtitle, then any shared hint.
	const described = $derived([subtitle ? subId : null, describedby].filter(Boolean).join(' ') || undefined);
	const inert = $derived(disabled || (kind !== 'toggle' && !href && !onclick));
</script>

{#snippet texts()}
	<span class="lr-texts">
		<span class="lr-title" id={titleId}>{title}</span>
		{#if second}<span class="lr-subtitle" id={subId}>{second}</span>{/if}
		{#if kind === 'value' && hint}<span class="lr-hint" id="{uid}-hint">{hint}</span>{/if}
	</span>
{/snippet}

{#if kind === 'toggle'}
	<div class="list-row lr-toggle {extra}" class:lr-disabled={disabled} data-testid={rowTestid}>
		<label class="lr-hit" for={inputId}>
			{@render texts()}
		</label>
		{#if info}<span class="lr-info">{@render info()}</span>{/if}
		<input
			id={inputId}
			class="lr-switch"
			type="checkbox"
			role="switch"
			aria-labelledby={titleId}
			aria-describedby={described}
			{disabled}
			{checked}
			onchange={(e) => {
				checked = e.currentTarget.checked;
				onchange?.(checked);
			}}
			data-testid={testid}
		/>
	</div>
{:else}
	<div class="list-row lr-{kind} {extra}" class:lr-disabled={inert} data-testid={rowTestid}>
		{#if icon}<span class="material-symbols lr-icon" aria-hidden="true">{icon}</span>{/if}
		{#if inert}
			<span class="lr-hit" aria-disabled="true" data-testid={testid}>{@render texts()}</span>
		{:else if href}
			<a
				class="lr-hit lr-stretch"
				{href}
				target={external ? '_blank' : undefined}
				rel={external ? 'noopener noreferrer' : undefined}
				{onclick}
				data-testid={testid}
			>
				{@render texts()}
			</a>
		{:else}
			<button type="button" class="lr-hit lr-stretch" {onclick} data-testid={testid}>
				{@render texts()}
			</button>
		{/if}
		{#if info}<span class="lr-info">{@render info()}</span>{/if}
		<span class="material-symbols lr-chevron" aria-hidden="true">{external ? 'open_in_new' : 'chevron_right'}</span>
	</div>
{/if}


<style>
	.list-row {
		position: relative;
		display: flex;
		align-items: center;
		gap: var(--space-md);
		min-height: var(--tap-target-min);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.list-row:not(.lr-disabled):hover {
		background: var(--color-bg-secondary);
	}
	.lr-hit {
		flex: 1;
		min-width: 0;
		display: flex;
		align-items: center;
		cursor: pointer;
		color: inherit;
		text-decoration: none;
		font: inherit;
		text-align: start;
		background: none;
		border: 0;
		padding: 0;
	}
	/* The link or button covers the whole row, so a tap anywhere opens it;
	   the info slot sits above that layer and keeps its own click. */
	.lr-stretch {
		position: static;
	}
	.lr-stretch::after {
		content: '';
		position: absolute;
		inset: 0;
		border-radius: inherit;
	}
	.lr-stretch:focus-visible {
		outline: none;
	}
	.lr-stretch:focus-visible::after {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.lr-texts {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.lr-title {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.lr-subtitle,
	.lr-hint {
		font-size: 0.85rem;
		line-height: 1.45;
		color: var(--color-text-secondary);
		overflow-wrap: anywhere;
	}
	.lr-hint {
		font-size: 0.8rem;
	}
	.lr-icon {
		font-size: 1.4rem;
		color: var(--color-primary);
		flex-shrink: 0;
	}
	.lr-chevron {
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}
	.lr-info {
		position: relative;
		z-index: 1;
		flex-shrink: 0;
	}
	.lr-disabled {
		color: var(--color-text-tertiary);
	}
	.lr-disabled .lr-icon {
		color: var(--color-text-tertiary);
	}

	/* The switch: a native checkbox drawn as a track and thumb. The track's
	   edge is --color-border (WCAG 1.4.11's 3:1 against the surface) and the
	   on state fills with the primary colour, so state never rests on hue
	   alone: the thumb's side moves too. */
	.lr-switch {
		appearance: none;
		flex-shrink: 0;
		position: relative;
		width: 2.75rem;
		height: 1.5rem;
		margin: 0;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		background: var(--color-bg-tertiary);
		cursor: pointer;
		transition: background var(--transition-fast);
	}
	.lr-switch::before {
		content: '';
		position: absolute;
		top: 50%;
		inset-inline-start: 0.15rem;
		width: 1.1rem;
		height: 1.1rem;
		border-radius: 50%;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		transform: translateY(-50%);
		transition: inset-inline-start var(--transition-fast);
	}
	.lr-switch:checked {
		background: var(--color-primary);
		border-color: var(--color-primary);
	}
	.lr-switch:checked::before {
		inset-inline-start: calc(100% - 1.25rem);
		border-color: var(--color-primary);
	}
	.lr-switch:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.lr-switch:disabled {
		cursor: not-allowed;
		opacity: 0.55;
	}
	.lr-disabled .lr-hit {
		cursor: not-allowed;
	}
	@media (prefers-reduced-motion: reduce) {
		.lr-switch,
		.lr-switch::before {
			transition: none;
		}
	}
	@media (forced-colors: active) {
		.lr-switch {
			appearance: auto;
			width: auto;
			height: auto;
		}
		.lr-switch::before {
			content: none;
		}
	}
</style>
