// The request half of the coach assistant client, with fetch and the session
// passed in so every answer of /api/coach/assist can be unit-tested without a
// browser Supabase client; client.ts wires the real ones. The server reads
// the athlete's data itself, under every consent; the body carries only the
// athlete id, the mode and the coach's optional request.

import { payloadSha256Hex } from '../../util/payload_hash';
import { CoachAssistError, coachAssistErrorKind } from './client_kind';
import type { CoachAssistMode } from './context';

export interface CoachAssistDraftInput {
	athleteId: string;
	mode: CoachAssistMode;
	request: string;
	today: string;
	locale: string;
}

export interface CoachAssistTransport {
	fetch: (url: string, init: RequestInit) => Promise<Response>;
	accessToken: () => Promise<string | undefined>;
	/** A fresh token after a 401, or undefined when the refresh fails. */
	refreshedToken: () => Promise<string | undefined>;
}

export async function postCoachAssistDraft(input: CoachAssistDraftInput, io: CoachAssistTransport): Promise<string> {
	const body = JSON.stringify({
		athlete_id: input.athleteId,
		mode: input.mode,
		request: input.request.trim() || undefined,
		today: input.today,
		locale: input.locale,
	});
	const bodyHash = await payloadSha256Hex(body);
	const post = async (token: string) => {
		try {
			return await io.fetch('/api/coach/assist', {
				method: 'POST',
				headers: {
					'content-type': 'application/json',
					'X-Supabase-Authorization': `Bearer ${token}`,
					'x-amz-content-sha256': bodyHash,
				},
				body,
			});
		} catch {
			throw new CoachAssistError('unavailable');
		}
	};

	let token = await io.accessToken();
	if (!token) throw new CoachAssistError('not_authenticated');
	let res = await post(token);
	if (res.status === 401) {
		token = (await io.refreshedToken().catch(() => undefined)) ?? token;
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
