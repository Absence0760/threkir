// Unit tests for scripts/rpc_transport.mjs, the migration replay both
// client transport guards read.
//
// Run: node --test scripts/rpc_transport.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import { byName, explain, loadFunctions, parseArgs, replayFunctions, takesGet } from './rpc_transport.mjs';

/** @param {string[]} sqls */
const replay = (...sqls) => byName(replayFunctions(sqls.map((sql, i) => ({ file: `${i}.sql`, sql }))));

test('the last definition of a signature wins, and an alter re-declares it', () => {
	const fns = replay(
		'create function public.f(p_id uuid) returns int language sql stable as $$ select 1 $$;',
		'create or replace function f(p_id uuid) returns int language sql as $$ select 2 $$;',
		'alter function public.f(uuid) stable;'
	);
	assert.equal(fns.get('f')?.volatility, 'stable');
	assert.equal(fns.get('f')?.file, '1.sql');
});

test('a keyword inside a function body or a literal does not answer for its header', () => {
	const fns = replay(
		"create function f(p text default 'stable') returns text language plpgsql as $$ begin -- stable\n return 'immutable'; end $$;"
	);
	assert.equal(fns.get('f')?.volatility, 'volatile');
});

test('drop removes a signature, a bare drop every overload, set schema the function', () => {
	assert.equal(replay('create function f(a int) returns int language sql as $$ select 1 $$;', 'drop function f(integer);').size, 0);
	assert.equal(replay('create function f(a int) returns int language sql as $$ select 1 $$;', 'drop function if exists f;').size, 0);
	assert.equal(replay('create function f(a int) returns int language sql as $$ select 1 $$;', 'alter function f(int) set schema private;').size, 0);
	assert.equal(replay('create function private.f(a int) returns int language sql as $$ select 1 $$;').size, 0);
});

test('two live overloads of one name are refused rather than guessed between', () => {
	assert.throws(
		() =>
			replay(
				'create function f(a int) returns int language sql as $$ select 1 $$;',
				'create function f(a text) returns int language sql as $$ select 1 $$;'
			),
		/more than one live overload/
	);
});

test('arguments carry their type, their default, and whether that default is NULL', () => {
	assert.deepEqual(parseArgs("p_a uuid, p_b text default null, p_c int = 5, out x int, p_d varchar(4) default null::text, p_e text default 'n'"), [
		{ name: 'p_a', type: 'uuid', hasDefault: false, defaultIsNull: false },
		{ name: 'p_b', type: 'text', hasDefault: true, defaultIsNull: true },
		{ name: 'p_c', type: 'integer', hasDefault: true, defaultIsNull: false },
		{ name: 'p_d', type: 'character varying', hasDefault: true, defaultIsNull: true },
		{ name: 'p_e', type: 'text', hasDefault: true, defaultIsNull: false }
	]);
});

test('a GET needs stable or immutable, scalar inputs, and no directive-named argument', () => {
	const fns = replay(
		'create function ok(p uuid) returns int language sql stable as $$ select 1 $$;',
		'create function writes(p uuid) returns int language sql as $$ select 1 $$;',
		'create function obj(p jsonb) returns int language sql stable as $$ select 1 $$;',
		'create function arr(p uuid[]) returns int language sql immutable as $$ select 1 $$;',
		'create function reserved("limit" int) returns int language sql stable as $$ select 1 $$;'
	);
	const verdict = Object.fromEntries([...fns].map(([n, fn]) => [n, takesGet(fn)]));
	assert.deepEqual(verdict, { ok: true, writes: false, obj: false, arr: false, reserved: false });
	assert.match(explain(/** @type {any} */ (fns.get('obj'))), /^stable, cannot be a query parameter: p jsonb/);
});

test('the committed migrations replay to a live set the guards can use', () => {
	const fns = loadFunctions();
	assert.ok(fns.size >= 200, `only ${fns.size} public functions parsed`);
	assert.equal(fns.get('route_markers_for_viewer')?.volatility, 'stable');
	assert.equal(fns.get('routes_intersecting_track')?.args[1].type, 'jsonb');
	assert.equal(fns.get('clear_discoverable_area')?.volatility, 'volatile');
	assert.equal(fns.get('search_public_events')?.args.find((a) => a.name === 'p_query')?.defaultIsNull, true);
});
