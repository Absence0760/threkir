/**
 * Editing a sent direct message (issue #1216, migration 20271114000210). The
 * server decides: `edit_direct_message` refuses a message that is not the
 * caller's, is unsent, is past the window or sits between a blocked pair. This
 * only decides whether to offer Edit. Mobile twin: `dm_edit.dart`.
 */

/** Must equal `c_window` in edit_direct_message; dm_edit.test.ts reads the migration. */
export const DM_EDIT_WINDOW_MS = 15 * 60 * 1000;

export interface DmEditableMessage {
	sender_id: string;
	created_at: string;
	unsent_at: string | null;
	body: string | null;
	/// A shared AI Coach answer (`coach_share`) is never editable: the text
	/// under its AI label is the answer's, not the sender's (20271210001215).
	kind?: string;
}

/**
 * Whether the viewer may still edit `m` at `nowMs`: their own live message,
 * sent no more than the window ago. A `created_at` ahead of the local clock
 * (skew) counts as just sent; the server's clock is the one that decides.
 */
export function canEditDm(
	m: DmEditableMessage,
	viewerId: string | null | undefined,
	nowMs: number,
): boolean {
	if (!viewerId || m.sender_id !== viewerId) return false;
	if (m.unsent_at !== null || m.body === null) return false;
	if (m.kind === 'coach_share') return false;
	const sentMs = Date.parse(m.created_at);
	if (Number.isNaN(sentMs)) return false;
	return nowMs - sentMs <= DM_EDIT_WINDOW_MS;
}
