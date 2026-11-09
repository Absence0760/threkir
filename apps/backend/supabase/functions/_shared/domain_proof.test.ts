// Pins _shared/domain_proof.ts: the DNS TXT and .well-known proof checks for
// club verification (issue #1190 § 2, decisions § 2398), including every SSRF
// refusal on the file fetch. Network-free: `fetch` is a fake that answers the
// DoH resolver and the organiser's host from tables.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	checkDomainProof,
	DOH_URL,
	isAllowedProofUrl,
	isInconclusive,
	isPublicAddress,
	isValidDomain,
	joinTxt,
	type ProofDeps,
	proofRecord,
	WELL_KNOWN_MAX_BYTES,
	WELL_KNOWN_PATH,
} from './domain_proof.ts';

const TOKEN = '0123456789abcdef0123456789abcdef';
const DOMAIN = 'race.example.org';

type Dns = Record<string, { A?: string[]; AAAA?: string[]; TXT?: string[] }>;
type Http = Record<string, () => Response>;

interface Fake {
	deps: ProofDeps;
	requested: string[];
}

function fake(dns: Dns, http: Http = {}, opts: { resolverDown?: boolean } = {}): Fake {
	const requested: string[] = [];
	const deps: ProofDeps = {
		fetch: (input: string, init?: RequestInit) => {
			requested.push(input);
			if (input.startsWith(DOH_URL)) {
				if (opts.resolverDown) return Promise.resolve(new Response('down', { status: 502 }));
				const u = new URL(input);
				const name = u.searchParams.get('name')!;
				const type = u.searchParams.get('type') as 'A' | 'AAAA' | 'TXT';
				const rec = dns[name];
				if (!rec) return Promise.resolve(Response.json({ Status: 3 }));
				const code = { A: 1, AAAA: 28, TXT: 16 }[type];
				const answers = (rec[type] ?? []).map((data) => ({
					name: `${name}.`,
					type: code,
					data: type === 'TXT' ? `"${data}"` : data,
				}));
				return Promise.resolve(Response.json({ Status: 0, Answer: answers }));
			}
			assertEquals(init?.redirect, 'manual', 'the proof file is never fetched with automatic redirects');
			const handler = http[input];
			if (!handler) return Promise.reject(new TypeError('connection refused'));
			return Promise.resolve(handler());
		},
		timeoutMs: 2_000,
	};
	return { deps, requested };
}

const PUBLIC_HOST = { A: ['93.184.216.34'], AAAA: ['2606:2800:220:1:248:1893:25c8:1946'] };
const fileUrl = (host: string) => `https://${host}${WELL_KNOWN_PATH}`;

// ── shapes ──────────────────────────────────────────────────────────────────

Deno.test('a domain is a dotted hostname, never an IP literal', () => {
	assert(isValidDomain('race.example.org'));
	assert(!isValidDomain('192.168.1.1'));
	assert(!isValidDomain('localhost'));
	assert(!isValidDomain('exa mple.com'));
	assert(!isValidDomain('-bad.example.com'));
});

Deno.test('a TXT record split across strings is joined', () => {
	assertEquals(joinTxt('"threkir-verification=" "abc"'), 'threkir-verification=abc');
	assertEquals(joinTxt('plain'), 'plain');
});

Deno.test('only global unicast addresses are public', () => {
	for (const ip of ['93.184.216.34', '8.8.8.8', '2606:4700::1111']) assert(isPublicAddress(ip), ip);
	for (
		const ip of [
			'127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.1.1', '169.254.169.254',
			'100.64.0.1', '0.0.0.0', '224.0.0.1', '255.255.255.255', '198.18.0.1', '192.0.2.1',
			'::1', '::', 'fe80::1', 'fc00::1', 'fd12:3456::1', 'ff02::1', '::ffff:127.0.0.1',
			'::ffff:169.254.169.254', '2001:db8::1', '2002:c0a8:101::1', '64:ff9b::a9fe:a9fe',
			'fe80::1%eth0', 'not-an-ip', '1.2.3', '999.1.1.1',
		]
	) assert(!isPublicAddress(ip), ip);
	assert(isPublicAddress('::ffff:8.8.8.8'), 'an IPv4-mapped public address is public');
});

Deno.test('the proof URL must be https on the claimed domain or its www', () => {
	assert(isAllowedProofUrl(new URL(fileUrl(DOMAIN)), DOMAIN));
	assert(isAllowedProofUrl(new URL(fileUrl(`www.${DOMAIN}`)), DOMAIN));
	assert(!isAllowedProofUrl(new URL(`http://${DOMAIN}${WELL_KNOWN_PATH}`), DOMAIN));
	assert(!isAllowedProofUrl(new URL(`https://${DOMAIN}:8443${WELL_KNOWN_PATH}`), DOMAIN));
	assert(!isAllowedProofUrl(new URL(`https://u:p@${DOMAIN}${WELL_KNOWN_PATH}`), DOMAIN));
	assert(!isAllowedProofUrl(new URL(`https://evil.${DOMAIN}${WELL_KNOWN_PATH}`), DOMAIN));
	assert(!isAllowedProofUrl(new URL(`https://${DOMAIN}.evil.com${WELL_KNOWN_PATH}`), DOMAIN));
});

