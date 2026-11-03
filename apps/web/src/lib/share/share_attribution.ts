/// Share-link attribution, the I/O half (decisions § 2268). The pure helpers
/// are in `share_ref.ts`.
///
/// Every call here is auxiliary to the page it runs on: a failure is logged
/// and degrades to "no ref" / "not counted", never to a broken share page or a
/// failed copy, join or sign-up.

import { supabase } from '../core/supabase';
import { auth } from '../stores/auth.svelte';
import {
	isLikelyBot,
	isTrackedShareKind,
	parseShareRef,
	shareRefFromSearch,
	signupShareFromTarget,
	type SignupShare,
	type TrackedShareKind,
} from './share_ref';

/// Whether the share_attribution gate is open. False on any error, so a
/// closed or unreachable gate adds nothing to a link or a sign-up.
export async function shareAttributionEnabled(): Promise<boolean> {
	const { data, error } = await supabase.rpc('share_attribution_enabled', undefined, { get: true });
	if (error) {
		console.error('share_attribution_enabled failed', error.message);
		return false;
	}
	return data === true;
}

let cached: { uid: string; ref: Promise<string | null> } | null = null;

/// The signed-in reader's own ref code when they own `ownerId`'s link, else
/// null. Minted once per session and cached; null while the gate is closed.
/// A failed read is not cached, so the next share tries again.
export function ownShareRef(ownerId: string | null | undefined): Promise<string | null> {
	const uid = auth.user?.id ?? null;
	if (!uid || !ownerId || uid !== ownerId) return Promise.resolve(null);
	if (cached?.uid !== uid) {
		cached = {
			uid,
			ref: (async () => {
				const { data, error } = await supabase.rpc('my_share_ref');
				if (error) {
					console.error('my_share_ref failed', error.message);
					cached = null;
					return null;
				}
				return parseShareRef(data);
			})(),
		};
	}
	return cached.ref;
}

/// Count one view of a `/share/<kind>/<id>` page. Runs in the visitor's
/// browser because CloudFront caches the share-entity HTML and strips the
/// query string, so the Lambda never sees a visit or its ref.
export async function recordShareView(
	kind: TrackedShareKind,
	id: string | null | undefined,
): Promise<void> {
	if (!id || !isTrackedShareKind(kind) || typeof window === 'undefined') return;
	try {
		const { error } = await supabase.rpc('record_share_visit', {
			p_kind: kind,
			p_id: id,
			p_ref: shareRefFromSearch(window.location.search),
			p_bot: isLikelyBot(navigator.userAgent, navigator.webdriver === true),
		});
		if (error) console.error('record_share_visit failed', error.message);
	} catch (e) {
		console.error('record_share_visit failed', e);
	}
}

/// Mark a plan copy (`id` = the new copy) or a challenge join (`id` = the
/// challenge) as started from the owner's link. False when nothing was marked.
export async function attributeShareStart(
	kind: 'plan' | 'challenge',
	id: string,
	ref: string | null | undefined,
): Promise<boolean> {
	const code = parseShareRef(ref);
	if (!code) return false;
	try {
		const { data, error } = await supabase.rpc('attribute_share_start', {
			p_kind: kind,
			p_id: id,
			p_ref: code,
		});
		if (error) {
			console.error('attribute_share_start failed', error.message);
			return false;
		}
		return data === true;
	} catch (e) {
		console.error('attribute_share_start failed', e);
		return false;
	}
}

export interface ShareStat {
	kind: TrackedShareKind;
	entityId: string;
	title: string | null;
	visits: number;
	refVisits: number;
	botVisits: number;
	signups: number;
	starts: number;
	refStarts: number;
	joins: number;
	refJoins: number;
}

/// The reader's own links over the last 90 days. Throws on a failed read, so
/// the page can tell "no links yet" from "could not load".
export async function fetchMyShareStats(): Promise<ShareStat[]> {
	const { data, error } = await supabase.rpc('my_share_stats', undefined, { get: true });
	if (error) throw new Error(error.message);
	return (data ?? []).flatMap((r) =>
		isTrackedShareKind(r.kind)
			? [
					{
						kind: r.kind,
						entityId: r.entity_id,
						title: r.title,
						visits: r.visits,
						refVisits: r.ref_visits,
						botVisits: r.bot_visits,
						signups: r.signups,
						starts: r.starts,
						refStarts: r.ref_starts,
						joins: r.joins,
						refJoins: r.ref_joins,
					},
				]
			: [],
	);
}

/// What a sign-up returning to `target` records as `signup_share` in its
/// GoTrue metadata: the link's kind, id and ref, but only while the gate is
/// open, so a closed gate stores nothing about the link at all.
export async function signupShareFor(target: string | null | undefined): Promise<SignupShare | null> {
	const share = signupShareFromTarget(target);
	if (!share) return null;
	return (await shareAttributionEnabled()) ? share : null;
}
