<script lang="ts">
	import { beforeNavigate, goto } from '$app/navigation';
	import ConfirmDialog from './ConfirmDialog.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { leaveDecision } from '#lib/core/leave_guard.ts';

	interface Props {
		/// Probed when a navigation is attempted, never sampled at build time —
		/// see `trackDirty` in #lib/core/form_dirty.
		isDirty: () => boolean;
		/// Surface-specific replacement for the generic "leave without saving?"
		/// body (e.g. a builder that says what is about to be thrown away).
		message?: string;
		/// True while a create or save is on the wire. Leaving then is refused
		/// with a toast rather than offered as a discard, so a create never
		/// finishes out of sight (twin of mobile's `DiscardGuard.isBusy`,
		/// decisions § 2500). Probed like `isDirty`.
		isBusy?: () => boolean;
	}

	let { isDirty, message, isBusy }: Props = $props();

	function probe(fn: (() => boolean) | undefined, what: string): boolean {
		if (!fn) return false;
		try {
			return fn();
		} catch (e) {
			// A throwing probe must never trap the user on the page: the callback
			// runs inside SvelteKit's navigation path, so an escaping error would
			// break navigation app-wide rather than just this guard.
			console.error(`unsaved-changes ${what} probe failed`, e);
			return false;
		}
	}

	let pending = $state<{ href: string; external: boolean; delta: number | null } | null>(null);
	let leaving = false;

	beforeNavigate((nav) => {
		const decision = leaveDecision({
			leaving,
			busy: !leaving && probe(isBusy, 'busy'),
			dirty: !leaving && probe(isDirty, 'dirty'),
			unload: nav.type === 'leave',
		});
		if (decision === 'allow') return;

		nav.cancel();
		// A 'leave' navigation IS the browser's beforeunload — SvelteKit's own
		// listener turns this cancel() into preventDefault() + returnValue, and
		// the browser owns the dialog text, so there is nothing to render and no
		// custom copy to show. Cancelling only while dirty or busy is also what
		// keeps a clean form from paying the engagement penalty browsers apply
		// to a permanently-armed beforeunload handler.
		if (decision === 'browser') return;
		if (decision === 'busy') {
			showToast(m('common.unsavedBusy'), 'info');
			return;
		}

		pending = {
			href: nav.to?.url.href ?? '/',
			external: nav.willUnload,
			delta: nav.type === 'popstate' ? nav.delta : null,
		};
	});

	async function leave() {
		const target = pending;
		pending = null;
		if (!target) return;
		leaving = true;
		// A cancelled popstate was undone by SvelteKit with history.go(-delta),
		// so replaying the delta lands on the entry the user asked for instead
		// of pushing a forward duplicate of it.
		if (target.delta != null) history.go(target.delta);
		else if (target.external) location.href = target.href;
		else await goto(target.href);
	}
</script>

<ConfirmDialog
	open={pending !== null}
	data-testid="unsaved-changes-dialog"
	title={m('common.unsavedTitle')}
	message={message ?? m('common.unsavedBody')}
	confirmLabel={m('common.discard')}
	danger
	onconfirm={leave}
	oncancel={() => (pending = null)}
/>
