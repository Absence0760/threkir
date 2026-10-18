<script lang="ts">
	import { initial, hashHue, seedBackground, seedForeground } from '#lib/format/avatar.ts';
	import { PUBLIC_SUPABASE_URL } from '$app/env/public';
	import { clubLogoSrc } from '#lib/social/club_logo.ts';

	let {
		club,
		size,
		font,
	}: {
		club: { id: string; name: string | null; avatar_url?: string | null };
		size: string;
		font: string;
	} = $props();

	const safeUrl = $derived(clubLogoSrc(club.avatar_url, PUBLIC_SUPABASE_URL));
	const hue = $derived(hashHue(club.id));
</script>

<span
	class="club-avatar"
	style="--cav-size: {size}; --cav-font: {font}; --cav-bg: {seedBackground(hue)}; --cav-fg: {seedForeground(hue)};"
	aria-hidden="true"
	data-testid="club-avatar"
	data-has-logo={safeUrl ? 'true' : 'false'}
>
	{#if safeUrl}
		<img src={safeUrl} alt="" />
	{:else}
		{initial(club.name)}
	{/if}
</span>

<style>
	.club-avatar {
		width: var(--cav-size);
		height: var(--cav-size);
		flex-shrink: 0;
		border-radius: 50%;
		background: var(--cav-bg);
		color: var(--cav-fg);
		display: grid;
		place-items: center;
		font-weight: 700;
		font-size: var(--cav-font);
		overflow: hidden;
	}
	.club-avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
</style>
