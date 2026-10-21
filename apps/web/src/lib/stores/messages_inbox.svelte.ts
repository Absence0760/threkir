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
import { coachEnabled } from '#lib/coach/coach_flag.ts';
import {
	AI_DISCLOSURE_VERSION_COACH,
	aiDisclosureFromProfileRow,
	checkAiDisclosure,
} from '#lib/core/ai_disclosure.ts';
import {
	fetchDmThreads,
	fetchLatestCoachMessage,
	type DmThread,
	type LatestCoachMessage,
} from '#lib/core/data.ts';
import { supabase } from '#lib/core/supabase.ts';
import { effective, loadSettings, updateUniversal } from '#lib/settings/settings.ts';
import { dmThreadRouteId } from '#lib/social/dm_thread.ts';
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

	#userId: string | null = null;
	#polling = false;
	#coachGeneration = 0;
	/// When each conversation was last marked read. A list fetch that started
	/// before that answers with the count from before the mark, and assigning
	/// it as-is put the badge back on the conversation just opened.
	#markedReadAt = new Map<string, number>();

	/// Binds the store to the signed-in runner, dropping what another account
	/// left behind. Returns true when the user changed.
	bind(userId: string | null): boolean {
		if (userId === this.#userId) return false;
		this.#userId = userId;
		this.threads = [];
		this.threadsError = false;
		this.coach = null;
		this.#markedReadAt.clear();
		this.#coachGeneration++;
		return true;
	}

	#apply(rows: DmThread[], startedAt: number) {
		this.threads = rows.map((t) =>
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
		try {
			this.threads = await fetchDmThreads();
		} catch {
			// Corrected by the next poll.
		}
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
