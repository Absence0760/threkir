/// Domain-control proof for club verification (issue #1190 § 2, decisions
/// § 2398): a DNS TXT record or a `/.well-known/threkir-verification` file on
/// the club's claimed domain carrying the request's token.
///
/// Both checks take an injected `fetch`, so the tests drive every branch
/// without the network. DNS is read over DNS-over-HTTPS from one fixed
/// resolver, never the runtime's own resolver, so the TXT read and the address
/// screen below see the same answers.
///
/// The `.well-known` fetch is the one request this codebase makes to a host a
/// user chose, so it is fenced (SSRF):
///   * https only, port 443 only, no credentials in the URL;
///   * the claimed domain and its `www.` only — a redirect anywhere else, or
///     to plain http, is refused, and at most three redirects are followed;
///   * every hop's host is resolved first and refused when ANY of its
///     addresses is loopback, private, link-local, carrier-grade NAT,
///     multicast, documentation, benchmarking or otherwise not global unicast
///     (cloud metadata at 169.254.169.254 included);
///   * one deadline bounds the whole check, headers and body together;
///   * the body is read to 4 KiB and no further.
/// The fetch itself resolves the host again, so a DNS answer that changes
/// between the screen and the connect (rebinding) is not closed here. What
/// such a request can learn is bounded: the body is only compared with a
/// random token and is never returned, and the caller sees one coarse reason.

export const DOH_URL = 'https://cloudflare-dns.com/dns-query';
export const TXT_LABEL = '_threkir-verification';
export const WELL_KNOWN_PATH = '/.well-known/threkir-verification';
export const PROOF_PREFIX = 'threkir-verification=';
export const CHECK_TIMEOUT_MS = 8_000;
export const WELL_KNOWN_MAX_BYTES = 4_096;
export const MAX_REDIRECTS = 3;
export const USER_AGENT = 'Threkir-Verification/1.0 (+https://threkir.com/help)';

export type ProofMethod = 'dns_txt' | 'well_known';

/// Why a check did not pass. `resolver_error` and `timeout` say nothing about
/// the organiser's domain (our resolver, or the network, failed), so a re-check
/// does not count them against the club.
export type ProofOutcome =
	| 'ok'
	| 'not_found'
	| 'unreachable'
	| 'timeout'
	| 'resolver_error'
	| 'refused_address'
	| 'refused_redirect'
	| 'too_large';

export interface ProofDeps {
	fetch: (input: string, init?: RequestInit) => Promise<Response>;
	timeoutMs?: number;
}

export interface DomainProofResult {
	verified: boolean;
	/// The method that passed, when one did.
	method: ProofMethod | null;
	/// What is recorded beside the result: where the proof was found, or both
	/// outcomes when none was.
	detail: string;
	checks: Record<ProofMethod, ProofOutcome>;
}

const DOMAIN_RE = /^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$/;

/// The same rule as `private.club_website_domain` for a bare host: lower case,
/// dotted, letters-digits-hyphens labels, a last label that starts with a
/// letter (so never an IP literal), 4..253 characters.
export function isValidDomain(domain: string): boolean {
	return domain.length >= 4 && domain.length <= 253 && DOMAIN_RE.test(domain);
}

export function proofRecord(token: string): string {
	return `${PROOF_PREFIX}${token}`;
}

// ── address screen ──────────────────────────────────────────────────────────

function parseIPv4(ip: string): number[] | null {
	const parts = ip.split('.');
	if (parts.length !== 4) return null;
	const out: number[] = [];
	for (const p of parts) {
		if (!/^\d{1,3}$/.test(p)) return null;
		const n = Number(p);
		if (n > 255) return null;
		out.push(n);
	}
	return out;
}

function isPublicIPv4(o: number[]): boolean {
	const [a, b, c] = o;
	if (a === 0 || a === 10 || a === 127) return false;
	if (a === 100 && b >= 64 && b <= 127) return false; // carrier-grade NAT
	if (a === 169 && b === 254) return false; // link-local, cloud metadata
	if (a === 172 && b >= 16 && b <= 31) return false;
	if (a === 192 && b === 168) return false;
	if (a === 192 && b === 0 && (c === 0 || c === 2)) return false; // IETF, TEST-NET-1
	if (a === 192 && b === 88 && c === 99) return false; // 6to4 relay
	if (a === 198 && (b === 18 || b === 19)) return false; // benchmarking
	if (a === 198 && b === 51 && c === 100) return false; // TEST-NET-2
	if (a === 203 && b === 0 && c === 113) return false; // TEST-NET-3
	if (a >= 224) return false; // multicast, reserved, broadcast
	return true;
}

