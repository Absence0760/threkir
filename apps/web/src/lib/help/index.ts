// Every in-app help guide, loaded at build time. One guide per file under
// `./guides/` (docs/features/help.md § Adding a guide); the pure index lives
// in `catalogue.ts` so the unit suite can build it without Vite's glob.

import { createHelpIndex } from './catalogue';
import type { Guide } from './types';

const modules = import.meta.glob<{ guide: Guide }>(['./guides/*.ts', '!./guides/*.test.ts'], { eager: true });

const index = createHelpIndex(Object.values(modules).map((mod) => mod.guide));

export const allGuides = index.allGuides;
export const guideFor = index.guideFor;
export const guidesByCategory = index.guidesByCategory;
export const guidesForRoute = index.guidesForRoute;
export const searchGuides = index.searchGuides;

export { AUDIENCES, GUIDE_CATEGORIES, GUIDE_KINDS, PLATFORMS, REQUIREMENTS } from './catalogue';
export type { CategoryGroup } from './catalogue';
export type * from './types';