// ── DNS TXT ─────────────────────────────────────────────────────────────────

Deno.test('a TXT record at _threkir-verification passes', async () => {
	const { deps, requested } = fake({ [`_threkir-verification.${DOMAIN}`]: { TXT: [proofRecord(TOKEN)] } });
	const r = await checkDomainProof(DOMAIN, TOKEN, deps);
	assertEquals(r.verified, true);
	assertEquals(r.method, 'dns_txt');
	assertEquals(r.detail, `TXT _threkir-verification.${DOMAIN}`);
	assert(requested.every((u) => u.startsWith(DOH_URL)), 'a DNS pass never touches the organiser host');
});

Deno.test('a TXT record at the apex passes', async () => {
	const { deps } = fake({ [DOMAIN]: { TXT: ['v=spf1 -all', proofRecord(TOKEN)] } });
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, deps)).method, 'dns_txt');
});

Deno.test('a TXT record for another token does not pass', async () => {
	const { deps } = fake({ [`_threkir-verification.${DOMAIN}`]: { TXT: [proofRecord('f'.repeat(32))] } });
	const r = await checkDomainProof(DOMAIN, TOKEN, deps);
	assertEquals(r.verified, false);
	assertEquals(r.checks.dns_txt, 'not_found');
});

Deno.test('a bare token at the apex TXT does not pass (the prefix is required)', async () => {
	const { deps } = fake({ [DOMAIN]: { TXT: [TOKEN] } });
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, deps)).checks.dns_txt, 'not_found');
});

Deno.test('a resolver outage is inconclusive, not a failure of the domain', async () => {
	const { deps } = fake({}, {}, { resolverDown: true });
	const r = await checkDomainProof(DOMAIN, TOKEN, deps);
	assertEquals(r.verified, false);
	assertEquals(r.checks.dns_txt, 'resolver_error');
	assertEquals(r.checks.well_known, 'resolver_error');
	assert(isInconclusive(r));
});

// ── .well-known ─────────────────────────────────────────────────────────────

Deno.test('the file on the apex with the prefixed token passes', async () => {
	const { deps } = fake({ [DOMAIN]: PUBLIC_HOST }, {
		[fileUrl(DOMAIN)]: () => new Response(`# Threkir\n${proofRecord(TOKEN)}\n`),
	});
	const r = await checkDomainProof(DOMAIN, TOKEN, deps);
	assertEquals(r.verified, true);
	assertEquals(r.method, 'well_known');
	assertEquals(r.detail, fileUrl(DOMAIN));
});

Deno.test('the file with the bare token on its own line passes', async () => {
	const { deps } = fake({ [DOMAIN]: PUBLIC_HOST }, { [fileUrl(DOMAIN)]: () => new Response(`${TOKEN}\r\n`) });
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, deps)).method, 'well_known');
});

Deno.test('the token inside other text does not pass', async () => {
	const { deps } = fake({ [DOMAIN]: PUBLIC_HOST }, {
		[fileUrl(DOMAIN)]: () => new Response(`<p>not ${TOKEN} here</p>`),
	});
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, deps)).checks.well_known, 'not_found');
});

Deno.test('a redirect from the apex to www on the same domain is followed', async () => {
	const www = `www.${DOMAIN}`;
	const { deps } = fake({ [DOMAIN]: PUBLIC_HOST, [www]: PUBLIC_HOST }, {
		[fileUrl(DOMAIN)]: () => new Response(null, { status: 301, headers: { location: fileUrl(www) } }),
		[fileUrl(www)]: () => new Response(proofRecord(TOKEN)),
	});
	const r = await checkDomainProof(DOMAIN, TOKEN, deps);
	assertEquals(r.method, 'well_known');
	assertEquals(r.detail, fileUrl(www));
});

Deno.test('SSRF: a host that resolves to a private address is refused before any request to it', async () => {
	for (const ip of ['10.0.0.5', '127.0.0.1', '169.254.169.254']) {
		const { deps, requested } = fake({ [DOMAIN]: { A: [ip] }, [`www.${DOMAIN}`]: { A: [ip] } }, {
			[fileUrl(DOMAIN)]: () => new Response(proofRecord(TOKEN)),
		});
		const r = await checkDomainProof(DOMAIN, TOKEN, deps);
		assertEquals(r.verified, false, ip);
		assertEquals(r.checks.well_known, 'refused_address', ip);
		assert(!requested.some((u) => !u.startsWith(DOH_URL)), `${ip}: nothing but the resolver was requested`);
	}
});

