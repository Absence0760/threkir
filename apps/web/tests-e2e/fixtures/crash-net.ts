import { CLIENT_ERROR_LOG_PREFIX } from '../../src/lib/core/client_error_log.ts';

/**
 * The pure half of the crash net (`fixtures/test.ts`): what counts as a crash,
 * how an opt-out or an allowlist entry is validated, and how the findings are
 * settled and worded. No Playwright import, so `crash-net.test.ts` runs under
 * the plain node:test runner with the rest of the fixture suites.
 */

export type CrashKind = 'pageerror' | 'svelte-runtime' | 'client-error' | 'error-boundary';

export interface Crash {
	kind: CrashKind;
	url: string;
	text: string;
}

export interface CrashNetAllow {
	/** Substring (or pattern) of the crash text this entry excuses. */
	match: string | RegExp;
	/** Why this crash is expected. Required and non-empty. */
	reason: string;
}

export type CrashNetMode = 'fail' | 'report';

export interface CrashNetOptions {
	/** Turns the net off for the test. The value is the reason, required and non-empty. */
	off?: string;
	/** Crashes the test expects. An entry that excuses nothing fails the test, so it cannot go stale. */
	allow?: readonly CrashNetAllow[];
	/** Overrides `CRASH_NET` for this test. The net's own proof spec pins `fail`. */
	mode?: CrashNetMode;
}

/**
 * Logged by the init script `boundaryObserverScript` installs when SvelteKit's
 * error page ("Internal Error") appears in the DOM, so a boundary is caught
 * through the same console channel as everything else — including one the
 * spec navigated away from, or whose context it closed, before teardown.
 */
export const ERROR_BOUNDARY_MARKER = '[crash-net] error boundary rendered';

/** A Svelte or SvelteKit runtime error links its code under this path. */
const SVELTE_RUNTIME_CODE = 'svelte.dev/e/';

/**
 * Only `error`-level console messages count. Svelte's dev warnings link to the
 * same `svelte.dev/e/` docs and are not crashes.
 */
export function classifyConsole(type: string, text: string): CrashKind | null {
	if (type !== 'error') return null;
	if (text.startsWith(ERROR_BOUNDARY_MARKER)) return 'error-boundary';
	if (text.startsWith(CLIENT_ERROR_LOG_PREFIX)) return 'client-error';
	if (text.includes(SVELTE_RUNTIME_CODE)) return 'svelte-runtime';
	return null;
}

/**
 * Unset means `fail`: the end state lives in the code, and a temporary
 * report-only pass is a CI env line that gets deleted. Anything other than
 * the two words throws, so a typo cannot silently disarm the net.
 */
export function resolveMode(env: string | undefined, override?: CrashNetMode): CrashNetMode {
	if (override) return override;
	if (env === undefined || env === '' || env === 'fail') return 'fail';
	if (env === 'report') return 'report';
	throw new Error(`CRASH_NET must be "fail" or "report" (or unset, meaning fail); got ${JSON.stringify(env)}`);
}

export function validateOptions(options: CrashNetOptions | undefined): CrashNetOptions {
	const o = options ?? {};
	if (o.off !== undefined && (typeof o.off !== 'string' || o.off.trim() === '')) {
		throw new Error(
			'crashNet.off needs a written reason: test.use({ crashNet: { off: "why this test may crash" } })'
		);
	}
	for (const entry of o.allow ?? []) {
		if (typeof entry.reason !== 'string' || entry.reason.trim() === '') {
			throw new Error(`crashNet.allow entry ${String(entry.match)} needs a written reason`);
		}
		if (entry.match === '' || (entry.match instanceof RegExp && entry.match.source === '(?:)')) {
			throw new Error('crashNet.allow entry has an empty match, which would excuse every crash');
		}
	}
	if (o.off !== undefined && o.allow?.length) {
		throw new Error('crashNet.off and crashNet.allow together: off already excuses everything');
	}
	return o;
}

function matches(entry: CrashNetAllow, text: string): boolean {
	return typeof entry.match === 'string' ? text.includes(entry.match) : entry.match.test(text);
}

export interface Settled {
	crashes: Crash[];
	allowed: Array<{ crash: Crash; reason: string }>;
	stale: CrashNetAllow[];
}

export function settle(recorded: readonly Crash[], allow: readonly CrashNetAllow[] = []): Settled {
	const used = new Set<CrashNetAllow>();
	const crashes: Crash[] = [];
	const allowed: Settled['allowed'] = [];
	for (const crash of recorded) {
		const entry = allow.find((a) => matches(a, crash.text));
		if (entry) {
			used.add(entry);
			allowed.push({ crash, reason: entry.reason });
		} else {
			crashes.push(crash);
		}
	}
	return { crashes, allowed, stale: allow.filter((a) => !used.has(a)) };
}

const MAX_TEXT = 600;

export function describeCrash(crash: Crash): string {
	const text = crash.text.length > MAX_TEXT ? `${crash.text.slice(0, MAX_TEXT)}…` : crash.text;
	return `[${crash.kind}] ${crash.url}: ${text}`;
}

/** A GitHub Actions workflow command, escaped so a multi-line stack stays one annotation. */
export function githubWarning(title: string, message: string): string {
	const escape = (s: string) => s.replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
	const escapeProperty = (s: string) => escape(s).replace(/:/g, '%3A').replace(/,/g, '%2C');
	return `::warning title=${escapeProperty(title)}::${escape(message)}`;
}

/**
 * Runs in every page of a watched context before its own scripts. SvelteKit's
 * default error page is `<h1>{status}</h1><p>{message}</p>`, and an unexpected
 * error's message is "Internal Error" — a 404's is "Not Found", which specs
 * visit on purpose and this deliberately ignores. Reports once per document.
 */
export function boundaryObserverScript(marker: string): void {
	let reported = false;
	const check = () => {
		if (reported) return;
		for (const p of Array.from(document.querySelectorAll('p'))) {
			if (p.textContent?.trim() !== 'Internal Error') continue;
			const heading = p.previousElementSibling;
			if (!heading || !/^H[1-6]$/.test(heading.tagName)) continue;
			reported = true;
			console.error(`${marker} (${heading.textContent?.trim()}) at ${location.pathname}`);
			observer.disconnect();
			return;
		}
	};
	const observer = new MutationObserver(check);
	observer.observe(document, { childList: true, subtree: true, characterData: true });
}
