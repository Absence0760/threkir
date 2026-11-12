import type { Browser, BrowserContext, Page, TestInfo } from '@playwright/test';

import {
	boundaryObserverScript,
	classifyConsole,
	describeCrash,
	ERROR_BOUNDARY_MARKER,
	githubWarning,
	resolveMode,
	settle,
	validateOptions,
	type Crash,
	type CrashNetOptions
} from './crash-net.ts';
import { expect, test as mockRouteTest } from './mock-route.ts';

/**
 * The suite-wide crash net. Import `test` and `expect` from here instead of
 * `@playwright/test` and every page the test opens is watched for:
 *
 * - an uncaught exception (`pageerror`),
 * - an `error`-level console message carrying a Svelte runtime code
 *   (`svelte.dev/e/…` — `each_key_duplicate`, `app_stores_removed`, …),
 * - the client `handleError` hook's local log line (`client_error_log.ts`),
 * - SvelteKit's "Internal Error" page appearing in the DOM.
 *
 * Teardown fails the test listing every one, so a spec asserting on a
 * heading that happens to render beside a crashed chart can no longer pass.
 * Pages in the default `context` and in any context the test makes with
 * `browser.newContext()` / `browser.newPage()` are covered; contexts made in a
 * `beforeAll` are not, because they belong to no single test.
 *
 * Opting out takes a reason, per test or per describe:
 *
 *     test.use({ crashNet: { off: 'drives the 500 page on purpose' } });
 *     test.use({ crashNet: { allow: [{ match: 'each_key_duplicate', reason: '#1234' }] } });
 *
 * An `allow` entry that excuses nothing fails the test, so it cannot outlive
 * the crash it was written for.
 *
 * `CRASH_NET=report` logs instead of failing: each crash becomes a
 * `crash-net` test annotation and a stdout line (a `::warning` annotation on
 * GitHub Actions). Unset means fail. Decisions § 1944.
 */

export type { CrashNetOptions };

interface Recorder {
	crashes: Crash[];
	attach(context: BrowserContext): Promise<void>;
}

function newRecorder(): Recorder {
	const crashes: Crash[] = [];
	const attached = new WeakSet<BrowserContext>();
	const watch = (page: Page) => {
		page.on('pageerror', (error) =>
			crashes.push({ kind: 'pageerror', url: page.url(), text: error.stack ?? error.message })
		);
		page.on('console', (message) => {
			const kind = classifyConsole(message.type(), message.text());
			if (kind) crashes.push({ kind, url: page.url(), text: message.text() });
		});
	};
	return {
		crashes,
		async attach(context) {
			if (attached.has(context)) return;
			attached.add(context);
			await context.addInitScript(boundaryObserverScript, ERROR_BOUNDARY_MARKER);
			context.on('page', watch);
			for (const page of context.pages()) watch(page);
		}
	};
}

/** Routes every context the test body makes through the recorder, until teardown. */
function interceptNewContexts(browser: Browser, recorder: Recorder): () => void {
	const hadOwn = {
		newContext: Object.prototype.hasOwnProperty.call(browser, 'newContext'),
		newPage: Object.prototype.hasOwnProperty.call(browser, 'newPage')
	};
	const newContext = browser.newContext;
	const newPage = browser.newPage;
	browser.newContext = async (...args) => {
		const context = await newContext.apply(browser, args);
		await recorder.attach(context);
		return context;
	};
	browser.newPage = async (...args) => {
		const page = await newPage.apply(browser, args);
		await recorder.attach(page.context());
		return page;
	};
	return () => {
		if (hadOwn.newContext) browser.newContext = newContext;
		else Reflect.deleteProperty(browser, 'newContext');
		if (hadOwn.newPage) browser.newPage = newPage;
		else Reflect.deleteProperty(browser, 'newPage');
	};
}

function report(testInfo: TestInfo, lines: string[], label: string): void {
	for (const line of lines) {
		testInfo.annotations.push({ type: 'crash-net', description: `${label}: ${line}` });
		const where = testInfo.titlePath.join(' > ');
		console.log(
			process.env.GITHUB_ACTIONS
				? githubWarning(`crash-net (report-only) ${label}`, `${where}\n${line}`)
				: `crash-net (report-only) ${label} in ${where}: ${line}`
		);
	}
}

export const test = mockRouteTest.extend<{ crashNet: CrashNetOptions; crashNetArmed: void }>({
	crashNet: [{}, { option: true }],

	// Fixtures are lazy: a test that asks only for `browser` (most saga specs,
	// which make their own context) never instantiates `context`, so without
	// this the net below never ran for them and `browser.newContext` was
	// never intercepted.
	crashNetArmed: [
		async ({ context }, use) => {
			void context;
			await use();
		},
		{ auto: true }
	],

	// `context` is overridden (rather than the net being an auto fixture) so
	// its teardown runs after every page the test used has closed, which is
	// when the last console message and pageerror have been delivered.
	context: async ({ context, crashNet, browser }, use, testInfo) => {
		const options = validateOptions(crashNet);
		if (options.off !== undefined) {
			testInfo.annotations.push({ type: 'crash-net', description: `off: ${options.off}` });
			await use(context);
			return;
		}
		const mode = resolveMode(process.env.CRASH_NET, options.mode);
		const recorder = newRecorder();
		await recorder.attach(context);
		const restore = interceptNewContexts(browser, recorder);
		try {
			await use(context);
		} finally {
			restore();
		}
		for (const page of context.pages()) {
			if (!page.isClosed()) await page.close();
		}

		const { crashes, allowed, stale } = settle(recorder.crashes, options.allow);
		for (const { crash, reason } of allowed) {
			testInfo.annotations.push({
				type: 'crash-net',
				description: `allowed (${reason}): ${describeCrash(crash)}`
			});
		}
		const found = crashes.map(describeCrash);
		const staleLines = stale.map((a) => `${String(a.match)} (${a.reason})`);

		if (mode === 'report') {
			report(testInfo, found, 'crash');
			report(testInfo, staleLines, 'stale allow entry');
			return;
		}
		expect(
			found,
			'The page crashed while this test ran. A crash beside a passing assertion is still a ' +
				'crash: fix it, or declare it with crashNet.allow (or crashNet.off) and a reason'
		).toEqual([]);
		expect(
			staleLines,
			'These crashNet.allow entries excused nothing in this test. The crash they were written ' +
				'for is gone (delete the entry) or now reads differently (update its match)'
		).toEqual([]);
	}
});

export { expect };
