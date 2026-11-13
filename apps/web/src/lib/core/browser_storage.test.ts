import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { localStore, sessionStore } from './browser_storage.js';
import { browserReturnStore } from './pending_return.js';
import { browserSessionStore } from './signup_source.js';
import { loadTheme, applyTheme } from '../settings/theme.js';
import { loadGoals, saveGoals } from '../training/goals.js';
import { DEFAULT_SHARE_LOOK, loadShareLook } from '../share/share_look.js';

// Firefox with site data blocked, and Safari in a sandboxed frame, throw from
// the storage getter itself (Sentry THREKIR-CLIENT-9, "SecurityError: The
// operation is insecure." on /clubs/[slug]/events/[id]).
class SecurityError extends Error {
	override name = 'SecurityError';
}

const KEYS = ['localStorage', 'sessionStorage'] as const;
const saved = new Map<string, PropertyDescriptor | undefined>();

function blockStorage() {
	for (const k of KEYS) {
		saved.set(k, Object.getOwnPropertyDescriptor(globalThis, k));
		Object.defineProperty(globalThis, k, {
			configurable: true,
			get() {
				throw new SecurityError('The operation is insecure.');
			},
		});
	}
}

function restoreStorage() {
	for (const k of KEYS) {
		const d = saved.get(k);
		if (d) Object.defineProperty(globalThis, k, d);
		else delete (globalThis as Record<string, unknown>)[k];
	}
	saved.clear();
}

beforeEach(blockStorage);
afterEach(restoreStorage);

test('the typeof guard is no guard: it throws through a blocked getter', () => {
	assert.throws(() => typeof localStorage === 'undefined', SecurityError);
});

test('blocked storage reads as none, not as a throw', () => {
	assert.equal(localStore(), null);
	assert.equal(sessionStore(), null);
	assert.equal(browserReturnStore(), null);
	assert.equal(browserSessionStore(), null);
});

test('the root layout theme bootstrap falls back to auto on blocked storage', () => {
	assert.equal(loadTheme(), 'auto');
	assert.doesNotThrow(() => applyTheme('dark'));
});

test('goals and the share look keep their defaults on blocked storage', () => {
	assert.deepEqual(loadGoals('u1'), []);
	assert.doesNotThrow(() => saveGoals('u1', []));
	assert.deepEqual(loadShareLook(), DEFAULT_SHARE_LOOK);
});

test('with storage present the helpers hand it back', () => {
	restoreStorage();
	const fake = { getItem: () => null } as unknown as Storage;
	(globalThis as Record<string, unknown>).localStorage = fake;
	try {
		assert.equal(localStore(), fake);
	} finally {
		delete (globalThis as Record<string, unknown>).localStorage;
		blockStorage();
	}
});

// Every other module reaches Web Storage through this helper. A bare
// `typeof localStorage` reads as an SSR guard and throws anyway; a bare
// `localStorage.setItem` outside a try takes the page down with it.
test('no module outside browser_storage.ts touches Web Storage directly', () => {
	const root = resolve(import.meta.dirname, '../..');
	const bare =
		/\btypeof\s+(local|session)Storage\b|\b(window\.|globalThis\.)?(local|session)Storage\s*\.\s*(getItem|setItem|removeItem|clear|key|length)\b/;
	const offenders: string[] = [];
	const walk = (dir: string) => {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const name = entry.name;
			const path = join(dir, name);
			if (entry.isDirectory()) {
				walk(path);
				continue;
			}
			if (!entry.isFile()) continue;
			if (!/\.(ts|svelte)$/.test(name) || /\.test\.ts$/.test(name)) continue;
			if (name === 'browser_storage.ts') continue;
			readFileSync(path, 'utf8')
				.split('\n')
				.forEach((line, i) => {
					const code = line.trim();
					if (code.startsWith('//') || code.startsWith('*')) return;
					if (bare.test(code)) offenders.push(`${relative(root, path)}:${i + 1}`);
				});
		}
	};
	walk(root);
	assert.deepEqual(offenders, []);
});
