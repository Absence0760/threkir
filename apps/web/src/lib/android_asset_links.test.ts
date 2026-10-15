// The Android App Links statement (decisions § 1923). Android verifies every
// `autoVerify` https filter in the manifest against this one file, and a
// statement that names the wrong package, or a fingerprint that is not a
// SHA-256, fails verification silently: links just open in the browser.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

type Statement = {
	relation: string[];
	target: { namespace: string; package_name: string; sha256_cert_fingerprints: string[] };
};

const statements = JSON.parse(read('static/.well-known/assetlinks.json')) as Statement[];
const gradle = read('../mobile_android/android/app/build.gradle.kts');
const manifest = read('../mobile_android/android/app/src/main/AndroidManifest.xml');

test('assetlinks.json delegates handle_all_urls to the shipped applicationId', () => {
	const applicationId = gradle.match(/applicationId\s*=\s*"([^"]+)"/)?.[1];
	assert.ok(applicationId, 'could not read applicationId from build.gradle.kts');
	const statement = statements.find(
		(s) =>
			s.target.namespace === 'android_app' &&
			s.relation.includes('delegate_permission/common.handle_all_urls'),
	);
	assert.ok(statement, 'no android_app handle_all_urls statement');
	assert.equal(statement.target.package_name, applicationId);
});

test('every fingerprint is a colon-separated uppercase SHA-256', () => {
	for (const s of statements) {
		assert.ok(s.target.sha256_cert_fingerprints.length > 0, 'a statement with no fingerprint verifies nothing');
		for (const fp of s.target.sha256_cert_fingerprints) {
			assert.match(fp, /^[0-9A-F]{2}(:[0-9A-F]{2}){31}$/, `not a SHA-256 fingerprint: ${fp}`);
		}
	}
});

test('every autoVerify host in the manifest is the host this file is served from', () => {
	const filters = [...manifest.matchAll(/<intent-filter android:autoVerify="true">([\s\S]*?)<\/intent-filter>/g)];
	assert.ok(filters.length > 0, 'no autoVerify intent-filter found; this guard is reading the wrong file');
	for (const [, body] of filters) {
		for (const [, host] of body.matchAll(/android:host="([^"]+)"/g)) {
			assert.equal(host, 'threkir.com', `autoVerify host ${host} has no assetlinks.json in this tree`);
		}
	}
});

test('the release sync keeps .well-known off the immutable year-long cache', () => {
	const workflow = read('../../.github/workflows/release-web.yml');
	assert.ok(workflow.includes('--exclude ".well-known/*"'), 'the immutable sync must exclude .well-known');
	assert.ok(workflow.includes('--include ".well-known/*"'), 'a short-cache sync must include .well-known');
});
