// The iOS universal-links file (decisions § 1924), the twin of assetlinks.json.
// iOS fetches it through Apple's CDN when the app is installed, and a file that
// names the wrong app, claims a path the app does not route, or is served as
// anything but application/json fails silently: links just open in Safari.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

type Component = { '/': string; comment?: string };
type Aasa = { applinks: { details: { appIDs: string[]; components: Component[] }[] } };

const aasa = JSON.parse(read('static/.well-known/apple-app-site-association')) as Aasa;
const pbxproj = read('../mobile_ios/ios/Runner.xcodeproj/project.pbxproj');
const entitlements = read('../mobile_ios/ios/Runner/Runner.entitlements');
const manifest = read('../mobile_android/android/app/src/main/AndroidManifest.xml');
const provisioning = read('../../docs/ops/apple_provisioning.md');

// The bundle id of the configurations that sign with Runner.entitlements: the
// phone app, not the watch or an extension.
function phoneBundleIds(): Set<string> {
	const ids = new Set<string>();
	for (const [, body] of pbxproj.matchAll(/buildSettings = \{([\s\S]*?)\n\t\t\t\};/g)) {
		if (!/CODE_SIGN_ENTITLEMENTS = Runner\/Runner\.entitlements;/.test(body)) continue;
		const id = body.match(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/)?.[1];
		if (id) ids.add(id.replace(/^"(.*)"$/, '$1'));
	}
	return ids;
}

// Android's autoVerify https paths, translated into AASA's path syntax:
// a pathPrefix is a trailing `*`, and pathPattern's `.` is AASA's `?`.
function androidVerifiedPaths(): { host: string; path: string }[] {
	const out: { host: string; path: string }[] = [];
	const filters = [...manifest.matchAll(/<intent-filter android:autoVerify="true">([\s\S]*?)<\/intent-filter>/g)];
	for (const [, body] of filters) {
		for (const [tag] of body.matchAll(/<data [^>]*android:scheme="https"[^>]*\/>/g)) {
			const host = tag.match(/android:host="([^"]+)"/)?.[1] ?? '';
			const prefix = tag.match(/android:pathPrefix="([^"]+)"/)?.[1];
			const pattern = tag.match(/android:pathPattern="([^"]+)"/)?.[1];
			if (prefix) out.push({ host, path: `${prefix}*` });
			else if (pattern) out.push({ host, path: pattern.replaceAll('.', '?') });
			else assert.fail(`an autoVerify https <data> with neither pathPrefix nor pathPattern: ${tag}`);
		}
	}
	return out;
}

test('the file names the phone app under the team that signs it', () => {
	assert.equal(aasa.applinks.details.length, 1);
	const [detail] = aasa.applinks.details;
	const bundleIds = phoneBundleIds();
	assert.equal(bundleIds.size, 1, `expected one phone bundle id, got ${[...bundleIds].join(', ')}`);
	const teamId = provisioning.match(/`apple_team_id` \(`([A-Z0-9]{10})`\)/)?.[1];
	assert.ok(teamId, 'could not read the Team ID from docs/ops/apple_provisioning.md');
	assert.deepEqual(detail.appIDs, [`${teamId}.${[...bundleIds][0]}`]);
});

test('the claimed paths are exactly the ones Android verifies', () => {
	const android = androidVerifiedPaths();
	assert.ok(android.length > 0, 'no autoVerify https path found; this guard is reading the wrong file');
	for (const { host } of android) {
		assert.equal(host, 'threkir.com', `autoVerify host ${host} has no apple-app-site-association in this tree`);
	}
	const ios = aasa.applinks.details[0].components.map((c) => c['/']).sort();
	assert.deepEqual(ios, android.map((p) => p.path).sort());
});

test('the phone entitlements claim threkir.com for applinks and nothing else', () => {
	const block = entitlements.match(
		/<key>com\.apple\.developer\.associated-domains<\/key>\s*<array>([\s\S]*?)<\/array>/,
	)?.[1];
	assert.ok(block, 'Runner.entitlements has no associated-domains array');
	const domains = [...block.matchAll(/<string>([^<]+)<\/string>/g)].map((m) => m[1]);
	assert.deepEqual(domains, ['applinks:threkir.com']);
});

test('the release uploads the file as application/json on the short cache', () => {
	const workflow = read('../../.github/workflows/release-web.yml');
	assert.match(workflow, /--exclude "\.well-known\/apple-app-site-association"/);
	const cp = workflow.match(/aws s3 cp apps\/web\/build\/\.well-known\/apple-app-site-association[\s\S]*?(?=\n\s*\n|\n\s{6}- )/)?.[0];
	assert.ok(cp, 'no dedicated aws s3 cp for apple-app-site-association');
	assert.match(cp, /--content-type "application\/json"/);
	assert.match(cp, /--cache-control "public,max-age=60,must-revalidate"/);
	assert.doesNotMatch(cp, /immutable/);
});
