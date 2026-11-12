import { AI_DISCLOSURE_CURRENT_VERSION } from '../../src/lib/core/ai_disclosure';

import { expect, test } from '../fixtures/test';

import { acceptCookieConsent } from '../fixtures/helpers';
import { readRow } from '../fixtures/db-read';
import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The coach assistant on (issue #1215 Phase 4): this lane's dev server sets
 * PUBLIC_COACH_ASSIST_ENABLED. The drafting endpoint is mocked in the
 * browser, since the gates it runs are unit-tested in
 * src/lib/coach/assist/assist.test.ts and nothing here may reach Anthropic.
 *
 *   1. The athlete allows the assistant on the coaching link, and withdraws.
 *   2. The coach's panel says when the athlete has not allowed it.
 *   3. A draft the coach uses is edited in the composer, and the message it
 *      becomes is stored as ai_assisted and marked on both sides.
 */
test.describe.configure({ mode: 'serial', timeout: 90_000 });

test.describe('the coach assistant', () => {
	const admin = getAdminClient();
	let athlete: SagaUser;
	let coach: SagaUser;
	let linkId: string;
	const stamp = Date.now();

	test.beforeAll(async ({}, testInfo) => {
		[athlete, coach] = await createSagaUsers(2, {
			displayNames: ['Assist Athlete Saga', 'Assist Coach Saga'],
			baseURL: testInfo.project.use.baseURL,
		});
		linkId = crypto.randomUUID();
		const { error } = await admin.from('coach_athletes').insert({
			id: linkId,
			coach_id: coach.id,
			athlete_id: athlete.id,
			status: 'active',
			invite_token: `e2e-assist-${stamp}`,
			accepted_at: new Date().toISOString(),
		});
		if (error) throw error;
		const client = await getUserClient({ email: coach.email, password: coach.password });
		const { error: consentErr } = await client.rpc('record_ai_disclosure_consent', {
			p_version: AI_DISCLOSURE_CURRENT_VERSION,
		});
		if (consentErr) throw consentErr;
	});

	test.afterAll(async () => {
		if (athlete && coach) {
			await admin.from('coach_athletes').delete().eq('coach_id', coach.id);
			await deleteSagaUsers([athlete, coach]);
		}
	});

	const consent = async () =>
		(await admin.from('coach_athletes').select('ai_assist_consent_version').eq('id', linkId).single()).data
			?.ai_assist_consent_version ?? null;

	test('the athlete allows the assistant on the link, and withdraws', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: athlete.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		await page.goto('/coaching');
		const block = page.getByTestId('coach-assist-consent');
		await expect(block).toBeVisible({ timeout: 15_000 });
		await expect(block).toContainText('Let Assist Coach Saga use AI assistance');
		const toggle = block.getByTestId('coach-assist-consent-toggle');
		await expect(toggle).not.toBeChecked();
		await block.getByText('What this shares').click();
		await expect(block).toContainText('Anthropic');

		await toggle.check();
		await expect.poll(consent).toBe(1);
		await toggle.uncheck();
		await expect.poll(consent).toBeNull();
		await toggle.check();
		await expect.poll(consent).toBe(1);
		await ctx.close();
	});

	test('the coach drafts, edits and sends; the message is marked AI-assisted', async ({ browser, mockRoute }) => {
		const ctx = await browser.newContext({ storageState: coach.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		let answer: { status: number; body: unknown } = {
			status: 403,
			body: { error: 'athlete has not allowed the assistant', code: 'athlete_consent_required' },
		};
		const posted: unknown[] = [];
		await mockRoute(page, '**/api/coach/assist', async (route) => {
			posted.push(route.request().postDataJSON());
			await route.fulfill({ status: answer.status, contentType: 'application/json', body: JSON.stringify(answer.body) });
		});

		const { error: seedErr } = await admin.from('direct_messages').insert({
			sender_id: athlete.id,
			recipient_id: coach.id,
			body: `Calf is a bit sore ${stamp}`,
		});
		expect(seedErr).toBeNull();

		await page.goto(`/messages/${athlete.id}`);
		await page.getByTestId('coach-assist-open').click({ timeout: 15_000 });
		await page.getByTestId('coach-assist-request').fill('keep it short');
		await page.getByTestId('coach-assist-run').click();
		await expect(page.getByTestId('coach-assist-error')).toHaveText(
			'Assist Athlete Saga has not allowed AI assistance on your coaching link.',
		);

		answer = { status: 200, body: { draft: `Easy week ahead ${stamp}.` } };
		await page.getByTestId('coach-assist-run').click();
		await expect(page.getByTestId('coach-assist-draft')).toContainText(`Easy week ahead ${stamp}.`);
		expect(posted.at(-1)).toMatchObject({ athlete_id: athlete.id, mode: 'reply', request: 'keep it short' });
		await page.getByTestId('coach-assist-use').click();

		const composer = page.locator('.composer textarea');
		await expect(composer).toHaveValue(`Easy week ahead ${stamp}.`);
		await expect(page.getByTestId('dm-assisted-note')).toBeVisible();
		await composer.fill(`Easy week ahead ${stamp}. Rest Sunday.`);
		await page.locator('.composer button.btn-primary').click();

		await expect(page.getByTestId('dm-ai-assisted')).toHaveCount(1, { timeout: 15_000 });
		const data = await readRow(
			"the coach's sent message",
			admin
				.from('direct_messages')
				.select('kind, body')
				.eq('sender_id', coach.id)
				.eq('recipient_id', athlete.id)
				.single(),
		);
		expect(data).toEqual({ kind: 'ai_assisted', body: `Easy week ahead ${stamp}. Rest Sunday.` });
		await expect(page.getByTestId('dm-assisted-note')).toHaveCount(0);
		await ctx.close();

		const actx = await browser.newContext({ storageState: athlete.storageStatePath });
		await acceptCookieConsent(actx);
		const apage = await actx.newPage();
		await apage.goto(`/messages/${coach.id}`);
		await expect(apage.getByTestId('dm-ai-assisted')).toContainText('AI-assisted', { timeout: 15_000 });
		await expect(apage.getByTestId('coach-assist-panel')).toHaveCount(0);
		await actx.close();
	});
});
