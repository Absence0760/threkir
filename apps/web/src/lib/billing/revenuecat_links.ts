/// Pure URL-building helpers for the RevenueCat hosted-checkout flow,
/// split out of `revenuecat.ts` so they carry no `$env/dynamic/public`
/// import and stay node:test-runnable (the env-reading shell can't be
/// imported under `npx tsx --test`). Same split as
/// `live_hub.ts` ↔ `live_hub_helpers.ts`.

export type ProPlan = 'monthly' | 'annual';

/// RevenueCat package identifiers of the `default` offering's two Pro
/// plans (products `pro_monthly` and `pro_annual`, both granting `pro`).
export const PRO_PACKAGE_IDS: Record<ProPlan, string> = {
	monthly: '$rc_monthly',
	annual: '$rc_annual',
};

/// The one host RevenueCat serves Web Purchase Links from.
export const CHECKOUT_HOST = 'pay.rev.cat';

const PLACEHOLDER_TOKEN_RE = /^(?:placeholder|todo|tbd|changeme|change-me|example|xxx+|your[-_]?token|token)$/i;

/// Why `base` cannot be a Web Purchase Link, or null if it can be. Empty is a
/// problem too: callers that allow an unset link check for empty first. The
/// release guard (`scripts/check_production_env.mjs`) and the storefront
/// (`webCheckoutAvailable` in `revenuecat.ts`) both answer through this, so a
/// value the guard lets ship is exactly a value the page will redirect to.
export function checkoutBaseProblem(base: string): string | null {
	const trimmed = base.trim();
	if (!trimmed) return 'Empty.';
	let parsed: URL;
	try {
		parsed = new URL(trimmed);
	} catch {
		return 'Not a URL. Expected the Web Purchase Link from the RevenueCat dashboard, https://pay.rev.cat/<token>.';
	}
	if (parsed.protocol !== 'https:') {
		return `Scheme is \`${parsed.protocol}\`, not https.`;
	}
	if (parsed.hostname !== CHECKOUT_HOST) {
		return `Host is \`${parsed.hostname}\`, not ${CHECKOUT_HOST}. Buyers would be sent to a page that is not RevenueCat's hosted checkout.`;
	}
	const token = parsed.pathname.replace(/^\/+|\/+$/g, '');
	if (!token) {
		return 'Has no link token after the host. RevenueCat 404s on the bare host.';
	}
	if (PLACEHOLDER_TOKEN_RE.test(token)) {
		return `Token \`${token}\` is a placeholder, not a link token from the RevenueCat dashboard.`;
	}
	return null;
}

/// What the Pro card on `/settings/upgrade` offers someone who does not have
/// Pro yet:
///   - `checkout`: a perk is live and this build has a working Web Purchase
///     Link, so the plan picker and the buy button render.
///   - `app_only`: a perk is live but there is no web checkout, so Pro is sold
///     through the iPhone app's In-App Purchase only (decisions § 1826). The
///     card says so instead of rendering a button that cannot take payment.
///   - `coming_soon`: no perk is live, so there is nothing to sell anywhere.
export type ProStorefront = 'checkout' | 'app_only' | 'coming_soon';

export function proStorefront(proSellable: boolean, webCheckout: boolean): ProStorefront {
	if (!proSellable) return 'coming_soon';
	return webCheckout ? 'checkout' : 'app_only';
}

/// Build the Pro hosted-checkout URL from a Web Paywall Link base. The
/// Supabase user id is appended as the App User ID path segment
/// (URL-encoded; RevenueCat 404s without it) so the purchase keys to the
/// same identity the webhook sees. `redirect_url`, when supplied, brings
/// the buyer back to the upgrade page after purchase. `packageId`, when
/// supplied, is RevenueCat's documented `package_id` parameter: it
/// preselects that package of the offering and skips the hosted package
/// picker, so the plan chosen on the upgrade page is the one checked out.
/// Returns `null` when the base is not a usable Web Purchase Link
/// (`checkoutBaseProblem`) so the caller can fail closed.
export function buildCheckoutUrl(
	checkoutBase: string,
	userId: string,
	returnUrl?: string,
	packageId?: string,
): string | null {
	if (checkoutBaseProblem(checkoutBase) !== null) return null;
	const base = checkoutBase.trim().replace(/\/+$/, '');
	const url = `${base}/${encodeURIComponent(userId)}`;
	const query: string[] = [];
	if (packageId) query.push(`package_id=${encodeURIComponent(packageId)}`);
	if (returnUrl) query.push(`redirect_url=${encodeURIComponent(returnUrl)}`);
	return query.length ? `${url}?${query.join('&')}` : url;
}

/// Whole percent saved by paying `annualPrice` once instead of
/// `monthlyPrice` twelve times, rounded DOWN so the copy never overstates
/// the saving. Null when there is no saving of at least 1% to state. Same
/// rule as mobile's `annualSavingPercent` in `revenuecat.dart`, which reads
/// the store prices instead of the list prices.
export function annualSavingPercent(monthlyPrice: number, annualPrice: number): number | null {
	if (!(monthlyPrice > 0) || !(annualPrice > 0)) return null;
	const yearOfMonths = monthlyPrice * 12;
	if (annualPrice >= yearOfMonths) return null;
	// The epsilon keeps binary rounding from flooring an exact 25 to 24.
	const percent = Math.floor(((yearOfMonths - annualPrice) / yearOfMonths) * 100 + 1e-9);
	return percent >= 1 ? percent : null;
}
