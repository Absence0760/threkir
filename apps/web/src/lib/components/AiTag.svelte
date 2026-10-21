<script lang="ts">
	// EU AI Act Art. 50: on every Coach message, not only the first (§ 2227).
	import { m } from '#lib/i18n/store.svelte.ts';
</script>

<span class="ai-tag" data-testid="ai-tag"
	><span aria-hidden="true">{m('messages.aiTag')}</span><span class="visually-hidden"
		>{m('messages.aiTagSr')}</span
	></span
>

<style>
	.ai-tag {
		display: inline-flex;
		align-items: center;
		flex: 0 0 auto;
		padding: 0 0.35rem;
		border-radius: 999px;
		border: 1px solid var(--color-border);
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.04em;
		line-height: 1.5;
	}
</style>
