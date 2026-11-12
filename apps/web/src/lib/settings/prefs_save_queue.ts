import type { PrefsBag } from './settings_overlay';

export type PrefsSaveStatus = 'idle' | 'saving' | 'saved';

export interface PrefsSaveQueueOptions {
	write: (batch: PrefsBag) => Promise<unknown>;
	onStatus: (status: PrefsSaveStatus) => void;
	onError: (error: Error) => void;
	debounceMs?: number;
	savedMs?: number;
	setTimer?: (fn: () => void, ms: number) => unknown;
	clearTimer?: (handle: unknown) => void;
}

/// The auto-save path every preference page shares. Edits are COALESCED:
/// rapid changes (blurring two heart-rate fields back to back) accumulate
/// into one batched write, so concurrent partial writes cannot clobber each
/// other on a stale bag snapshot. A failed batch is merged back under any
/// edit made while it was in flight, so neither is lost and the newer wins.
export class PrefsSaveQueue {
	private pending: PrefsBag = {};
	private flushTimer: unknown = null;
	private savedTimer: unknown = null;
	private readonly debounceMs: number;
	private readonly savedMs: number;
	private readonly setTimer: (fn: () => void, ms: number) => unknown;
	private readonly clearTimer: (handle: unknown) => void;

	constructor(private readonly opts: PrefsSaveQueueOptions) {
		this.debounceMs = opts.debounceMs ?? 350;
		this.savedMs = opts.savedMs ?? 1800;
		this.setTimer = opts.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
		this.clearTimer =
			opts.clearTimer ?? ((handle) => clearTimeout(handle as ReturnType<typeof setTimeout>));
	}

	enqueue(changes: PrefsBag): void {
		Object.assign(this.pending, changes);
		this.opts.onStatus('saving');
		if (this.flushTimer !== null) this.clearTimer(this.flushTimer);
		this.flushTimer = this.setTimer(() => void this.flush(), this.debounceMs);
	}

	async flush(): Promise<void> {
		if (this.flushTimer !== null) {
			this.clearTimer(this.flushTimer);
			this.flushTimer = null;
		}
		if (Object.keys(this.pending).length === 0) return;
		const batch = this.pending;
		this.pending = {};
		try {
			await this.opts.write(batch);
			this.opts.onStatus('saved');
			if (this.savedTimer !== null) this.clearTimer(this.savedTimer);
			this.savedTimer = this.setTimer(() => this.opts.onStatus('idle'), this.savedMs);
		} catch (e) {
			this.pending = { ...batch, ...this.pending };
			this.opts.onStatus('idle');
			this.opts.onError(e as Error);
		}
	}
}
