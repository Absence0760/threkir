import type { Browser, Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Plan wizard — the recovery block (issue #1186, decisions § 93).
 *
 * The masters recovery calibration needs a consented date of birth at 50+.
 * Without one the wizard says how to get it, and any runner can opt into the
 * same calibration with `extra_recovery`, a universal setting the wizard and
 * Settings → Training share. The generator arithmetic is unit-tested; this
 * pins the wiring: which state shows which line, that the toggle reshapes the
 * preview, and that it lands in the settings bag where the other surface
 * reads it.
 *
 * Saga users, because each case needs a profile in a specific date-of-birth
 * state and the toggle writes a setting a seeded user's other specs read.
 */

let users: SagaUser[] = [];
let noDob: SagaUser;
let masters: SagaUser;
let withheld: SagaUser;

test.beforeAll(async () => {
	users = await createSagaUsers(3, {
		displayNames: ['Saga Recovery NoDob', 'Saga Recovery Masters', 'Saga Recovery Withheld'],
	});
	[noDob, masters, withheld] = users;
	const admin = getAdminClient();
	const consented = await admin
		.from('user_profiles')
		.update({ date_of_birth: '1960-01-15', health_data_consent_at: new Date().toISOString() })
		.eq('id', masters.id);
	if (consented.error) throw new Error(consented.error.message);
	const noConsent = await admin
		.from('user_profiles')
		.update({ date_of_birth: '1960-01-15', health_data_consent_at: null })
		.eq('id', withheld.id);
	if (noConsent.error) throw new Error(noConsent.error.message);
});

test.afterAll(async () => {
	if (users.length > 0) await deleteSagaUsers(users);
});

async function openWizard(browser: Browser, baseURL: string | undefined, user: SagaUser) {
	const context = await browser.newContext({ baseURL, storageState: user.storageStatePath });
	const page = await context.newPage();
	await page.goto('/plans/new?type=training');
	await page.getByLabel('Goal race').selectOption('distance_full');
	return { context, page };
}

const weekVolumes = (page: Page) => page.locator('.week-km').allInnerTexts();

async function extraRecoverySetting(userId: string): Promise<unknown> {
	const { data } = await getAdminClient()
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();
	return (data?.prefs as Record<string, unknown> | undefined)?.extra_recovery;
}

test('a runner with no date of birth is told where to add one, and the toggle reshapes the plan and persists', async ({
	browser,
	baseURL,
}) => {
	const { context, page } = await openWizard(browser, baseURL, noDob);
	try {
		const hint = page.getByTestId('plan-dob-hint');
		await expect(hint).toBeVisible({ timeout: 10_000 });
		await expect(hint.getByRole('link', { name: 'Add your date of birth' })).toHaveAttribute(
			'href',
			'/settings/body#body-metrics',
		);

		const toggle = page.getByTestId('plan-extra-recovery');
		await expect(toggle).toBeEnabled();
		await expect(toggle).not.toBeChecked();
		await expect(page.locator('.week-km').first()).toBeVisible();
		const before = await weekVolumes(page);

		await toggle.check();
		await expect.poll(() => weekVolumes(page)).not.toEqual(before);
		await expect.poll(() => extraRecoverySetting(noDob.id)).toBe(true);

		await page.goto('/settings/training');
		await expect(page.getByTestId('extra-recovery-toggle')).toBeChecked({ timeout: 10_000 });
		await page.getByTestId('extra-recovery-toggle').uncheck();
		await expect.poll(() => extraRecoverySetting(noDob.id)).toBe(false);
	} finally {
		await context.close();
	}
});

test('a masters runner is told the calibration is already on, with no toggle and no hint', async ({
	browser,
	baseURL,
}) => {
	const { context, page } = await openWizard(browser, baseURL, masters);
	try {
		await expect(page.getByTestId('plan-recovery-masters')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('plan-extra-recovery')).toHaveCount(0);
		await expect(page.getByTestId('plan-dob-hint')).toHaveCount(0);
	} finally {
		await context.close();
	}
});

test('a date of birth held without health-data consent points at the consent, not at adding a date', async ({
	browser,
	baseURL,
}) => {
	const { context, page } = await openWizard(browser, baseURL, withheld);
	try {
		const hint = page.getByTestId('plan-dob-consent-hint');
		await expect(hint).toBeVisible({ timeout: 10_000 });
		await expect(hint.getByRole('link', { name: 'Review consent' })).toHaveAttribute(
			'href',
			'/settings/body#body-metrics',
		);
		await expect(page.getByTestId('plan-dob-hint')).toHaveCount(0);
		await expect(page.getByTestId('plan-extra-recovery')).toBeVisible();
	} finally {
		await context.close();
	}
});
