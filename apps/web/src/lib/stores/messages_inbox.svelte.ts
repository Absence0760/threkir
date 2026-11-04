/**
 * The Messages inbox list, shared by the `/messages` layout (which renders
 * it) and the conversation pages under it (which zero a thread's badge when
 * they mark it read, and refresh the list after a send or an unsend).
 *
 * It holds two independent reads. The direct-message conversations come from
 * `dm_threads()`. The AI Coach row is decided separately (decisions § 2227):
 * off unless the deploy has the Coach on, placed by the runner's
 * `messages_coach_row` setting, and carrying a preview of the newest Coach
 * message only once the runner has consented to the Coach — without that
 * consent `coach_messages` is not read at all, so the row says what the Coach
 * is and nothing it said.
 */
import { SvelteMap } from 'svelte/reactivity';

import { coachEnabled } from '#lib/coach/coach_flag.ts';
import {
	AI_DISCLOSURE_VERSION_COACH,
	aiDisclosureFromProfileRow,
	checkAiDisclosure,
} from '#lib/core/ai_disclosure.ts';
import {
	fetchDmThreads,
	fetchLatestCoachMessage,
	hideDmConversation,
	setDmConversationArchived,
	setDmConversationMuted,
	type DmThread,
	type LatestCoachMessage,
} from '#lib/core/data.ts';
import { supabase } from '#lib/core/supabase.ts';
import { deferDestructive } from '#lib/stores/undo.svelte.ts';
import { dmUnreadStore } from '#lib/stores/dm_unread.svelte.ts';
import { dmPendingHides } from '#lib/stores/dm_pending_hides.svelte.ts';
import { effective, loadSettings, updateUniversal } from '#lib/settings/settings.ts';
import { dmThreadRouteId } from '#lib/social/dm_thread.ts';
import {
	conversationWriteKey,
	overlayConversationWrites,
	revertConversationFlag,
	settledConversationWrites,
	type ConversationFlag,
	type ConversationWrite,
} from '#lib/social/dm_conversation_writes.ts';
import {
	MESSAGES_COACH_ROW_KEY,
	parseCoachInboxPlacement,
	type CoachInboxPlacement,
} from '#lib/social/messages_inbox.ts';

export interface CoachInboxState {
	placement: CoachInboxPlacement;
	/// The runner has accepted the Coach disclosure. False on a failed read.
	consented: boolean;
	/// The newest Coach message, read only when `consented`.
	latest: LatestCoachMessage | null;
}

class MessagesInboxStore {
	threads = $state<DmThread[]>([]);
	threadsError = $state(false);
	/// Null while unknown and whenever the Coach is off for this deploy.
	coach = $state<CoachInboxState | null>(null);
	/// The inbox is showing its Archived list.
	showingArchived = $state(false);

	#userId: string | null = null;
	#polling = false;
	#coachGeneration = 0;
	/// When each conversation was last marked read. A list fetch that started
	/// before that answers with the count from before the mark, and assigning
	/// it as-is put the badge back on the conversation just opened.
	#markedReadAt = new Map<string, number>();
	/// The runner's mute / archive writes a list read may predate
	/// (dm_conversation_writes.ts), keyed by conversation and flag. Reactive,
	/// because a conversation the list has not loaded reads its state here.
	#writes = new SvelteMap<string, ConversationWrite>();

