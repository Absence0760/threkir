import type { en } from './locales/en.ts';

// The catalogue shape: every locale module is `... satisfies Messages`,
// so a missing or extra key is a compile error. Values are plain strings
// (en is declared without `as const`, so the inferred value type is
// `string`, not a literal) — translations are free to differ.
//
// A type-only import on purpose: the runtime never loads a whole catalogue
// (decisions § 1802), so nothing here may pull one into a bundle.
export type Messages = typeof en;
export type MessageKey = keyof Messages;
