<!--
	"Official" mark on content published by a verified organiser: a route,
	plan, gym routine, challenge or session plan whose club is verified and
	whose author is an owner/admin of it. The flag is derived server-side
	(`is_official`, migration 20271021000030) and never stored per row; this
	is the official kind of `ProvenanceBadge`, kept as its own name for the
	content surfaces. Twin of the Flutter `OfficialBadge` widget.
-->
<script lang="ts">
	import ProvenanceBadge from '#lib/components/ProvenanceBadge.svelte';

	interface Props {
		size?: number;
		parkCourse?: boolean;
	}
	let { size = 14, parkCourse = false }: Props = $props();
</script>

<ProvenanceBadge kind="official" {size} {parkCourse} />
