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

/// Build the Pro hosted-checkout URL from a Web Paywall Link base. The
/// Supabase user id is appended as the App User ID path segment
/// (URL-encoded; RevenueCat 404s without it) so the purchase keys to the
/// same identity the webhook sees. `redirect_url`, when supplied, brings
/// the buyer back to the upgrade page after purchase. `packageId`, when
/// supplied, is RevenueCat's documented `package_id` parameter: it
/// preselects that package of the offering and skips the hosted package
/// picker, so the plan chosen on the upgrade page is the one checked out.
/// Returns `null` when the base is empty so the caller can fail closed.
export function buildCheckoutUrl(
	checkoutBase: string,
	userId: string,
	returnUrl?: string,
	packageId?: string,
): string | null {
	const base = checkoutBase.trim().replace(/\/+$/, '');
	if (!base) return null;
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
