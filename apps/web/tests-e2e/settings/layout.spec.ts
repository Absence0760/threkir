import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings — settings-nav structure. The sub-pages are grouped under four
 * section labels in the sidebar nav (Profile / Preferences / Apps & data /
 * Account & legal). Pins that grouping so future routes land in the right
 * bucket and don't get accidentally orphaned outside any section. The
 * Preferences section is the topical split of what used to be one
 * /settings/preferences page (issue #905).
 */
test.describe('/settings — side-nav structure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('side-nav groups the pages under four section headers', async ({
		page
	}) => {
		await page.goto('/settings/account');

		const nav = page.locator('.settings-nav');
		await expect(nav).toBeVisible({ timeout: 10_000 });

		const sectionLabels = nav.locator('.nav-section-label');
		await expect(sectionLabels).toHaveCount(4);
		await expect(sectionLabels.nth(0)).toHaveText(/Profile/);
		await expect(sectionLabels.nth(1)).toHaveText(/Preferences/);
		await expect(sectionLabels.nth(2)).toHaveText(/Apps & data/);
		await expect(sectionLabels.nth(3)).toHaveText(/Account & legal/);

		// Every existing tab is still present + each routes correctly.
		const expected = [
			{ href: '/settings/account', label: 'Account' },
			{ href: '/settings/body', label: 'Body metrics' },
			{ href: '/settings/display', label: 'Units & display' },
			{ href: '/settings/recording', label: 'Recording & voice' },
			{ href: '/settings/training', label: 'Training' },
			{ href: '/settings/privacy', label: 'Privacy & sharing' },
			{ href: '/settings/notifications', label: 'Notifications' },
			{ href: '/settings/integrations', label: 'Integrations' },
			// "Devices" alone read as hardware; the page is signed-in sessions
			// plus their per-device overrides, and the heart-rate strap /
			// treadmill pairing lives under Integrations (#666 I10).
			{ href: '/settings/devices', label: 'Signed-in devices' },
			{ href: '/settings/gear', label: 'Gear' },
			{ href: '/settings/upgrade', label: 'Pro & support' },
			{ href: '/settings/licenses', label: 'About' },
		];
		for (const { href, label } of expected) {
			const link = nav.locator(`a[href="${href}"]`);
			await expect(link).toBeVisible();
			await expect(link).toContainText(label);
		}
		// The landing page for old links is not a tab: a setting reached only
		// through it would be one no runner finds from the nav.
		await expect(nav.locator('a[href="/settings/preferences"]')).toHaveCount(0);

		// Clicking a tab routes to it + applies the active class.
		await nav.locator('a[href="/settings/gear"]').click();
		await expect(page).toHaveURL(/\/settings\/gear$/);
		await expect(nav.locator('a[href="/settings/gear"]')).toHaveClass(
			/active/
		);
	});
});
