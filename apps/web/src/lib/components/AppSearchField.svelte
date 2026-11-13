<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';

	// The one search field (issue #1374), the web twin of ui_kit's
	// `AppSearchField`: a search glyph, the field, and a clear button while
	// there is text, so clear is always there and always in the same place.
	// `page_chrome_guard.test.ts` fails a hand-built `type="search"` input anywhere
	// else. `label` is the accessible name; the placeholder repeats it unless
	// the caller says otherwise.
	let {
		value = $bindable(''),
		label,
		placeholder,
		clearLabel,
		oninput,
		id,
		describedby,
		testid,
		input = $bindable(null),
	}: {
		value?: string;
		label: string;
		placeholder?: string;
		clearLabel?: string;
		/// Also called with `''` when the clear button empties the field.
		oninput?: (value: string) => void;
		id?: string;
		describedby?: string;
		testid?: string;
		input?: HTMLInputElement | null;
	} = $props();

	function clear() {
		value = '';
		oninput?.('');
		input?.focus();
	}
</script>

<div class="app-search">
	<span class="material-symbols glyph" aria-hidden="true">search</span>
	<input
		bind:this={input}
		bind:value
		{id}
		type="search"
		autocomplete="off"
		enterkeyhint="search"
		placeholder={placeholder ?? label}
		aria-label={label}
		aria-describedby={describedby}
		data-testid={testid}
		oninput={() => oninput?.(value)}
	/>
	{#if value !== ''}
		<button
			type="button"
			class="clear"
			aria-label={clearLabel ?? m('filterBar.clearSearch')}
			title={clearLabel ?? m('filterBar.clearSearch')}
			data-testid={testid ? `${testid}-clear` : undefined}
			onclick={clear}
		>
			<span class="material-symbols" aria-hidden="true">close</span>
		</button>
	{/if}
</div>

<style>
	.app-search {
		position: relative;
		display: flex;
		align-items: center;
		flex: 1 1 12rem;
		min-width: 0;
	}
	.glyph {
		position: absolute;
		inset-inline-start: 0.75rem;
		font-size: 1.2rem;
		color: var(--color-text-secondary);
		pointer-events: none;
	}
	input {
		width: 100%;
		min-width: 0;
		min-height: var(--tap-target-min);
		padding-block: 0.6rem;
		padding-inline: 2.5rem var(--tap-target-min);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font: inherit;
		font-size: 0.95rem;
	}
	input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
		border-color: var(--color-primary);
	}
	/* The clear button below is the one clear; WebKit's own would be a second. */
	input::-webkit-search-cancel-button {
		appearance: none;
		display: none;
	}
	.clear {
		position: absolute;
		inset-inline-end: 0;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: var(--tap-target-min);
		height: var(--tap-target-min);
		border: none;
		border-radius: var(--radius-md);
		background: transparent;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.clear:hover {
		color: var(--color-text);
	}
	.clear:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: -2px;
	}
	.clear .material-symbols {
		font-size: 1.2rem;
	}
</style>
