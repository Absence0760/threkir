/// The one-off donation link: a Stripe Payment Link on the Threkir Stripe
/// account, the same account RevenueCat Web Billing charges Pro through, so
/// donations and web Pro share one processor (decisions § 2217).
///
/// `$app/env`-free so the release guard (`scripts/check_production_env.mjs`)
/// and the page (`donate.ts`) answer through the same test: a value the guard
/// lets ship is exactly a value the page will link to.

/// Stripe serves Payment Links from `buy.stripe.com`, and from
/// `donate.stripe.com` when the link is set up as a donation.
export const DONATE_HOSTS = ['donate.stripe.com', 'buy.stripe.com'] as const;

/// Why `url` cannot be the donation link, or null if it can be. Empty is a
/// problem too: callers that allow an unset link check for empty first.
export function donateUrlProblem(url: string): string | null {
	const trimmed = url.trim();
	if (!trimmed) return 'Empty.';
	let parsed: URL;
	try {
		parsed = new URL(trimmed);
	} catch {
		return 'Not a URL. Expected a Stripe Payment Link, https://donate.stripe.com/<id> or https://buy.stripe.com/<id>.';
	}
	if (parsed.protocol !== 'https:') {
		return `Scheme is \`${parsed.protocol}\`, not https.`;
	}
	if (!(DONATE_HOSTS as readonly string[]).includes(parsed.hostname)) {
		return `Host is \`${parsed.hostname}\`, not ${DONATE_HOSTS.join(' or ')}. Donors would be sent to a page that is not a Stripe Payment Link.`;
	}
	if (parsed.pathname.replace(/\//g, '') === '') {
		return 'No link id in the path. Copy the whole Payment Link from the Stripe dashboard.';
	}
	return null;
}
