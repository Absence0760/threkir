import type { EntryGenerator, PageLoad } from './$types';
import { error } from '@sveltejs/kit';
import { PUBLIC_SITE_URL } from '$app/env/public';
import { guidesByCategory } from '#lib/learn/guides.ts';
import { CATEGORIES, getCategory } from '#lib/learn/categories.ts';
import { siteOrigin } from '#lib/core/site_url.ts';

export const prerender = true;


export const entries: EntryGenerator = () => CATEGORIES.map((c) => ({ category: c.id }));

export const load: PageLoad = ({ params }) => {
	const category = getCategory(params.category);
	if (!category) throw error(404, 'Category not found');
	const siteUrl = siteOrigin(PUBLIC_SITE_URL);
	return {
		siteUrl,
		category,
		guides: guidesByCategory(category.id),
	};
};
