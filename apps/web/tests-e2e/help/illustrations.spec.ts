import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { expect, test } from '../fixtures/test';

import type { Guide } from '../../src/lib/help/types';
import { setStorageOnLoad } from '../fixtures/helpers';

/**
 * Every help-guide illustration, as a signed-out visitor sees it
 * (docs/features/help.md § Illustrations). help-centre.spec.ts pins one
 * drawing, privacy-zones, which paints with five of the seven theme tokens;
 * `positive` and `caution` are drawn only by other guides, so a broken
 * mapping for either reached no browser test. This walks every guide that
 * carries an illustration and checks each painted shape against the theme
 * token its placeholder stands for.
 *
 * Signed out, because the public live-event page links spectators straight
 * into the guides (decisions § 1866) and no account preference should be
 * what makes the drawing work.
 */

const HELP_DIR = resolve(import.meta.dirname, '..', '..', 'src', 'lib', 'help');

/** The contract HelpIllustration.svelte implements: illustration token → app theme token. */
const TOKEN_TO_THEME: Record<string, string> = {
	accent: '--color-primary',
	'accent-soft': '--color-primary-light',
	muted: '--color-text-tertiary',
	surface: '--color-surface',
	tint: '--color-bg-tertiary',
	positive: '--color-success',
	caution: '--color-warning'
};

const PLACEHOLDER = /^rgb\(255, 0, 16[1-7]\)$/;

async function illustratedGuides(): Promise<{ id: string; illustration: string; alt: string }[]> {
	const out: { id: string; illustration: string; alt: string }[] = [];
	for (const file of readdirSync(resolve(HELP_DIR, 'guides')).filter((f) => f.endsWith('.ts')).sort()) {
		const { guide } = (await import(resolve(HELP_DIR, 'guides', file))) as { guide: Guide };
		for (const section of guide.sections) {
			for (const block of section.blocks) {
				if (block.type === 'illustration') out.push({ id: guide.id, illustration: block.id, alt: block.alt });
			}
		}
	}
	return out;
}

test.describe('/help — every guide illustration, signed out', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('each illustrated guide draws its figure, announced by its alt, painted with the theme tokens', async ({
		page
	}) => {
		const guides = await illustratedGuides();
		// The seven committed drawings; a guide that loses its block shrinks this.
		expect(guides.length).toBeGreaterThanOrEqual(7);
		const seenTokens = new Set<string>();

		for (const g of guides) {
			await page.goto(`/help/${g.id}`);
			const figure = page.getByTestId('help-illustration');
			await expect(figure, g.id).toHaveAttribute('data-illustration', g.illustration, { timeout: 10_000 });
			await expect(figure.getByRole('img', { name: g.alt, exact: true }), g.id).toBeVisible();

			const paints = await figure.evaluate((fig, map) => {
				const resolveVar = (name: string) => {
					const probe = document.createElement('span');
					probe.style.color = `var(${name})`;
					fig.appendChild(probe);
					const c = getComputedStyle(probe).color;
					probe.remove();
					return c;
				};
				const rows: { token: string; prop: string; got: string; want: string }[] = [];
				for (const el of fig.querySelectorAll('svg *')) {
					for (const prop of ['fill', 'stroke'] as const) {
						const m = /^var\(--illus-([a-z-]+)\)$/.exec(el.getAttribute(prop) ?? '');
						if (!m) continue;
						const style = getComputedStyle(el);
						rows.push({
							token: m[1],
							prop,
							got: prop === 'fill' ? style.fill : style.stroke,
							want: map[m[1]] ? resolveVar(map[m[1]]) : `no theme token for ${m[1]}`
						});
					}
				}
				return rows;
			}, TOKEN_TO_THEME);

			expect(paints.length, `${g.id} paints with no theme token`).toBeGreaterThan(0);
			for (const p of paints) {
				seenTokens.add(p.token);
				expect(p.got, `${g.id} ${p.prop} for ${p.token}`).not.toMatch(PLACEHOLDER);
				expect(p.got, `${g.id} ${p.prop} for ${p.token}`).toBe(p.want);
			}
		}
		// The point of walking them all: between them, every token is drawn.
		expect([...seenTokens].sort()).toEqual(Object.keys(TOKEN_TO_THEME).sort());
	});

	test('ja: the spectator guide’s figure is announced in Japanese and still painted', async ({
		context,
		page
	}) => {
		const ja = JSON.parse(
			readFileSync(resolve(import.meta.dirname, '..', '..', 'static', 'help-guides', 'guides.ja.json'), 'utf8')
		) as { id: string; sections: { blocks: { type: string; alt?: string }[] }[] }[];
		const jaAlt = ja
			.find((g) => g.id === 'follow-a-race-live')!
			.sections.flatMap((s) => s.blocks)
			.find((b) => b.type === 'illustration')!.alt!;
		expect(jaAlt).toMatch(/[぀-ヿ一-鿿]/);

		await setStorageOnLoad(context, { local: { locale: 'ja' } });
		await page.goto('/help/follow-a-race-live');
		const figure = page.getByTestId('help-illustration');
		await expect(figure).toHaveAttribute('data-illustration', 'follow-a-race-live', { timeout: 10_000 });
		await expect(figure.getByRole('img', { name: jaAlt, exact: true })).toBeVisible({ timeout: 15_000 });
		await expect(figure.getByRole('img', { name: /A course on a map/ })).toHaveCount(0);

		const fills = await figure.evaluate((fig) =>
			[...fig.querySelectorAll('svg *')].map((el) => getComputedStyle(el).fill)
		);
		expect(fills.length).toBeGreaterThan(0);
		for (const f of fills) expect(f).not.toMatch(PLACEHOLDER);
	});
});