Deno.test('SSRF: one private address among public ones is enough to refuse', async () => {
	const { deps, requested } = fake({ [DOMAIN]: { A: ['93.184.216.34', '192.168.0.10'] } }, {
		[fileUrl(DOMAIN)]: () => new Response(proofRecord(TOKEN)),
	});
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, deps)).checks.well_known, 'refused_address');
	assert(!requested.includes(fileUrl(DOMAIN)));
});

Deno.test('SSRF: a private IPv6 address is refused', async () => {
	const { deps } = fake({ [DOMAIN]: { AAAA: ['fd00::1'] }, [`www.${DOMAIN}`]: { AAAA: ['::1'] } }, {});
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, deps)).checks.well_known, 'refused_address');
});

Deno.test('SSRF: a redirect to another host is refused and not followed', async () => {
	const { deps, requested } = fake({ [DOMAIN]: PUBLIC_HOST, 'attacker.example.net': PUBLIC_HOST }, {
		[fileUrl(DOMAIN)]: () =>
			new Response(null, { status: 302, headers: { location: 'https://attacker.example.net/token' } }),
	});
	const r = await checkDomainProof(DOMAIN, TOKEN, deps);
	assertEquals(r.checks.well_known, 'refused_redirect');
	assert(!requested.some((u) => new URL(u).hostname === 'attacker.example.net'));
});

Deno.test('SSRF: a redirect to an internal address on a lookalike path is refused', async () => {
	const { deps, requested } = fake({ [DOMAIN]: PUBLIC_HOST }, {
		[fileUrl(DOMAIN)]: () =>
			new Response(null, { status: 307, headers: { location: 'http://169.254.169.254/latest/meta-data/' } }),
	});
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, deps)).checks.well_known, 'refused_redirect');
	assert(!requested.some((u) => u.includes('169.254.169.254')));
});

Deno.test('SSRF: a redirect down to plain http on the same host is refused', async () => {
	const { deps } = fake({ [DOMAIN]: PUBLIC_HOST }, {
		[fileUrl(DOMAIN)]: () =>
			new Response(null, { status: 301, headers: { location: `http://${DOMAIN}${WELL_KNOWN_PATH}` } }),
	});
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, deps)).checks.well_known, 'refused_redirect');
});

Deno.test('SSRF: a redirect loop stops after the cap', async () => {
	let hits = 0;
	const { deps } = fake({ [DOMAIN]: PUBLIC_HOST }, {
		[fileUrl(DOMAIN)]: () => {
			hits++;
			return new Response(null, { status: 302, headers: { location: WELL_KNOWN_PATH } });
		},
	});
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, deps)).checks.well_known, 'refused_redirect');
	assert(hits <= 4, `followed ${hits} hops`);
});

Deno.test('SSRF: a body past the cap is refused, by declared length or by streaming', async () => {
	const big = 'x'.repeat(WELL_KNOWN_MAX_BYTES) + `\n${proofRecord(TOKEN)}`;
	const declared = fake({ [DOMAIN]: PUBLIC_HOST }, { [fileUrl(DOMAIN)]: () => new Response(big) });
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, declared.deps)).checks.well_known, 'too_large');

	const streamed = fake({ [DOMAIN]: PUBLIC_HOST }, {
		[fileUrl(DOMAIN)]: () =>
			new Response(
				new ReadableStream({
					start(c) {
						c.enqueue(new TextEncoder().encode(big));
						c.close();
					},
				}),
			),
	});
	assertEquals((await checkDomainProof(DOMAIN, TOKEN, streamed.deps)).checks.well_known, 'too_large');
});

Deno.test('a host that never answers is bounded by the deadline', async () => {
	const deps: ProofDeps = {
		fetch: (input: string, init?: RequestInit) => {
			if (input.startsWith(DOH_URL)) {
				const name = new URL(input).searchParams.get('name')!;
				const type = new URL(input).searchParams.get('type');
				const answers = name === DOMAIN && type === 'A' ? [{ type: 1, data: '93.184.216.34' }] : [];
				return Promise.resolve(Response.json({ Status: 0, Answer: answers }));
			}
			return new Promise((_, reject) => {
				init?.signal?.addEventListener('abort', () => reject(init.signal!.reason));
			});
		},
		timeoutMs: 50,
	};
	const started = Date.now();
	const r = await checkDomainProof(DOMAIN, TOKEN, deps);
	assertEquals(r.checks.well_known, 'timeout');
	assert(Date.now() - started < 2_000);
});

Deno.test('an invalid domain makes no request at all', async () => {
	const { deps, requested } = fake({});
	const r = await checkDomainProof('10.0.0.1', TOKEN, deps);
	assertEquals(r.verified, false);
	assertEquals(requested.length, 0);
});
