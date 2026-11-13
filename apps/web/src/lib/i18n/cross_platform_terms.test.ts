import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPPORTED_LOCALES, type Locale } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';

// A control a person reads on one platform and is told about on the other must
// carry the same words on both, in every locale: the phone's switch read
// "Mostrar-me a corredores por perto" while web's help text told the same
// person to turn on "Mostrar-me em Corredores por perto". Each pair is a web
// key and the ARB key that names the same thing.

const HERE = dirname(fileURLToPath(import.meta.url));
const L10N = resolve(HERE, '../../../../mobile_android/lib/l10n');

const PAIRS: [web: string, arb: string][] = [
	['socialNearby.heading', 'peopleNearbyHeader'],
	['prefs.discoverableNearby', 'prefsDiscoverableNearby'],
	// Health-data consent: the statement a runner agrees to and the withdrawal
	// they confirm read the same on both (decisions § 2514).
	['onboarding.healthConsent', 'setupHealthConsent'],
	['prefs.withdrawConsentMessage', 'bodyMetricsWithdrawBody'],
	['nutrition.targets.metricsHint', 'nutritionTargetsMetricsHint'],
	['nutrition.targets.emptyBody', 'nutritionTargetsEmptyBody'],
];

const ARB_FILE: Record<Locale, string> = {
	en: 'app_en.arb',
	de: 'app_de.arb',
	fr: 'app_fr.arb',
	es: 'app_es.arb',
	'pt-PT': 'app_pt.arb',
	'pt-BR': 'app_pt_BR.arb',
	ja: 'app_ja.arb',
};

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: a control named on both platforms reads the same on both`, async () => {
		const web = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const arb = JSON.parse(readFileSync(resolve(L10N, ARB_FILE[loc]), 'utf8')) as Record<string, string>;
		for (const [w, a] of PAIRS) {
			assert.ok(web[w] && arb[a], `${loc}: ${w} or ${a} is missing`);
			assert.equal(arb[a], web[w], `${loc}: mobile ${a} differs from web ${w}`);
		}
	});
}