/// The eight 16-bit groups of an IPv6 address, or null when it is not one.
function parseIPv6(ip: string): number[] | null {
	let s = ip.toLowerCase();
	if (s.includes('%')) return null; // zone ids are link-local by definition
	let tail: number[] = [];
	const lastColon = s.lastIndexOf(':');
	if (s.includes('.')) {
		const v4 = parseIPv4(s.slice(lastColon + 1));
		if (!v4) return null;
		tail = [(v4[0] << 8) | v4[1], (v4[2] << 8) | v4[3]];
		const before = s.slice(0, lastColon);
		s = before.endsWith(':') ? `${before}:` : before;
	}
	const halves = s.split('::');
	if (halves.length > 2) return null;
	const toGroups = (h: string) => (h === '' ? [] : h.split(':'));
	const head = toGroups(halves[0]);
	const rest = halves.length === 2 ? toGroups(halves[1]) : [];
	const want = 8 - tail.length;
	const missing = want - head.length - rest.length;
	if (halves.length === 1 && missing !== 0) return null;
	if (halves.length === 2 && missing < 1) return null;
	const groups = [...head, ...Array(halves.length === 2 ? missing : 0).fill('0'), ...rest];
	const out: number[] = [];
	for (const g of groups) {
		if (!/^[0-9a-f]{1,4}$/.test(g)) return null;
		out.push(parseInt(g, 16));
	}
	return [...out, ...tail];
}

function isPublicIPv6(g: number[]): boolean {
	// Only global unicast (2000::/3) is reachable as a public host.
	if ((g[0] & 0xe000) !== 0x2000) {
		// ::ffff:a.b.c.d — an IPv4-mapped address is the IPv4 address.
		if (g.slice(0, 5).every((x) => x === 0) && g[5] === 0xffff) {
			return isPublicIPv4([g[6] >> 8, g[6] & 0xff, g[7] >> 8, g[7] & 0xff]);
		}
		return false;
	}
	if (g[0] === 0x2001 && g[1] < 0x0200) return false; // 2001::/23 IETF, Teredo
	if (g[0] === 0x2001 && g[1] === 0x0db8) return false; // documentation
	if (g[0] === 0x2002) return false; // 6to4 embeds an arbitrary IPv4
	return true;
}

/// Whether a resolved address is a public, global-unicast host. Anything that
/// does not parse is not public.
export function isPublicAddress(ip: string): boolean {
	const v4 = parseIPv4(ip);
	if (v4) return isPublicIPv4(v4);
	const v6 = parseIPv6(ip);
	if (v6) return isPublicIPv6(v6);
	return false;
}

// ── DNS over HTTPS ──────────────────────────────────────────────────────────

const RR_TYPE: Record<'A' | 'AAAA' | 'TXT', number> = { A: 1, AAAA: 28, TXT: 16 };

/// One DoH query. NXDOMAIN and an empty answer are `[]`; anything that is not
/// an answer from the resolver is `'resolver_error'` or `'timeout'`.
export async function resolve(
	name: string,
	type: 'A' | 'AAAA' | 'TXT',
	deps: ProofDeps,
	signal: AbortSignal,
): Promise<string[] | 'resolver_error' | 'timeout'> {
	const url = `${DOH_URL}?name=${encodeURIComponent(name)}&type=${type}`;
	let res: Response;
	try {
		res = await deps.fetch(url, { headers: { Accept: 'application/dns-json' }, signal, redirect: 'error' });
	} catch (err) {
		return isTimeout(err) ? 'timeout' : 'resolver_error';
	}
	if (!res.ok) {
		await res.body?.cancel().catch(() => {});
		return 'resolver_error';
	}
	let body: unknown;
	try {
		body = await res.json();
	} catch (err) {
		return isTimeout(err) ? 'timeout' : 'resolver_error';
	}
	if (body === null || typeof body !== 'object') return 'resolver_error';
	const b = body as { Status?: unknown; Answer?: unknown };
	if (b.Status === 3) return [];
	if (b.Status !== 0) return 'resolver_error';
	if (!Array.isArray(b.Answer)) return [];
	const out: string[] = [];
	for (const rr of b.Answer) {
		if (rr && typeof rr === 'object' && (rr as { type?: unknown }).type === RR_TYPE[type]) {
			const data = (rr as { data?: unknown }).data;
			if (typeof data === 'string') out.push(type === 'TXT' ? joinTxt(data) : data.trim());
		}
	}
	return out;
}

