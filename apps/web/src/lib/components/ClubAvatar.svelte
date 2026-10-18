<script lang="ts">
	import Avatar from '#lib/components/Avatar.svelte';
	import { hashHue } from '#lib/format/avatar.ts';
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

	const logoSrc = (url: string | null | undefined) => clubLogoSrc(url, PUBLIC_SUPABASE_URL);
	const hasLogo = $derived(logoSrc(club.avatar_url) !== '');
</script>

<Avatar
	url={club.avatar_url ?? null}
	name={club.name}
	{size}
	{font}
	bg="seed"
	seedHue={hashHue(club.id)}
	sanitize={logoSrc}
	data-testid="club-avatar"
	data-has-logo={hasLogo ? 'true' : 'false'}
/>
