// The sitemap endpoints' shared read: one anon client, one load per kind.
//
// `/sitemap.xml` (the index) and `/sitemaps/[name].xml` (the children) both
// read the same rows. While prerendering, every child of a kind is rendered in
// the one prerender process, so each kind is loaded once and the index and its
// children agree on what exists. Outside a build (`vite dev`, the e2e lane)
// nothing is cached, so a row seeded after the server started is listed.
//
// Anon JWT only — the service-role key never enters the static bundle.
// A missing or unreachable Supabase degrades to the fixed pages only; the
// static site still ships.

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { building } from '$app/env';
import { PUBLIC_SITE_URL, PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$app/env/public';

import { siteOrigin } from '../core/site_url';
import type { SitemapKind } from './sitemap';
import { loadSitemapKind, type SitemapRow } from './sitemap_source';

const cache = new Map<SitemapKind, Promise<SitemapRow[]>>();
let client: SupabaseClient | null = null;

/// The canonical origin every <loc> is built on (www → apex is the CDN's job;
/// PUBLIC_SITE_URL already names the apex).
export function sitemapBase(): string {
	return siteOrigin(PUBLIC_SITE_URL);
}

function anonClient(): SupabaseClient | null {
	if (!PUBLIC_SUPABASE_URL || !PUBLIC_SUPABASE_ANON_KEY) return null;
	client ??= createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
		auth: { persistSession: false },
	});
	return client;
}

/// Every public row of `kind` as a sitemap entry, keyed by row id.
export function sitemapRows(kind: SitemapKind): Promise<SitemapRow[]> {
	const supabase = anonClient();
	if (!supabase) return Promise.resolve([]);
	if (!building) return loadSitemapKind(supabase, sitemapBase(), kind);
	let rows = cache.get(kind);
	if (!rows) {
		rows = loadSitemapKind(supabase, sitemapBase(), kind);
		cache.set(kind, rows);
	}
	return rows;
}

export const SITEMAP_HEADERS = {
	'content-type': 'application/xml; charset=utf-8',
	// Crawl etiquette: long-cache the static file; CloudFront invalidates on
	// every release-web deploy anyway.
	'cache-control': 'public, max-age=3600',
};