/// A TXT record's character strings joined, as a record split across
/// several 255-byte strings is one value: `"a" "b"` is `ab`.
export function joinTxt(data: string): string {
	const parts = [...data.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => m[1].replace(/\\(.)/g, '$1'));
	return parts.length > 0 ? parts.join('') : data.trim();
}

function isTimeout(err: unknown): boolean {
	return err instanceof DOMException && (err.name === 'TimeoutError' || err.name === 'AbortError');
}

// ── the two checks ──────────────────────────────────────────────────────────

/// A `threkir-verification=<token>` TXT record at `_threkir-verification.<domain>`
/// or at the domain itself.
export async function checkDnsTxt(
	domain: string,
	token: string,
	deps: ProofDeps,
	signal: AbortSignal,
): Promise<{ outcome: ProofOutcome; at: string | null }> {
	if (!isValidDomain(domain)) return { outcome: 'not_found', at: null };
	const want = proofRecord(token);
	let inconclusive: ProofOutcome | null = null;
	for (const name of [`${TXT_LABEL}.${domain}`, domain]) {
		const records = await resolve(name, 'TXT', deps, signal);
		if (records === 'resolver_error' || records === 'timeout') {
			inconclusive = records;
			continue;
		}
		if (records.some((r) => r.trim() === want)) return { outcome: 'ok', at: name };
	}
	return { outcome: inconclusive ?? 'not_found', at: null };
}

/// Every address the host resolves to, refused when any is not public.
async function screenHost(
	host: string,
	deps: ProofDeps,
	signal: AbortSignal,
): Promise<ProofOutcome | null> {
	const [a, aaaa] = await Promise.all([
		resolve(host, 'A', deps, signal),
		resolve(host, 'AAAA', deps, signal),
	]);
	if (a === 'timeout' || aaaa === 'timeout') return 'timeout';
	if (a === 'resolver_error' || aaaa === 'resolver_error') return 'resolver_error';
	const addrs = [...a, ...aaaa];
	if (addrs.length === 0) return 'unreachable';
	if (addrs.some((ip) => !isPublicAddress(ip))) return 'refused_address';
	return null;
}

/// The only URLs the file check will request: https, default port, no
/// credentials, on the claimed domain or its `www.`.
export function isAllowedProofUrl(url: URL, domain: string): boolean {
	return url.protocol === 'https:' &&
		(url.port === '' || url.port === '443') &&
		url.username === '' &&
		url.password === '' &&
		(url.hostname === domain || url.hostname === `www.${domain}`);
}

/// Reads at most `max` bytes; null when the body is longer.
async function readCapped(res: Response, max: number): Promise<string | null> {
	const declared = Number(res.headers.get('content-length'));
	if (Number.isFinite(declared) && declared > max) {
		await res.body?.cancel().catch(() => {});
		return null;
	}
	if (!res.body) return '';
	const reader = res.body.getReader();
	const chunks: Uint8Array[] = [];
	let size = 0;
	while (true) {
		const { done, value } = await reader.read();
		if (done) break;
		size += value.byteLength;
		if (size > max) {
			await reader.cancel().catch(() => {});
			return null;
		}
		chunks.push(value);
	}
	const buf = new Uint8Array(size);
	let off = 0;
	for (const c of chunks) {
		buf.set(c, off);
		off += c.byteLength;
	}
	return new TextDecoder().decode(buf);
}

