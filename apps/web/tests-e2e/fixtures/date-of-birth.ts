/**
 * Drives `DateOfBirthInput` — three selects (month / day / year) inside a
 * fieldset carrying `data-testid`, which replaced `<input type="date">` so a
 * runner no longer pages back through decades to reach a birth year.
 */

import type { Locator, Page } from '@playwright/test';

export function dateOfBirth(page: Page, testid = 'date-of-birth'): {
	group: Locator;
	month: Locator;
	day: Locator;
	year: Locator;
} {
	return {
		group: page.getByTestId(testid),
		month: page.getByTestId(`${testid}-month`),
		day: page.getByTestId(`${testid}-day`),
		year: page.getByTestId(`${testid}-year`),
	};
}

/// Pick `iso` (`YYYY-MM-DD`). Year and month go first so the day list has
/// its real length before the day is chosen.
export async function fillDateOfBirth(page: Page, iso: string, testid = 'date-of-birth'): Promise<void> {
	const [y, mo, d] = iso.split('-').map(Number);
	const f = dateOfBirth(page, testid);
	await f.year.selectOption(String(y));
	await f.month.selectOption(String(mo));
	await f.day.selectOption(String(d));
}
