#!/usr/bin/env node
// Prints production's PostgREST `max_rows` and nothing else, for the
// "PostgREST row cap" sync stage (lib/postgrest_cap.mjs). The Management API's
// PostgREST config response also carries the project's JWT secret, so only the
// one integer field leaves this process; the token and ref come from the
// environment and are never printed.

const ref = process.env.SUPABASE_PROJECT_REF ?? '';
const token = process.env.SUPABASE_ACCESS_TOKEN ?? '';
if (!/^[a-z0-9]{20}$/.test(ref) || !token) {
	console.error('SUPABASE_PROJECT_REF or SUPABASE_ACCESS_TOKEN is unset');
	process.exit(2);
}

const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/postgrest`, {
	headers: { authorization: `Bearer ${token}`, accept: 'application/json' },
	signal: AbortSignal.timeout(30_000),
});
if (!res.ok) {
	console.error(`the Management API answered ${res.status}`);
	process.exit(1);
}
const body = /** @type {{ max_rows?: unknown } | null} */ (await res.json());
const maxRows = body?.max_rows;
if (typeof maxRows !== 'number' || !Number.isInteger(maxRows) || maxRows < 0) {
	console.error('the response has no integer max_rows');
	process.exit(1);
}
process.stdout.write(`${maxRows}\n`);
