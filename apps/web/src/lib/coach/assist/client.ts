// Network glue for the coach assistant panel (issue #1215 Phase 4): the
// request in client_request.ts, over the browser's fetch and Supabase session.
// It resolves to the draft, which only this coach sees.

import { supabase } from '../../core/supabase';
import { postCoachAssistDraft, type CoachAssistDraftInput } from './client_request';

export function requestCoachAssistDraft(input: CoachAssistDraftInput): Promise<string> {
	return postCoachAssistDraft(input, {
		fetch: (url, init) => fetch(url, init),
		accessToken: async () => (await supabase.auth.getSession()).data.session?.access_token,
		refreshedToken: async () => (await supabase.auth.refreshSession()).data.session?.access_token,
	});
}
