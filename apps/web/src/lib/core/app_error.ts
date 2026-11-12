import type { MessageKey } from '#lib/i18n/messages.ts';

export type AppErrorParams = Record<string, string | number>;

/// A failure the app raises on purpose and wants the reader to see in their
/// own language. It carries the catalogue key (and its params) the sentence
/// lives under, so `errorCopy` renders it instead of falling back to a
/// generic line, and a free-text English `new Error('…')` never has to reach
/// the page to be specific (decisions § 2291). `message` is for logs and for
/// code that still pattern-matches the text; it defaults to the key.
export class AppError extends Error {
	readonly key: MessageKey;
	readonly params: AppErrorParams | undefined;

	constructor(key: MessageKey, opts: { params?: AppErrorParams; message?: string } = {}) {
		super(opts.message ?? key);
		this.name = 'AppError';
		this.key = key;
		this.params = opts.params;
	}
}
