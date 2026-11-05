/// The generated row types, with no client attached.
///
/// This module holds the ONLY path in the functions tree that reaches out of
/// `apps/backend` — deliberately. `apps/web/src/lib/database.types.ts` is the
/// single committed output of `npm run gen:types`
/// (docs/architecture/schema_codegen.md) and CI's `gen:types:check` fails the
/// PR when it drifts from the migrations. A second copy generated into this
/// tree would need a second drift check and would rot between the two, so the
/// functions read that one file, through here and nowhere else: if the
/// generated file ever moves, exactly one line changes.
///
/// Nothing crosses the boundary at RUNTIME. Every re-export below is
/// `export type`, so the specifier is erased before the Supabase CLI bundles a
/// function and `database.types.ts` never enters a deployed module graph
/// (it carries a runtime `Constants` export that would otherwise be dragged in).
///
/// It is split from `./database.ts`, which adds the client type, because it
/// must import nothing from supabase-js. `clip-public-track` reads these types,
/// and its worker has to boot without reaching registry.npmjs.org (decisions
/// § 699); `database.ts` takes its client type from `npm:`, and even a
/// type-only `npm:` import makes the runtime fetch that package before a
/// worker may boot (decisions § 2341). `_shared/offline_worker_boot_guard.test.ts`
/// walks the probe path and fails if `database.ts` enters it.
import type { Database, Json } from '../../../../web/src/lib/database.types.ts';

export type { Database, Json };

/// One table's Insert / Update shape, for a handler that names the row it is
/// building before it hands it to `.insert()` / `.update()`. There is no `Row`
/// alias: a read is inferred from the `.select()` that produced it, and naming
/// the whole row would claim columns the query did not ask for.
export type TablesInsert<T extends keyof Database['public']['Tables']> =
	Database['public']['Tables'][T]['Insert'];
export type TablesUpdate<T extends keyof Database['public']['Tables']> =
	Database['public']['Tables'][T]['Update'];
