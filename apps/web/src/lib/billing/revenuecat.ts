/// RevenueCat hosted-checkout wrapper.
///
/// Pro checkout and subscription management both run through RevenueCat's
/// HOSTED redirect surfaces — a Web Paywall Link for purchase and the
/// no-code customer portal for management — rather than the embedded
/// `@revenuecat/purchases-js` SDK. The SDK shipped ~178 KB gzipped into
/// the `/settings/upgrade` bundle for two one-shot redirects; a hosted
/// link does the same job with zero client JS. See
/// docs/features/paywall.md § "Client → RevenueCat SDK" + decisions.md.
///
/// The CTA on `/settings/upgrade` renders only where `webCheckoutAvailable()`
/// holds. Without a usable link (local dev, previews, and production until
/// web checkout goes live) a sellable Pro is sold through the iPhone app's
/// In-App Purchase alone, and the page says so rather than rendering a buy
/// button that cannot take payment (decisions § 1826).
///
/// Production flow:
///   1. The buyer is redirected to the Web Paywall Link with their
///      Supabase user id appended, so RevenueCat keys the purchase to the
///      same identity the webhook sees (`app_user_id`).
///   2. On success RevenueCat redirects back to `/settings/upgrade`; the
///      `revenuecat-webhook` Edge Function flips `subscription_tier`
///      server-side, and the page refetches the profile on load.
///   3. Management routes to the hosted customer portal (active-sub
///      lookup by email), so no per-user SDK `getCustomerInfo()` call is
///      needed to derive a management URL.
///
/// URL construction lives in the `$env`-free `revenuecat_links.ts` so it
/// stays unit-testable; this module is the thin env-reading shell.

import { env } from '$env/dynamic/public';

import {
	buildCheckoutUrl,
	checkoutBaseProblem,
	PRO_PACKAGE_IDS,
	type ProPlan,
} from './revenuecat_links';

// Read via `$env/dynamic/public` rather than `static/public` so an
// unconfigured build returns an empty string and `webCheckoutAvailable()`
// reports false, instead of failing the SvelteKit build with a 500.
//
// The checkout base is the project's Web Paywall Link of the form
// `https://pay.rev.cat/<token>`; `<token>` is a public, per-project value
// from the RevenueCat dashboard. The portal base is the no-code customer
// portal link. Both are public by design (they're URLs a browser is
// redirected to), so the PUBLIC_ prefix is correct.
const CHECKOUT_BASE = env.PUBLIC_REVENUECAT_WEB_CHECKOUT_URL ?? '';
const PORTAL_URL = env.PUBLIC_REVENUECAT_WEB_PORTAL_URL ?? '';

/// Whether this build can take a Pro payment on the web. Fail-closed: an
/// unset link and a malformed one (not https, not pay.rev.cat, a placeholder
/// token) both answer false, by the same `checkoutBaseProblem` test the
/// release guard applies.
export function webCheckoutAvailable(): boolean {
	return checkoutBaseProblem(CHECKOUT_BASE) === null;
}

/// Build the Pro hosted-checkout URL for a specific Supabase user id,
/// preselecting the package for `plan`. Returns `null` when
/// `webCheckoutAvailable()` is false, so the caller can fail closed.
export function proCheckoutUrl(userId: string, plan: ProPlan, returnUrl?: string): string | null {
	return buildCheckoutUrl(CHECKOUT_BASE, userId, returnUrl, PRO_PACKAGE_IDS[plan]);
}

/// The hosted subscription-management URL. RevenueCat's no-code customer
/// portal authenticates the user by email at the portal itself, so no
/// per-user SDK call is needed. Returns `null` when unconfigured.
export function managementUrl(): string | null {
	return PORTAL_URL.trim() || null;
}
