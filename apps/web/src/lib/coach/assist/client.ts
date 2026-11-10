// Network glue for the coach assistant panel (issue #1215 Phase 4). Posts the
// athlete id, the mode and the coach's optional request to /api/coach/assist
// and resolves to the draft, which only this coach sees. The server reads
// the athlete's data itself, under every consent; the client never sends it.

import { supabase } from '../../core/supabase';
import { payloadSha256Hex } from '../../util/payload_hash';
import { CoachAssistError, coachAssistErrorKind } from './client_kind';
import type { CoachAssistMode } from './context';

export async function requestCoachAssistDraft(input: {
	athleteId: string;
	mode: CoachAssistMode;
	request: string;
	today: string;
	locale: string;
}): Promise<string> {
	const body = JSON.stringify({
		athlete_id: input.athleteId,
		mode: input.mode,
		request: input.request.trim() || undefined,
		today: input.today,
		locale: input.locale,
	});
	const bodyHash = await payloadSha256Hex(body);
	const post = (token: string) =>
		fetch('/api/coach/assist', {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				'X-Supabase-Authorization': `Bearer ${token}`,
				'x-amz-content-sha256': bodyHash,
			},
			body,
		});

	let token = (await supabase.auth.getSession()).data.session?.access_token;
	if (!token) throw new CoachAssistError('not_authenticated');
	let res = await post(token);
	if (res.status === 401) {
		const refreshed = await supabase.auth.refreshSession().catch(() => null);
		token = refreshed?.data.session?.access_token ?? token;
		res = await post(token);
	}
	const data = (await res.json().catch(() => null)) as {
		draft?: unknown;
		code?: unknown;
		upgrade?: unknown;
	} | null;
	if (!res.ok) throw new CoachAssistError(coachAssistErrorKind(res.status, data));
	if (!data || typeof data.draft !== 'string' || !data.draft.trim()) {
		throw new CoachAssistError('unavailable');
	}
	return data.draft;
}
