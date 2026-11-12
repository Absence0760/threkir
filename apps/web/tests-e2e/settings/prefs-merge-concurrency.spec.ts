import { expect, test } from '../fixtures/test';

import { readRow } from '../fixtures/db-read';
import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Concurrent writers to one prefs bag must all land (issue #1212).
 *
 * Both clients used to push a settings change as a read-merge-write of the
 * whole bag, so two writers in flight each read the bag before the other's
 * upsert landed and the later upsert put the earlier one's key back. One page
 * load has several such writers — the layout's `time_zone` sync, a prefs
 * page's one-time `locale` stamp, the page's own save — and on CI a
 * /settings/body save of `body_weight_kg` was overwritten by the `locale`
 * stamp 28 ms later.
 *
 * The merge now runs server-side in one statement. This fires the writes
 * together, through the real RPC under the user's own JWT, and requires every
 * key to survive; a client-side merge passes it only when the writes happen
 * not to overlap.
 */
test.describe('prefs bag — concurrent merges', () => {
	const admin = getAdminClient();
	let user: SagaUser;

	test.beforeEach(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Prefs Merge Saga'] });
		const { error } = await admin
			.from('user_settings')
			.upsert({ user_id: user.id, prefs: { body_weight_kg: 60, privacy_default: 'followers' } });
		if (error) throw error;
	});

	test.afterEach(async () => {
		await deleteSagaUsers([user]);
	});

	test('every concurrent merge_my_settings call keeps its key, and a null removes one', async () => {
		const client = await getUserClient({ email: user.email, password: user.password });
		const keys = Array.from({ length: 12 }, (_, i) => `merge_probe_${i}`);

		const results = await Promise.all([
			client.rpc('merge_my_settings', { p_changes: { body_weight_kg: 81.5 } }),
			client.rpc('merge_my_settings', { p_changes: { privacy_default: null } }),
			...keys.map((k, i) => client.rpc('merge_my_settings', { p_changes: { [k]: i } })),
		]);
		for (const r of results) expect(r.error).toBeNull();

		const row = await readRow<{
			data: { prefs: Record<string, unknown> } | null;
			error: { message: string } | null;
		}>(
			'prefs after concurrent merges',
			admin.from('user_settings').select('prefs').eq('user_id', user.id).single(),
		);
		expect(row.prefs.body_weight_kg).toBe(81.5);
		expect('privacy_default' in row.prefs).toBe(false);
		for (const [i, k] of keys.entries()) expect(row.prefs[k]).toBe(i);
	});

	test('every concurrent merge_my_device_settings call keeps its key', async () => {
		const client = await getUserClient({ email: user.email, password: user.password });
		const keys = Array.from({ length: 12 }, (_, i) => `merge_probe_${i}`);

		const results = await Promise.all(
			keys.map((k, i) =>
				client.rpc('merge_my_device_settings', {
					p_device_id: 'e2e-merge-device',
					p_changes: { [k]: i },
					p_platform: 'web',
				}),
			),
		);
		for (const r of results) expect(r.error).toBeNull();

		const row = await readRow<{
			data: { prefs: Record<string, unknown> } | null;
			error: { message: string } | null;
		}>(
			'device prefs after concurrent merges',
			admin
				.from('user_device_settings')
				.select('prefs')
				.eq('user_id', user.id)
				.eq('device_id', 'e2e-merge-device')
				.single(),
		);
		for (const [i, k] of keys.entries()) expect(row.prefs[k]).toBe(i);
	});
});
