// See https://kit.svelte.dev/docs/types#app
// for information about these interfaces
declare global {
	namespace App {
		// interface Error {}
		interface Locals {
			supabase: import('@supabase/supabase-js').SupabaseClient<
				import('#lib/core/database.ts').AppDatabase
			>;
			getSession: () => Promise<import('@supabase/supabase-js').Session | null>;
		}
		interface PageData {
			session?: import('@supabase/supabase-js').Session | null;
		}
		interface PageState {
			/// The back target a page saved for this history entry (`referrer_back.svelte.ts`).
			back?: { target: import('#lib/util/back_target.ts').BackTarget; pop: boolean };
			/// History entries the page pushed over its own (a park's opened preview); the back link steps over them.
			stacked?: number;
		}
		// interface Platform {}
	}
}

export {};
