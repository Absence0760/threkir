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
	acceptDmRequest,
	acceptGroupInvite,
	declineDmRequest,
	declineGroupInvite,
	fetchDmThreads,
	fetchGroupInvites,
	fetchGroupMessagesEnabled,
	fetchLatestCoachMessage,
	hideDmConversation,
	setDmConversationArchived,
	setDmConversationMuted,
	setDmConversationUnread,
	type DmThread,
	type GroupInvite,
	type LatestCoachMessage,
} from '#lib/core/data.ts';
import { supabase } from '#lib/core/supabase.ts';
import { deferDestructive } from '#lib/stores/undo.svelte.ts';
import { dmUnreadStore } from '#lib/stores/dm_unread.svelte.ts';
import { dmPendingHides } from '#lib/stores/dm_pending_hides.svelte.ts';
import { effective, loadSettings, updateUniversal } from '#lib/settings/settings.ts';
import { dmThreadRouteId } from '#lib/social/dm_thread.ts';
import {
	confirmedFlagValue,
	conversationWriteKey,
	dropRefusedWrite,
	overlayConversationWrites,
	restoreHiddenConversation,
	revertConversationFlag,
	settledConversationWrites,
	settledHides,
	settleLandedWrite,
	withoutHiddenConversations,
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

type HideOptions = {
	throughMessageId: string;
	message: string;
	onCommitError: (e: unknown) => void;
	onRestore?: () => void;
};

class MessagesInboxStore {
	threads = $state<DmThread[]>([]);
	threadsError = $state(false);
	/// Null while unknown and whenever the Coach is off for this deploy.
	coach = $state<CoachInboxState | null>(null);
	/// The inbox is showing its Archived list.
	showingArchived = $state(false);
	/// The inbox is showing its Requests list (message requests the runner
	/// has not answered, migration 20271115002384, and group invites).
	showingRequests = $state(false);
	/// Group conversations are on for this deploy (decisions § 2463). False
	/// until the server says otherwise, and while a failed read leaves it
	/// unknown: every group surface stays hidden rather than offering what the
	/// server refuses, and each poll reads the flag again until it answers.
	groupsEnabled = $state(false);
	/// The runner's live group invites, listed under Requests.
	invites = $state<GroupInvite[]>([]);

	#userId: string | null = null;
	#polling = false;
	#groupsGeneration = 0;
	/// The last flag read failed, so the next poll reads it again.
	#groupsUnknown = false;
	#coachGeneration = 0;
	/// When each conversation was last marked read. A list fetch that started
	/// before that answers with the count from before the mark, and assigning
	/// it as-is put the badge back on the conversation just opened.
	#markedReadAt = new Map<string, number>();
	/// The runner's mute / archive writes a list read may predate
	/// (dm_conversation_writes.ts), keyed by conversation and flag. Reactive,
	/// because a conversation the list has not loaded reads its state here.
	#writes = new SvelteMap<string, ConversationWrite>();
	/// When each deleted conversation's delete landed (`Infinity` while its
	/// undo window is open or the commit is in flight). A list read that
	/// started before the delete landed still lists the conversation, and
	/// one returning after the window closed put the row back until the next
	/// poll.
	#hiddenAt = new Map<string, number>();

	/// Binds the store to the signed-in runner, dropping what another account
	/// left behind. Returns true when the user changed.
	bind(userId: string | null): boolean {
		if (userId === this.#userId) return false;
		this.#userId = userId;
		this.threads = [];
		this.threadsError = false;
		this.coach = null;
		this.showingArchived = false;
		this.showingRequests = false;
		this.groupsEnabled = false;
		this.#groupsUnknown = false;
		this.invites = [];
		this.#groupsGeneration++;
		this.#markedReadAt.clear();
		this.#hiddenAt.clear();
		dmPendingHides.clear();
		this.#writes.clear();
		this.#coachGeneration++;
		return true;
	}

	/// `userId` is the account the read was made for: one that lands after the
	/// store was bound to another account is that account's list, not this one's.
	#apply(rows: DmThread[], startedAt: number, userId: string | null) {
		if (userId !== this.#userId) return;
		const visible = overlayConversationWrites(
			withoutHiddenConversations(rows, this.#hiddenAt, startedAt),
			this.#writes.values(),
			startedAt,
		);
		for (const id of settledHides(this.#hiddenAt, startedAt)) this.#hiddenAt.delete(id);
		for (const w of settledConversationWrites(this.#writes.values(), startedAt)) {
			this.#writes.delete(conversationWriteKey(w.conversationId, w.flag));
		}
		// The server lists no group while the flag is off (20271217000006); a
		// client that has not yet read the flag hides them too.
		const shown = this.groupsEnabled ? visible : visible.filter((t) => t.kind !== 'group');
		this.threads = shown.map((t) =>
			(this.#markedReadAt.get(dmThreadRouteId(t)) ?? -Infinity) >= startedAt ? { ...t, unread: 0 } : t,
		);
	}

	async loadThreads() {
		this.threadsError = false;
		const userId = this.#userId;
		const startedAt = performance.now();
		try {
			this.#apply(await fetchDmThreads(), startedAt, userId);
		} catch {
			this.threadsError = true;
		}
	}

	/// A failed poll keeps the list it has and logs: the next tick is the
	/// retry, and a banner every 30 s would be noise. A list that never loaded
	/// retries through loadThreads so its error state can clear.
	async poll() {
		if (this.#groupsUnknown) void this.loadGroups();
		if (this.#polling) return;
		if (this.threadsError) return this.loadThreads();
		this.#polling = true;
		const userId = this.#userId;
		const startedAt = performance.now();
		try {
			this.#apply(await fetchDmThreads(), startedAt, userId);
		} catch (e) {
			console.warn('messages inbox poll failed', e);
		} finally {
			this.#polling = false;
		}
		await this.refreshInvites();
		await this.refreshCoachPreview();
	}

	/// After a send or an unsend. The write already renders in the thread, so
	/// a failed list read leaves the previews as they were.
	async refreshThreads() {
		const userId = this.#userId;
		const startedAt = performance.now();
		try {
			this.#apply(await fetchDmThreads(), startedAt, userId);
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

	/// Marks a conversation unread, or clears the mark when it is opened. The
	/// row shows one unread at once; the badge re-reads once the write lands.
	setMarkedUnread(conversationId: string, markedUnread: boolean) {
		return this.#setFlag(conversationId, 'markedUnread', markedUnread, setDmConversationUnread);
	}

	/// The write is held in #writes until a list read carries it, so a poll
	/// that started before it landed cannot flip the toggle back. A refusal
	/// reverts that one field on that one row: restoring a snapshot of the
	/// whole list would also undo whatever a poll brought in meanwhile. A
	/// refusal that a later write to the same flag superseded reverts nothing.
	async #setFlag(
		conversationId: string,
		flag: ConversationFlag,
		value: boolean,
		write: (conversationId: string, value: boolean) => Promise<void>,
	) {
		const key = conversationWriteKey(conversationId, flag);
		const listed = this.threads.find((t) => t.conversationId === conversationId)?.[flag];
		const pending: ConversationWrite = {
			conversationId,
			flag,
			value,
			at: Infinity,
			prior: confirmedFlagValue(this.#writes.get(key), listed),
		};
		this.#writes.set(key, pending);
		this.#patch(conversationId, { [flag]: value });
		try {
			await write(conversationId, value);
		} catch (e) {
			if (!dropRefusedWrite(this.#writes, pending)) throw e;
			if (pending.prior !== undefined) {
				this.threads = revertConversationFlag(this.threads, conversationId, flag, pending.prior);
			} else {
				void this.refreshThreads();
			}
			throw e;
		}
		settleLandedWrite(this.#writes, pending, performance.now());
		// A row the list did not have is read now, so the conversation joins the
		// list with the state just written.
		if (listed === undefined) void this.refreshThreads();
		void dmUnreadStore.refresh();
	}

	/// Deletes a conversation for the runner, held behind the undo window
	/// (conventions.md § Destructive actions): the row leaves the list now and
	/// the server is told only when the window closes, so Undo cancels a timer.
	/// `onRestore` lets the open conversation pane come back with the row.
	/// `throughMessageId` is the newest message the runner had on screen: the
	/// delete stops there, so one sent during the window stays.
	hide(conversationId: string, opts: HideOptions) {
		const hidden = this.threads.find((t) => t.conversationId === conversationId);
		const userId = this.#userId;
		this.#hiddenAt.set(conversationId, Infinity);
		dmPendingHides.add(conversationId);
		this.threads = this.threads.filter((t) => t.conversationId !== conversationId);
		deferDestructive({
			message: opts.message,
			commit: async () => {
				try {
					await hideDmConversation(conversationId, opts.throughMessageId);
					if (this.#userId === userId) this.#hiddenAt.set(conversationId, performance.now());
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
				if (this.#userId !== userId) return;
				this.#hiddenAt.delete(conversationId);
				// The one row comes back at once, as it was at the delete: a
				// snapshot of the whole list would also undo whatever a poll
				// brought in during the window. The list read then brings the
				// row's preview and unread count up to anything that arrived
				// during the window, which the badge re-read below counts.
				const restored = restoreHiddenConversation(this.threads, hidden);
				if (restored) this.threads = restored;
				void this.refreshThreads();
				opts.onRestore?.();
				void dmUnreadStore.refresh();
			},
			onCommitError: (e) => opts.onCommitError(e),
		});
	}

	/// Accepts a message request. The row moves to the inbox at once; a
	/// refusal puts it back and rethrows for the caller to report.
	async acceptRequest(conversationId: string) {
		this.#patch(conversationId, { request: false });
		try {
			await acceptDmRequest(conversationId);
		} catch (e) {
			this.#patch(conversationId, { request: true });
			throw e;
		}
		void this.refreshThreads();
		void dmUnreadStore.refresh();
	}

	/// Declines a message request, and blocks the requester when `block`. Not
	/// undoable from the app (the conversation leaves every list), so the
	/// caller confirms first rather than holding it behind an undo window
	/// (conventions.md § Destructive actions). The row leaves only once the
	/// server has agreed; a refusal rethrows for the caller to report.
	async declineRequest(conversationId: string, throughMessageId: string, block = false) {
		await declineDmRequest(conversationId, throughMessageId, block);
		this.threads = this.threads.filter((t) => t.conversationId !== conversationId);
		void this.refreshThreads();
		void dmUnreadStore.refresh();
	}

	/// Reads the flag and, when it is on, the runner's invites. A failed flag
	/// read leaves the groups hidden and is retried by the next poll, so one
	/// blip does not hide them until the page is reloaded; a failed invite
	/// read keeps the list it had, and the next poll retries that too.
	async loadGroups() {
		const userId = this.#userId;
		const generation = ++this.#groupsGeneration;
		if (!userId) return;
		const read = await fetchGroupMessagesEnabled();
		if (generation !== this.#groupsGeneration) return;
		this.#groupsUnknown = read === null;
		const enabled = read === true;
		this.groupsEnabled = enabled;
		if (!enabled) {
			this.invites = [];
			this.threads = this.threads.filter((t) => t.kind !== 'group');
			return;
		}
		// A list read that landed before the flag did left the groups out.
		await Promise.all([this.refreshInvites(), this.refreshThreads()]);
	}

	async refreshInvites() {
		if (!this.groupsEnabled) return;
		const generation = this.#groupsGeneration;
		try {
			const invites = await fetchGroupInvites();
			if (generation === this.#groupsGeneration) this.invites = invites;
		} catch (e) {
			console.warn('messages inbox: group invites read failed', e);
		}
	}

	/// Accepts an invite: the group joins the inbox and its thread opens from
	/// the moment of acceptance (D3). A refusal rethrows for the caller.
	async acceptInvite(conversationId: string) {
		await acceptGroupInvite(conversationId);
		this.invites = this.invites.filter((i) => i.conversationId !== conversationId);
		await this.refreshThreads();
		void dmUnreadStore.refresh();
	}

	/// Declines an invite. Not undoable from the app (the group cannot invite
	/// the runner back for 14 days), so the caller confirms first.
	async declineInvite(conversationId: string) {
		await declineGroupInvite(conversationId);
		this.invites = this.invites.filter((i) => i.conversationId !== conversationId);
	}

	/// After leaving a group, or the open thread finding the runner removed:
	/// the row stays as "You left" while it holds a message of the runner's
	/// own, else it goes.
	async afterLeave() {
		await this.refreshThreads();
		void dmUnreadStore.refresh();
	}

	markRead(routeId: string) {
		this.#markedReadAt.set(routeId, performance.now());
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
