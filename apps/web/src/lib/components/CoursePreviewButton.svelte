<script lang="ts">
	import type { PathPoint } from '#lib/routes/flyover_path.ts';
	import { hasPreviewableCourse } from '#lib/routes/course_preview_points.ts';
	import { getUnit } from '#lib/format/units.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';

	let {
		points,
		title,
		climbNames = [],
		noiseBandM,
		replay = false,
	}: {
		points: PathPoint[];
		title: string;
		climbNames?: { dM: number; name: string }[];
		noiseBandM?: number;
		replay?: boolean;
	} = $props();

	// The dialog carries the 3D map engine, so it loads on the first click
	// rather than in the page's own chunk. The button stays enabled while it
	// loads: disabling it would drop focus to the body, and the dialog
	// returns focus to whatever held it when it opened.
	let CoursePreview3D = $state<typeof import('#lib/components/CoursePreview3D.svelte').default | null>(null);
	let open = $state(false);
	let loading = $state(false);

	const available = $derived(hasPreviewableCourse(points));

	async function openPreview() {
		if (loading) return;
		if (!CoursePreview3D) {
			loading = true;
			try {
				CoursePreview3D = (await import('#lib/components/CoursePreview3D.svelte')).default;
			} catch (e) {
				console.error('course preview failed to load', e);
				showToast(m('coursePreview.mapFailed'), 'error');
				return;
			} finally {
				loading = false;
			}
		}
		open = true;
	}
</script>

{#if available}
	<button
		type="button"
		class="btn btn-outline btn-sm"
		data-testid="course-preview-open"
		aria-haspopup="dialog"
		aria-busy={loading}
		onclick={openPreview}
	>
		<span class="material-symbols" aria-hidden="true">terrain</span>
		{replay ? m('coursePreview.replay') : m('coursePreview.open')}
	</button>
	{#if CoursePreview3D}
		<CoursePreview3D
			{open}
			{points}
			{title}
			{climbNames}
			{noiseBandM}
			unit={getUnit()}
			onclose={() => (open = false)}
		/>
	{/if}
{/if}
