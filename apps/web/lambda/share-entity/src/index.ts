// AWS Lambda Function URL handler for the shared entity-SSR surface.
//
// One Lambda owning the nine public /share/* entity paths and the challenge
// card's /og/challenge PNG, all routed here by CloudFront (see the
// share-entity behaviours in infra/modules/web-stack/main.tf):
//   - /share/event/<id>        public club event   → SportsEvent/Event JSON-LD
//   - /share/profile/<id>      public runner       → ProfilePage JSON-LD
//   - /share/club/<slug>       public club         → SportsOrganization JSON-LD
//   - /share/race/<id>         race-calendar entry → SportsEvent JSON-LD
//   - /share/session/<id>      public session plan → WebPage + breadcrumb
//   - /share/workout/<id>      public gym workout  → WebPage + breadcrumb
//   - /share/plan/<id>         public-library plan → WebPage + breadcrumb
//   - /share/challenge/<id>    public challenge    → Event JSON-LD
//   - /share/course/<region>/<park>/<course>
//                              park course         → SportsActivityLocation JSON-LD
//   - /og/challenge/<id>.png   that challenge's og:image card
//
// Each renders at request time so an entity created/edited after the last
// build still unfurls with the right per-entity <head> before a crawler or
// chat-app link-unfurler (which do not run the SPA's JS) can see it. Every
// surface but the challenge uses the branded card (or, for profiles/clubs,
// the avatar URL) as its og:image; the challenge card is rasterised here
// with the same @resvg addon share-badge ships (decisions § 2261).
//
// Fail-open posture: a private / missing entity yields the SPA shell at 404
// with a noindex robots tag (a clean crawler signal), never a 5xx -- the same
// designed, localized not-found card a reader reaches by any other route.

import type { LambdaFunctionURLEvent, LambdaFunctionURLResult } from 'aws-lambda';

import { lookupSharedEvent } from '../../../src/lib/share/share_event_lookup';
import { lookupSharedProfile } from '../../../src/lib/share/share_profile_lookup';
import { lookupSharedClub } from '../../../src/lib/share/share_club_lookup';
import { lookupSharedRace } from '../../../src/lib/share/share_race_lookup';
import { lookupSharedSession } from '../../../src/lib/share/share_session_lookup';
import { lookupSharedWorkout } from '../../../src/lib/share/share_workout_lookup';
import { lookupSharedPlan } from '../../../src/lib/share/share_plan_lookup';
import { lookupSharedChallenge } from '../../../src/lib/share/share_challenge_lookup';
import { lookupSharedCourse } from '../../../src/lib/share/share_course_lookup';
import { renderChallengeOgPng } from '../../../src/lib/share/og_challenge_png';
import {
	buildShareEventHead,
	renderShareEventHeadTags,
} from '../../../src/lib/share/share_event_meta';
import {
	buildShareProfileHead,
	renderShareProfileHeadTags,
} from '../../../src/lib/share/share_profile_meta';
import {
	buildShareClubHead,
	renderShareClubHeadTags,
} from '../../../src/lib/share/share_club_meta';
import {
	buildShareRaceHead,
	renderShareRaceHeadTags,
} from '../../../src/lib/share/share_race_meta';
import {
	buildShareSessionHead,
	renderShareSessionHeadTags,
} from '../../../src/lib/share/share_session_meta';
import {
	buildShareWorkoutHead,
	renderShareWorkoutHeadTags,
} from '../../../src/lib/share/share_workout_meta';
import { buildSharePlanHead, renderSharePlanHeadTags } from '../../../src/lib/share/share_plan_meta';
import {
	buildShareChallengeHead,
	renderShareChallengeHeadTags,
} from '../../../src/lib/share/share_challenge_meta';
import {
	buildShareCourseHead,
	renderShareCourseHeadTags,
} from '../../../src/lib/share/share_course_meta';
import { injectEntityHead } from '../../../src/lib/share/entity_spa_shell';
import { siteOrigin } from '../../../src/lib/core/site_url';
import { shareMethodRefusal } from '../../../src/lib/share/share_method_gate';
import { notFoundShell } from '../../../src/lib/share/entity_spa_shell';
import { reportException } from '../../../src/lib/core/lambda_sentry';

declare const __SPA_SHELL_HTML__: string;

const CACHE_CONTROL = 'public, max-age=300, s-maxage=300, stale-while-revalidate=60';

// A 503 here is an unexpected throw, and it is the ONE response on these
// behaviours that must not carry the window above. Cached for five minutes at
// the edge, a transient failure becomes a five-minute outage for every viewer
// who shares a cache node with the request that tripped it (decisions § 969).
const NO_STORE = 'no-store';

interface Config {
	supabaseUrl: string;
	supabaseAnonKey: string;
	siteUrl: string;
}