	/// Binds the store to the signed-in runner, dropping what another account
	/// left behind. Returns true when the user changed.
	bind(userId: string | null): boolean {
		if (userId === this.#userId) return false;
		this.#userId = userId;
		this.threads = [];
		this.threadsError = false;
		this.coach = null;
		this.showingArchived = false;
		this.#markedReadAt.clear();
		dmPendingHides.clear();
		this.#writes.clear();
		this.#coachGeneration++;
		return true;
	}

	#apply(rows: DmThread[], startedAt: number) {
		const visible = overlayConversationWrites(
			rows.filter((t) => !dmPendingHides.has(t.conversationId)),
			this.#writes.values(),
			startedAt,
		);
		for (const w of settledConversationWrites(this.#writes.values(), startedAt)) {
			this.#writes.delete(conversationWriteKey(w.conversationId, w.flag));
		}
		this.threads = visible.map((t) =>
			(this.#markedReadAt.get(dmThreadRouteId(t)) ?? -Infinity) >= startedAt ? { ...t, unread: 0 } : t,
		);
	}

	async loadThreads() {
		this.threadsError = false;
		const startedAt = Date.now();
		try {
			this.#apply(await fetchDmThreads(), startedAt);
		} catch {
			this.threadsError = true;
		}
	}

	/// A failed poll keeps the list it has and logs: the next tick is the
	/// retry, and a banner every 30 s would be noise. A list that never loaded
	/// retries through loadThreads so its error state can clear.
	async poll() {
		if (this.#polling) return;
		if (this.threadsError) return this.loadThreads();
		this.#polling = true;
		const startedAt = Date.now();
		try {
			this.#apply(await fetchDmThreads(), startedAt);
		} catch (e) {
			console.warn('messages inbox poll failed', e);
		} finally {
			this.#polling = false;
		}
		await this.refreshCoachPreview();
	}

	/// After a send or an unsend. The write already renders in the thread, so
	/// a failed list read leaves the previews as they were.
	async refreshThreads() {
		const startedAt = Date.now();
		try {
			this.#apply(await fetchDmThreads(), startedAt);
		} catch {
			// Corrected by the next poll.
		}
	}

	#patch(conversationId: string, change: Partial<DmThread>) {
		this.threads = this.threads.map((t) => (t.conversationId === conversationId ? { ...t, ...change } : t));
	}

	/// The runner's latest mute / archive write to a conversation, until a list
	/// read carries it. The open conversation reads this when its row is not in
	/// the list — a deep link before the inbox loaded, or a list read that
	/// failed — so the toggle shows what was just written instead of `false`.
	writtenFlag(conversationId: string, flag: ConversationFlag): boolean | undefined {
		return this.#writes.get(conversationWriteKey(conversationId, flag))?.value;
	}

	/// Mutes or unmutes at once: both are one tap back. A refused write puts
	/// the flag back and rethrows for the caller to report.
	setMuted(conversationId: string, muted: boolean) {
		return this.#setFlag(conversationId, 'muted', muted, setDmConversationMuted);
	}

	/// Archives or unarchives at once; the conversation moves between the
	/// inbox and the Archived list, where Unarchive is one tap away.
	setArchived(conversationId: string, archived: boolean) {
		return this.#setFlag(conversationId, 'archived', archived, setDmConversationArchived);
	}

	/// The write is held in #writes until a list read carries it, so a poll
	/// that started before it landed cannot flip the toggle back. A refusal
	/// reverts that one field on that one row: restoring a snapshot of the
	/// whole list would also undo whatever a poll brought in meanwhile.
	async #setFlag(
		conversationId: string,
		flag: ConversationFlag,
		value: boolean,
		write: (conversationId: string, value: boolean) => Promise<void>,
	) {
		const key = conversationWriteKey(conversationId, flag);
		const prior = this.threads.find((t) => t.conversationId === conversationId)?.[flag];
		const pending: ConversationWrite = { conversationId, flag, value, at: Infinity };
		this.#writes.set(key, pending);
		this.#patch(conversationId, { [flag]: value });
		try {
			await write(conversationId, value);
		} catch (e) {
			if (this.#writes.get(key) === pending) this.#writes.delete(key);
			if (prior !== undefined) {
				this.threads = revertConversationFlag(this.threads, conversationId, flag, prior);
			} else {
				void this.refreshThreads();
			}
			throw e;
		}
		if (this.#writes.get(key) === pending) this.#writes.set(key, { ...pending, at: Date.now() });
		// A row the list did not have is read now, so the conversation joins the
		// list with the state just written.
		if (prior === undefined) void this.refreshThreads();
		void dmUnreadStore.refresh();
	}

	/// Deletes a conversation for the runner, held behind the undo window
	/// (conventions.md § Destructive actions): the row leaves the list now and
	/// the server is told only when the window closes, so Undo cancels a timer.
	/// `onRestore` lets the open conversation pane come back with the row.
	hide(conversationId: string, opts: { message: string; onCommitError: (e: unknown) => void; onRestore?: () => void }) {
		const before = this.threads;
		dmPendingHides.add(conversationId);
		this.threads = this.threads.filter((t) => t.conversationId !== conversationId);
		deferDestructive({
			message: opts.message,
			commit: async () => {
				try {
					await hideDmConversation(conversationId);
					// Hidden on the server now: drop it from the held count so the
					// badge does not count it again before the read below lands.
					dmUnreadStore.forget(conversationId);
				} finally {
					dmPendingHides.delete(conversationId);
				}
				void dmUnreadStore.refresh();
			},
			// Undo, or a refused commit: the badge dropped the conversation on
			// the delete and re-reads now, the server being what knows.
			restore: () => {
				dmPendingHides.delete(conversationId);
				this.threads = before;
				opts.onRestore?.();
				void dmUnreadStore.refresh();
			},
			// restore() has already put the row back; the list read brings in
			// anything that arrived during the window.
			onCommitError: (e) => {
				opts.onCommitError(e);
				void this.refreshThreads();
			},
		});
	}

	markRead(routeId: string) {
		this.#markedReadAt.set(routeId, Date.now());
		this.threads = this.threads.map((t) => (dmThreadRouteId(t) === routeId ? { ...t, unread: 0 } : t));
	}

	/// Decides the Coach row. Each step fails toward showing less: a failed
	/// consent read is no consent, so nothing the Coach said is read.
	async loadCoach() {
		const userId = this.#userId;
		const generation = ++this.#coachGeneration;
		if (!userId || !coachEnabled()) {
			this.coach = null;
			return;
		}
		let placement: CoachInboxPlacement = 'pinned';
		try {
			placement = parseCoachInboxPlacement(
				effective(await loadSettings(userId), MESSAGES_COACH_ROW_KEY),
			);
		} catch (e) {
			console.warn('messages inbox: settings read failed', e);
		}
		let consented = false;
		try {
			const { data, error } = await supabase
				.rpc('get_my_profile', undefined, { get: true })
				.maybeSingle();
			if (error) throw new Error(error.message);
			consented = checkAiDisclosure(aiDisclosureFromProfileRow(data), AI_DISCLOSURE_VERSION_COACH).ok;
		} catch (e) {
			console.warn('messages inbox: AI consent read failed', e);
		}
		let latest: LatestCoachMessage | null = null;
		if (consented && placement !== 'hidden') {
			try {
				latest = await fetchLatestCoachMessage();
			} catch (e) {
				console.warn('messages inbox: latest coach message read failed', e);
			}
		}
		if (generation !== this.#coachGeneration) return;
		this.coach = { placement, consented, latest };
	}

	/// Re-reads the preview only; placement and consent stand until the next
	/// full load.
	async refreshCoachPreview() {
		const coach = this.coach;
		if (!coach || !coach.consented || coach.placement === 'hidden') return;
		const generation = this.#coachGeneration;
		try {
			const latest = await fetchLatestCoachMessage();
			if (generation === this.#coachGeneration && this.coach) this.coach = { ...this.coach, latest };
		} catch (e) {
			console.warn('messages inbox: coach preview refresh failed', e);
		}
	}

	/// Saves the runner's choice and shows it at once. A refused write puts
	/// the row back where it was and rethrows for the caller to report.
	async setCoachPlacement(next: CoachInboxPlacement) {
		const userId = this.#userId;
		const before = this.coach;
		if (!userId || !before) return;
		this.#coachGeneration++;
		this.coach = { ...before, placement: next };
		try {
			await updateUniversal(userId, { [MESSAGES_COACH_ROW_KEY]: next });
		} catch (e) {
			this.coach = before;
			throw e;
		}
		if (before.placement === 'hidden') await this.refreshCoachPreview();
	}
}

export const messagesInbox = new MessagesInboxStore();
