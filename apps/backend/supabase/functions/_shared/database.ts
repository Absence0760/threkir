/// The generated row types, and the client type every Edge Function's
/// Supabase handle should carry.
///
/// The row types live in `./database_types.ts`, the tree's one reach into
/// `apps/web`; this module re-exports them so a handler has one import for
/// both. Every export here is a type, so nothing crosses at runtime.
///
/// supabase-js comes from npm, not esm.sh, for the reason the Stripe SDK does
/// (decisions § 2257, § 2341): esm.sh rebuilds a package's graph itself and its
/// CDN has served two builds of one versioned URL at once (`tslib@2.8.1`, which
/// supabase-js pulls in), which no `deno.lock` pin can match. An npm tarball is
/// immutable once published. The version must match the root package.json's
/// `@supabase/supabase-js` devDependency, which is where `deno check` reads the
/// declarations from; `offline_worker_boot_guard.test.ts` pins both.
///
/// This module must stay OFF `clip-public-track`'s module graph. A type-only
/// `npm:` import is enough to make the edge runtime fetch the package from
/// registry.npmjs.org before the worker boots, and every stack-using CI job's
/// setup probes that function (decisions § 699). The probe path takes its row
/// types from `./database_types.ts` instead.
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2.119.0';
import type { Database, Json, TablesInsert, TablesUpdate } from './database_types.ts';

export type { Database, Json, TablesInsert, TablesUpdate };

/// A Supabase client bound to this project's schema.
///
/// A service-role client and a user-scoped one are the SAME type: they differ
/// only in which key and which `Authorization` header they were built with,
/// and RLS is enforced by Postgres at request time, not by the type. What one
/// may read is a runtime fact about the caller, so nothing here can encode it
/// — which is why the two never need separate aliases, and why a parameter
/// typed `DbClient` still says nothing about privilege. Where that
/// distinction matters, the parameter name carries it (`service`, `admin`,
/// `userClient`), as it already did before these were typed at all.
export type DbClient = SupabaseClient<Database>;