const ROUTES: Array<{
	re: RegExp;
	render: (key: string, config: Config) => Promise<string | null>;
}> = [
	{
		re: /^\/share\/event\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { event } = await lookupSharedEvent(id, c);
			if (!event) return null;
			return renderShareEventHeadTags(buildShareEventHead({ id, event, siteUrl: c.siteUrl }));
		},
	},
	{
		re: /^\/share\/profile\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { profile } = await lookupSharedProfile(id, c);
			if (!profile) return null;
			return renderShareProfileHeadTags(
				buildShareProfileHead({ id, profile, siteUrl: c.siteUrl }),
			);
		},
	},
	{
		re: /^\/share\/club\/([^/]+)\/?$/,
		render: async (slug, c) => {
			const { club } = await lookupSharedClub(slug, c);
			if (!club) return null;
			return renderShareClubHeadTags(buildShareClubHead({ slug, club, siteUrl: c.siteUrl }));
		},
	},
	{
		re: /^\/share\/race\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { race } = await lookupSharedRace(id, c);
			if (!race) return null;
			return renderShareRaceHeadTags(buildShareRaceHead({ id, race, siteUrl: c.siteUrl }));
		},
	},
	{
		re: /^\/share\/session\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { session, displayName } = await lookupSharedSession(id, c);
			if (!session) return null;
			return renderShareSessionHeadTags(
				buildShareSessionHead({ id, session, displayName, siteUrl: c.siteUrl }),
			);
		},
	},
	{
		re: /^\/share\/workout\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { workout, displayName } = await lookupSharedWorkout(id, c);
			if (!workout) return null;
			return renderShareWorkoutHeadTags(
				buildShareWorkoutHead({ id, workout, displayName, siteUrl: c.siteUrl }),
			);
		},
	},
	{
		re: /^\/share\/plan\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { plan } = await lookupSharedPlan(id, c);
			if (!plan) return null;
			return renderSharePlanHeadTags(buildSharePlanHead({ id, plan, siteUrl: c.siteUrl }));
		},
	},
	{
		re: /^\/share\/challenge\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { challenge } = await lookupSharedChallenge(id, c);
			if (!challenge) return null;
			return renderShareChallengeHeadTags(
				buildShareChallengeHead({ id, challenge, siteUrl: c.siteUrl }),
			);
		},
	},
	{
		// Three slugs, the in-app /parks/[region]/[park]/[course] path's own.
		// Everything after the prefix is one key; the lookup splits and
		// validates it, so a mangled path is the branded not-found rather
		// than the JSON 404.
		re: /^\/share\/course\/(.+?)\/?$/,
		render: async (key, c) => {
			const { course } = await lookupSharedCourse(key, c);
			if (!course) return null;
			return renderShareCourseHeadTags(
				buildShareCourseHead({ key, course, siteUrl: c.siteUrl }),
			);
		},
	},
];

const CHALLENGE_PNG_RE = /^\/og\/challenge\/([^/]+)\.png$/;

export const handler = async (
	event: LambdaFunctionURLEvent,
): Promise<LambdaFunctionURLResult> => {
	try {
		const refused = shareMethodRefusal(event.requestContext?.http?.method);
		if (refused) return refused;

		const config: Config = {
			supabaseUrl: process.env.PUBLIC_SUPABASE_URL ?? '',
			supabaseAnonKey: process.env.PUBLIC_SUPABASE_ANON_KEY ?? '',
			// `siteOrigin`, not `?? DEFAULT_SITE_URL`: `??` fires only on
			// null/undefined, so a `PUBLIC_SITE_URL=""` in the function's env
			// survives as the empty string and every og:url / og:image below
			// comes out root-relative (decisions § 895).
			siteUrl: siteOrigin(process.env.PUBLIC_SITE_URL),
		};
		const path = event.rawPath || '/';
		const pngMatch = path.match(CHALLENGE_PNG_RE);
		if (pngMatch) {
			// A missing config or an unknown id renders the generic card at 200:
			// an unfurl image must never 404.
			const key = decodeKey(pngMatch[1]) ?? '';
			const png = await renderChallengeOgPng(
				key,
				config.supabaseUrl && config.supabaseAnonKey ? config : null,
			);
			return {
				statusCode: 200,
				isBase64Encoded: true,
				headers: { 'content-type': 'image/png', 'cache-control': CACHE_CONTROL },
				body: png.toString('base64'),
			};
		}
		for (const route of ROUTES) {
			const match = path.match(route.re);
			if (!match) continue;
			// `%zz` is not a valid escape, so decodeURIComponent THROWS on it.
			// Unguarded that reached the outer catch and answered 503 — a server
			// error and a retry signal to crawlers for what is simply a
			// malformed link. It is an entity we cannot find, like any other.
			const key = decodeKey(match[1]);
			// A missing Supabase config, a malformed key, or a private/missing
			// entity all resolve to the branded 404 (the render fn returns null).
			const headTags =
				key !== null && config.supabaseUrl && config.supabaseAnonKey
					? await route.render(key, config)
					: null;
			if (!headTags) return html(404, notFoundShell(__SPA_SHELL_HTML__, 'Not found — Threkir'));
			return html(200, injectEntityHead(__SPA_SHELL_HTML__, headTags));
		}
		return json(404, { error: 'not found' }, CACHE_CONTROL);
	} catch (err) {
		console.error('[share-entity lambda] unhandled_error', {
			path: event.rawPath,
			message: err instanceof Error ? err.message : String(err),
			stack: err instanceof Error ? err.stack : undefined,
		});
		await reportException('share-entity', err, { path: event.rawPath });
		return json(503, { error: 'temporarily unavailable' }, NO_STORE);
	}
};

/// The path segment as a decoded entity key, or null when the segment carries
/// a malformed percent-escape.
export function decodeKey(segment: string): string | null {
	try {
		return decodeURIComponent(segment);
	} catch {
		return null;
	}
}

function html(statusCode: number, body: string): LambdaFunctionURLResult {
	return {
		statusCode,
		headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': CACHE_CONTROL },
		body,
	};
}

function json(
	statusCode: number,
	body: unknown,
	cacheControl: string,
): LambdaFunctionURLResult {
	return {
		statusCode,
		headers: { 'content-type': 'application/json', 'cache-control': cacheControl },
		body: JSON.stringify(body),
	};
}
