import type { Locator, Page } from '@playwright/test';

/**
 * Share on a private run or route no longer makes it public on its own: with
 * audience sharing on (the seed opens the server flag) it asks who should see
 * it. Picking Public is what opens the make-public confirm the old one-tap
 * flow showed, so a spec that is about that confirm goes through here.
 */
export async function shareChoosingPublic(page: Page, shareButton: Locator): Promise<void> {
	await shareButton.click();
	await page.getByTestId('audience-level-public').click();
}