/// The token in `https://<domain>/.well-known/threkir-verification`, on a line
/// of its own as `threkir-verification=<token>` or the bare token. The apex is
/// tried first, then `www.`.
export async function checkWellKnown(
	domain: string,
	token: string,
	deps: ProofDeps,
	signal: AbortSignal,
): Promise<{ outcome: ProofOutcome; at: string | null }> {
	if (!isValidDomain(domain)) return { outcome: 'not_found', at: null };
	let last: ProofOutcome = 'not_found';
	for (const host of [domain, `www.${domain}`]) {
		const r = await fetchProofFile(new URL(`https://${host}${WELL_KNOWN_PATH}`), domain, token, deps, signal);
		if (r.outcome === 'ok') return r;
		// A refusal is a finding about the domain, so it wins over a plain miss
		// on the other host when the result is reported.
		if (r.outcome !== 'not_found' && r.outcome !== 'unreachable') last = r.outcome;
		if (r.outcome === 'timeout') break;
	}
	return { outcome: last, at: null };
}

async function fetchProofFile(
	start: URL,
	domain: string,
	token: string,
	deps: ProofDeps,
	signal: AbortSignal,
): Promise<{ outcome: ProofOutcome; at: string | null }> {
	let url = start;
	for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
		if (!isAllowedProofUrl(url, domain)) return { outcome: 'refused_redirect', at: null };
		const screened = await screenHost(url.hostname, deps, signal);
		if (screened) return { outcome: screened, at: null };

		let res: Response;
		try {
			res = await deps.fetch(url.toString(), {
				redirect: 'manual',
				signal,
				headers: { 'User-Agent': USER_AGENT, Accept: 'text/plain' },
			});
		} catch (err) {
			return { outcome: isTimeout(err) ? 'timeout' : 'unreachable', at: null };
		}

		if (res.status >= 300 && res.status < 400) {
			const location = res.headers.get('location');
			await res.body?.cancel().catch(() => {});
			if (!location) return { outcome: 'not_found', at: null };
			let next: URL;
			try {
				next = new URL(location, url);
			} catch {
				return { outcome: 'refused_redirect', at: null };
			}
			url = next;
			continue;
		}
		if (!res.ok) {
			await res.body?.cancel().catch(() => {});
			return { outcome: 'not_found', at: null };
		}
		let text: string | null;
		try {
			text = await readCapped(res, WELL_KNOWN_MAX_BYTES);
		} catch (err) {
			return { outcome: isTimeout(err) ? 'timeout' : 'unreachable', at: null };
		}
		if (text === null) return { outcome: 'too_large', at: null };
		const want = proofRecord(token);
		const found = text.split(/\r?\n/).some((line) => {
			const l = line.trim();
			return l === want || l === token;
		});
		return found ? { outcome: 'ok', at: url.toString() } : { outcome: 'not_found', at: null };
	}
	return { outcome: 'refused_redirect', at: null };
}

/// Both checks under one deadline; DNS first, as it is the cheaper and the
/// one that touches no organiser server.
export async function checkDomainProof(
	domain: string,
	token: string,
	deps: ProofDeps,
): Promise<DomainProofResult> {
	const signal = AbortSignal.timeout(deps.timeoutMs ?? CHECK_TIMEOUT_MS);
	const dns = await checkDnsTxt(domain, token, deps, signal);
	if (dns.outcome === 'ok') {
		return {
			verified: true,
			method: 'dns_txt',
			detail: `TXT ${dns.at}`,
			checks: { dns_txt: 'ok', well_known: 'not_found' },
		};
	}
	const file = await checkWellKnown(domain, token, deps, signal);
	if (file.outcome === 'ok') {
		return {
			verified: true,
			method: 'well_known',
			detail: file.at ?? WELL_KNOWN_PATH,
			checks: { dns_txt: dns.outcome, well_known: 'ok' },
		};
	}
	return {
		verified: false,
		method: null,
		detail: `dns_txt: ${dns.outcome}; well_known: ${file.outcome}`,
		checks: { dns_txt: dns.outcome, well_known: file.outcome },
	};
}

/// Whether a failed result says nothing about the domain: every check failed
/// on our side (the resolver or the deadline), so a re-check must not count it.
export function isInconclusive(r: DomainProofResult): boolean {
	const ours = (o: ProofOutcome) => o === 'resolver_error' || o === 'timeout';
	return !r.verified && ours(r.checks.dns_txt) && ours(r.checks.well_known);
}
