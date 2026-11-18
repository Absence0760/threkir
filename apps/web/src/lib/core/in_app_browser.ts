/// In-app browser detection for /login. Google refuses OAuth inside embedded
/// webviews (`403 disallowed_useragent`, Google's "Use secure browsers"
/// policy), and that is where Facebook, Instagram, Threads, LinkedIn and
/// TikTok open a tapped link. So /login recognises those browsers from the
/// user agent and offers Apple, email or the system browser instead of a
/// Google button that can only fail. Web only: the phone apps sign in
/// natively, so there is no Dart twin.
///
/// The tokens are the ones each app appends to the system webview's UA:
///   facebook   FBAN/ FBAV/ (iOS), FB_IAB/ (Android)
///   messenger  FBAN/MessengerForiOS, FB_IAB/Orca-Android
///   instagram  "Instagram 309.0.0.0 ..."
///   threads    "Barcelona 312.0.0.0 ..." (the app's internal name)
///   linkedin   LinkedInApp
///   tiktok     musical_ly_, BytedanceWebview, trill_
///   x          "Twitter for iPhone" / TwitterAndroid in its legacy webview
/// plus Android's generic WebView marker `; wv)` for any other app. An iOS
/// WKWebView with no app token cannot be told from Safari by its UA, so it
/// is not detected (Google's block still applies there; nothing to do).
/// SFSafariViewController and Chrome Custom Tabs, which X and Bluesky
/// mostly use, carry the plain browser UA and are not blocked.

import type { SignupSource } from './signup_source';

export type InAppBrowser =
	| 'facebook'
	| 'messenger'
	| 'instagram'
	| 'threads'
	| 'linkedin'
	| 'tiktok'
	| 'x'
	| 'other';

const RULES: [InAppBrowser, RegExp][] = [
	['messenger', /FBAN\/Messenger|FB_IAB\/Orca-Android|\bMessengerLite/],
	['facebook', /FBAN\/|FBAV\/|FB_IAB\/|\bFBIOS\b|\bFB4A\b/],
	// Before instagram: Threads' webview is Instagram's, so a Threads UA may
	// carry both names.
	['threads', /\bBarcelona [0-9]/],
	['instagram', /\bInstagram [0-9]/],
	['linkedin', /\bLinkedInApp\b/],
	['tiktok', /musical_ly|BytedanceWebview|\btrill_[0-9]/],
	['x', /\bTwitter(?:Android| for )/],
	['other', /Android.*; wv\)/],
];

/// The in-app browser `ua` belongs to, or null for an ordinary browser.
export function detectInAppBrowser(ua: string | null | undefined): InAppBrowser | null {
	if (!ua) return null;
	for (const [app, re] of RULES) {
		if (re.test(ua)) return app;
	}
	return null;
}

/// The display name of the app, for "inside the Facebook app's browser".
/// Null for `other`, which takes the unnamed wording.
export function inAppBrowserName(app: InAppBrowser): string | null {
	switch (app) {
		case 'facebook':
			return 'Facebook';
		case 'messenger':
			return 'Messenger';
		case 'instagram':
			return 'Instagram';
		case 'threads':
			return 'Threads';
		case 'linkedin':
			return 'LinkedIn';
		case 'tiktok':
			return 'TikTok';
		case 'x':
			return 'X';
		case 'other':
			return null;
	}
}

/// The link to copy out of the in-app browser. The system browser it is
/// pasted into starts a new tab with no referrer, so the tab's first touch
/// (signup_source, decisions § 2350) would read `direct`; carrying it as UTM
/// parameters keeps the sign-up counted against the app it came from. A link
/// that already has a `utm_source` is left alone. With no usable first touch
/// the detected app itself is the source, since the visitor is reading this
/// inside it.
export function externalBrowserLink(
	href: string,
	touch: SignupSource | null,
	app: InAppBrowser,
): string {
	let url: URL;
	try {
		url = new URL(href);
	} catch {
		return href;
	}
	if (url.searchParams.has('utm_source')) return url.toString();
	const known = touch && touch.source !== 'direct' && touch.source !== 'other' ? touch : null;
	if (known) {
		url.searchParams.set('utm_source', known.source);
		if (known.medium) url.searchParams.set('utm_medium', known.medium);
		if (known.campaign) url.searchParams.set('utm_campaign', known.campaign);
	} else if (app !== 'other') {
		url.searchParams.set('utm_source', app);
		url.searchParams.set('utm_medium', 'in-app-browser');
	}
	return url.toString();
}
