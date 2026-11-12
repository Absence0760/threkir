#!/usr/bin/env node
//
// Serves apps/web's adapter-static output the way CloudFront does, for the
// built-app Playwright lane (playwright.built.config.ts).
//
// Not `vite preview`: preview resolves the vite config with command 'serve',
// so it runs the env-isolation guard and SvelteKit's env validation against a
// process that has no business holding the build's env, and its SPA fallback
// is Kit's own rather than the deploy's. Production is an S3 bucket behind
// CloudFront: a key that exists is served as-is, an extensionless path is the
// prerendered `<path>.html` when one was emitted, and anything else is the
// `200.html` shell (CloudFront's 403 -> shell mapping in
// infra/modules/web-stack/main.tf). This mirrors exactly that and nothing
// more, with the stdlib only.
//
// Usage: node tests-e2e/scripts/serve-build.mjs <port> [build-dir]

import { createReadStream, statSync } from 'node:fs';
import http from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';

const PORT = Number(process.argv[2]);
if (!Number.isInteger(PORT) || PORT <= 0) {
	console.error('usage: serve-build.mjs <port> [build-dir]');
	process.exit(2);
}
const ROOT = resolve(process.argv[3] ?? join(import.meta.dirname, '..', '..', 'build'));
const SHELL = '200.html';

/** @type {Record<string, string>} */
const TYPES = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript; charset=utf-8',
	'.mjs': 'text/javascript; charset=utf-8',
	'.css': 'text/css; charset=utf-8',
	'.json': 'application/json; charset=utf-8',
	'.webmanifest': 'application/manifest+json',
	'.svg': 'image/svg+xml',
	'.png': 'image/png',
	'.jpg': 'image/jpeg',
	'.ico': 'image/x-icon',
	'.webp': 'image/webp',
	'.avif': 'image/avif',
	'.woff2': 'font/woff2',
	'.txt': 'text/plain; charset=utf-8',
	'.xml': 'application/xml; charset=utf-8',
	'.wasm': 'application/wasm',
	'.pmtiles': 'application/octet-stream',
};

/** @param {string} path */
function isFile(path) {
	try {
		return statSync(path).isFile();
	} catch {
		return false;
	}
}

/**
 * The file a request path resolves to, or null when it would escape ROOT.
 * @param {string} pathname
 * @returns {string | null}
 */
function resolveFile(pathname) {
	let decoded;
	try {
		decoded = decodeURIComponent(pathname);
	} catch {
		return null;
	}
	const candidate = normalize(join(ROOT, decoded));
	if (candidate !== ROOT && !candidate.startsWith(ROOT + sep)) return null;
	if (isFile(candidate)) return candidate;
	const trimmed = candidate.endsWith(sep) ? candidate.slice(0, -1) : candidate;
	if (isFile(`${trimmed}.html`)) return `${trimmed}.html`;
	if (isFile(join(trimmed, 'index.html'))) return join(trimmed, 'index.html');
	return join(ROOT, SHELL);
}

if (!isFile(join(ROOT, SHELL))) {
	console.error(`serve-build: ${join(ROOT, SHELL)} is missing — run \`vite build\` first.`);
	process.exit(1);
}

http
	.createServer((req, res) => {
		if (req.method !== 'GET' && req.method !== 'HEAD') {
			res.writeHead(405).end();
			return;
		}
		const { pathname } = new URL(req.url ?? '/', 'http://build.invalid');
		const file = resolveFile(pathname);
		if (!file) {
			res.writeHead(400).end();
			return;
		}
		res.writeHead(200, {
			'content-type': TYPES[extname(file)] ?? 'application/octet-stream',
			'cache-control': 'no-store',
		});
		if (req.method === 'HEAD') {
			res.end();
			return;
		}
		createReadStream(file).pipe(res);
	})
	.listen(PORT, '127.0.0.1', () => {
		console.log(`serve-build: ${ROOT} on 127.0.0.1:${PORT}`);
	});
