import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	changedEditFields,
	editedFieldsMoved,
	runEditPatch,
	saveRunEdit,
	type RunEditIo,
	type RunEditPatch,
	type RunEditRow,
} from './run_edit_cas';

// The run-detail edit is a compare-and-swap on the server-stamped
// `updated_at` (decisions § 2147). The fake plays Postgres: a swap lands only
// while the row still holds the base it is given, and every landed write
// moves the stamp.

const BASE_1 = '2026-09-02T08:00:00.123456+00:00';
const BASE_2 = '2026-09-02T09:30:00.654321+00:00';

function row(over: Partial<RunEditRow> = {}): RunEditRow {
	return {
		updated_at: BASE_1,
		metadata: { title: 'Easy', notes: 'flat', activity_type: 'run' },
		is_dnf: false,
		...over,
	};
}

class FakeServer implements RunEditIo<RunEditRow> {
	swaps: Array<{ patch: RunEditPatch; base: string | null }> = [];
	reloads = 0;
	/// Runs just before each swap is evaluated, to move the row behind it.
	beforeSwap: Array<() => void> = [];
	private stamp = 0;

	constructor(public current: RunEditRow | null) {}

	async swap(patch: RunEditPatch, base: string | null): Promise<RunEditRow[]> {
		this.swaps.push({ patch, base });
		this.beforeSwap.shift()?.();
		if (!this.current || this.current.updated_at !== base) return [];
		this.stamp++;
		this.current = {
			...this.current,
			...patch,
			updated_at: `2026-09-03T00:00:0${this.stamp}.000001+00:00`,
		};
		return [this.current];
	}

	async reload(): Promise<RunEditRow | null> {
		this.reloads++;
		return this.current;
	}
}

test('a swap on an unmoved row saves, filtered on the exact base string', async () => {
	const loaded = row();
	const server = new FakeServer(row());
	const out = await saveRunEdit(server, loaded, { title: 'Tempo', notes: 'flat' });
	assert.equal(out.kind, 'saved');
	assert.equal(server.swaps.length, 1);
	assert.equal(server.swaps[0].base, BASE_1, 'microseconds survive to the filter');
	assert.equal(server.current?.metadata?.title, 'Tempo');
	assert.equal(server.reloads, 0);
});

test('only the fields the runner changed are written', () => {
	const loaded = row();
	assert.deepEqual(changedEditFields(loaded, { title: 'Tempo', notes: 'flat' }), { title: 'Tempo' });
	assert.deepEqual(changedEditFields(loaded, { title: ' Easy ', notes: 'flat' }), {});
	assert.deepEqual(changedEditFields(loaded, { title: 'Easy', notes: '' }), { notes: '' });
});

test('an untouched dialog writes nothing', async () => {
	const server = new FakeServer(row());
	const out = await saveRunEdit(server, row(), { title: 'Easy', notes: 'flat' });
	assert.equal(out.kind, 'saved');
	assert.equal(server.swaps.length, 0);
});

test('a row moved in another field is re-read and the edit re-applied on top', async () => {
	const loaded = row();
	const server = new FakeServer(
		row({ updated_at: BASE_2, metadata: { title: 'Easy', notes: 'Web notes', activity_type: 'run' } }),
	);
	const out = await saveRunEdit(server, loaded, { title: 'Tempo', notes: 'flat' });
	assert.equal(out.kind, 'saved');
	assert.deepEqual(
		server.swaps.map((s) => s.base),
		[BASE_1, BASE_2],
	);
	assert.equal(server.current?.metadata?.title, 'Tempo');
	assert.equal(server.current?.metadata?.notes, 'Web notes', 'the other change survives');
});

test('a row moved in the same field is a conflict and nothing is written', async () => {
	const loaded = row();
	const moved = row({ updated_at: BASE_2, metadata: { title: 'Web title', notes: 'flat' } });
	const server = new FakeServer(moved);
	const out = await saveRunEdit(server, loaded, { title: 'Phone title', notes: 'flat' });
	assert.equal(out.kind, 'conflict');
	assert.equal(out.kind === 'conflict' && out.row.metadata?.title, 'Web title');
	assert.equal(server.swaps.length, 1);
	assert.equal(server.current?.metadata?.title, 'Web title');
});

test('a DNF toggle conflicts with another writer toggling it', async () => {
	const loaded = row();
	const server = new FakeServer(row({ updated_at: BASE_2, is_dnf: true }));
	const out = await saveRunEdit(server, loaded, { title: 'Easy', notes: 'flat' }, true);
	assert.equal(out.kind, 'conflict');
	assert.equal(editedFieldsMoved(loaded, server.current!, {}, true), true);
	assert.equal(editedFieldsMoved(loaded, server.current!, {}, undefined), false);
});

test('losing the re-applied swap too reports a conflict with the latest row', async () => {
	const loaded = row();
	const server = new FakeServer(row({ updated_at: BASE_2 }));
	server.beforeSwap.push(
		() => {},
		() => {
			server.current = row({ updated_at: '2026-09-02T10:00:00.000001+00:00' });
		},
	);
	const out = await saveRunEdit(server, loaded, { title: 'Tempo' });
	assert.equal(out.kind, 'conflict');
	assert.equal(server.swaps.length, 2);
	assert.equal(server.current?.metadata?.title, 'Easy');
});

test('a row deleted elsewhere is gone', async () => {
	const server = new FakeServer(null);
	const out = await saveRunEdit(server, row(), { title: 'Tempo' });
	assert.equal(out.kind, 'gone');
});

test('the patch carries the bag without a device clock, and is_dnf only when toggled', () => {
	const patch = runEditPatch(row(), { title: 'Tempo' });
	assert.deepEqual(Object.keys(patch), ['metadata']);
	assert.equal(Object.prototype.hasOwnProperty.call(patch.metadata, 'last_modified_at'), false);
	assert.equal(patch.metadata.notes, 'flat');
	assert.deepEqual(Object.keys(runEditPatch(row(), {}, true)).sort(), ['is_dnf', 'metadata']);
});
