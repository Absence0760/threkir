import { test as base, expect } from '@playwright/test';
import type { Request, Route } from '@playwright/test';

/**
 * `page.route` with the silence taken out of it.
 *
 * A Playwright glob is anchored at both ends, so `**\/auth/v1/user` compiles to
 * `^(.*\/)auth/v1/user$` and never sees the `?redirect_to=…` the SDK actually
 * sends. Nothing reports that: the request escapes to the real server, the
 * stub's body is never used, and every assertion written beside it — "the
 * pending banner appeared", "the write was never sent" — is scored against a
 * handler nothing invoked. The spec stays green while the endpoint it was
 * standing in front of was reached for real.
 *
 * `mockRoute` registers the same handler and counts its invocations, then fails
 * the test from fixture teardown if the count is zero. Where a mock is *meant*
 * never to fire, `neverFires` says so in words and the count is asserted at
 * zero instead — which is a real check, not an exemption: a mock that starts
 * firing fails too, so the reason cannot quietly go stale.
 *
 * Usage — take `mockRoute` off the fixture object, not off `page`:
 *
 *     import { expect, test } from '../fixtures/mock-route';
 *
 *     test('…', async ({ page, mockRoute }) => {
 *         await mockRoute(page, '**\/api/coach', (route) => route.fulfill({ … }));
 *     });
 *
 * The first argument is the routing target, so a second context's page, or a
 * `BrowserContext` itself, works the same way.
 *
 * `tests-e2e/fixtures/mock-route.test.ts` fails the PR when a bare
 * `.route()` call that guards a mutation is added without it.
 */

export type RouteHandler = (route: Route, request: Request) => unknown;

/**
 * The structural slice of `Page` / `BrowserContext` this needs. Declared
 * rather than imported as a union so a spec can pass either without a cast.
 */
export interface RouteTarget {
	route(
		url: string | RegExp | ((url: URL) => boolean),
		handler: RouteHandler,
		options?: { times?: number }
	): Promise<unknown>;
}

export interface MockRouteOptions {
	/** Passed straight through to `page.route`. */
	times?: number;
	/**
	 * Why this mock is expected never to be invoked. Inverts the check: the
	 * test fails if the handler runs at all.
	 */
	neverFires?: string;
}

export interface MockRoute {
	(
		target: RouteTarget,
		url: string | RegExp | ((url: URL) => boolean),
		handler: RouteHandler,
		options?: MockRouteOptions
	): Promise<void>;
	/**
	 * Declare, from inside one case, that a mock a `beforeEach` installed for
	 * the whole file is not exercised by THIS case — because the case never
	 * reaches the endpoint, or because it replaced the stub with its own. The
	 * count is then asserted at zero rather than at one, and the declaration
	 * itself is checked: naming a pattern no registration in this test used
	 * fails, so a moved or renamed mock cannot leave the sentence behind.
	 */
	neverFires(url: string | RegExp | ((url: URL) => boolean), reason: string): void;
}

interface Registration {
	target: RouteTarget;
	pattern: string;
	site: string;
	calls: number;
	neverFires?: string;
}

function describePattern(url: string | RegExp | ((url: URL) => boolean)): string {
	if (typeof url === 'string') return url;
	if (url instanceof RegExp) return String(url);
	return '(url predicate)';
}

/** The spec line that registered the mock, so the failure names it. */
function callSite(): string {
	const frames = new Error().stack?.split('\n').slice(1) ?? [];
	for (const frame of frames) {
		if (frame.includes('fixtures/mock-route.ts')) continue;
		const match = /\(?((?:[A-Za-z]:)?[^()\s]*tests-e2e[^()\s]*?:\d+:\d+)\)?\s*$/.exec(frame);
		if (match) {
			const from = match[1].indexOf('tests-e2e');
			return match[1].slice(from);
		}
	}
	return 'unknown call site';
}

export const test = base.extend<{ mockRoute: MockRoute }>({
	mockRoute: async ({}, use, testInfo) => {
		const registered: Registration[] = [];
		const declaredSilent: Array<{ pattern: string; reason: string; site: string }> = [];

		const mockRoute: MockRoute = async (target, url, handler, options) => {
			const record: Registration = {
				target,
				pattern: describePattern(url),
				site: callSite(),
				calls: 0,
				neverFires: options?.neverFires
			};
			registered.push(record);
			await target.route(
				url,
				(route, request) => {
					record.calls += 1;
					return handler(route, request);
				},
				options?.times === undefined ? undefined : { times: options.times }
			);
		};

		mockRoute.neverFires = (url, reason) => {
			declaredSilent.push({ pattern: describePattern(url), reason, site: callSite() });
		};

		await use(mockRoute);

		// A test that already failed has said what went wrong; a dead mock
		// underneath it is a consequence to report after the real cause, not
		// a second error on top of it.
		if (testInfo.errors.length > 0) return;

		const unmatched = declaredSilent.filter(
			(d) => !registered.some((r) => r.pattern === d.pattern)
		);
		expect(
			unmatched.map((d) => `${d.pattern} (${d.site})`),
			'These `mockRoute.neverFires` declarations name a pattern no mock in this test ' +
				'registered, so they excuse nothing. The mock they were written for has moved, ' +
				'been renamed, or gone'
		).toEqual([]);
		for (const d of declaredSilent) {
			for (const r of registered) if (r.pattern === d.pattern) r.neverFires = d.reason;
		}

		// A later mock on the same target and pattern supersedes an earlier one
		// — Playwright runs the most recent handler first, and `page.unroute`
		// retires the earlier registration outright. Either way the pattern is
		// proven live by the one that fired, which is what is being checked.
		const superseded = (r: Registration, i: number) =>
			registered.some(
				(later, j) => j > i && later.target === r.target && later.pattern === r.pattern && later.calls > 0
			);

		const dead = registered.filter(
			(r, i) => !r.neverFires && r.calls === 0 && !superseded(r, i)
		);
		expect(
			dead.map((r) => `${r.pattern} (${r.site})`),
			'These route mocks were never invoked, so nothing they were standing in front of was ' +
				'stubbed: the real endpoint answered every request and the assertions written ' +
				'beside the mock were scored against a handler that never ran. A Playwright glob ' +
				'is anchored at both ends — a pattern without a trailing `*` cannot match a URL ' +
				'that carries a query string. Fix the pattern, or pass `neverFires` with the ' +
				'reason it is right for this one not to fire'
		).toEqual([]);

		const stale = registered.filter((r) => r.neverFires && r.calls > 0);
		expect(
			stale.map((r) => `${r.pattern} (${r.site}): ${r.neverFires}`),
			'These route mocks are declared `neverFires` but were invoked. Either the behaviour ' +
				'the reason describes has changed — in which case the reason is stale and the ' +
				'mock now needs a real assertion — or the mock is fine and the flag should go'
		).toEqual([]);
	}
});

export { expect };
