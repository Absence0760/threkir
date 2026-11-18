import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectInAppBrowser, externalBrowserLink, inAppBrowserName } from './in_app_browser.js';

const IOS_SAFARI =
	'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const IOS_WEBVIEW =
	'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
const ANDROID_CHROME =
	'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
const ANDROID_WEBVIEW =
	'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36';

test('ordinary browsers are not in-app browsers', () => {
	assert.equal(detectInAppBrowser(IOS_SAFARI), null);
	assert.equal(detectInAppBrowser(ANDROID_CHROME), null);
	assert.equal(
		detectInAppBrowser('Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0'),
		null,
	);
	assert.equal(detectInAppBrowser(''), null);
	assert.equal(detectInAppBrowser(null), null);
	assert.equal(detectInAppBrowser(undefined), null);
});

test('Facebook on iOS and Android', () => {
	assert.equal(detectInAppBrowser(`${IOS_WEBVIEW} [FBAN/FBIOS;FBAV/500.0.0.0;FBBV/1;FBDV/iPhone14,5;FBMD/iPhone;FBSN/iOS;FBSV/17.5;FBLC/en_US]`), 'facebook');
	assert.equal(detectInAppBrowser(`${ANDROID_WEBVIEW} [FB_IAB/FB4A;FBAV/480.0.0.0;]`), 'facebook');
});

test('Messenger is told apart from Facebook', () => {
	assert.equal(detectInAppBrowser(`${IOS_WEBVIEW} [FBAN/MessengerForiOS;FBAV/480.0.0;]`), 'messenger');
	assert.equal(detectInAppBrowser(`${ANDROID_WEBVIEW} [FB_IAB/Orca-Android;FBAV/480.0.0;]`), 'messenger');
});

test('Instagram and Threads', () => {
	assert.equal(detectInAppBrowser(`${IOS_WEBVIEW} Instagram 309.0.0.40.113 (iPhone14,5; iOS 17_5; en_US)`), 'instagram');
	assert.equal(detectInAppBrowser(`${IOS_WEBVIEW} Barcelona 312.0.0.0 (iPhone14,5; iOS 17_5; en_US)`), 'threads');
	assert.equal(
		detectInAppBrowser(`${ANDROID_WEBVIEW} Barcelona 312.0.0.0 Instagram 309.0.0.40.113 Android`),
		'threads',
	);
});

test('LinkedIn, TikTok and X', () => {
	assert.equal(detectInAppBrowser(`${IOS_WEBVIEW} [LinkedInApp]/9.30.1`), 'linkedin');
	assert.equal(detectInAppBrowser(`${IOS_WEBVIEW} musical_ly_32.5.0 JsSdk/2.0 NetType/WIFI`), 'tiktok');
	assert.equal(detectInAppBrowser(`${ANDROID_WEBVIEW} trill_320503 BytedanceWebview/d8a21c6`), 'tiktok');
	assert.equal(detectInAppBrowser(`${IOS_WEBVIEW} Twitter for iPhone/10.60`), 'x');
	assert.equal(detectInAppBrowser(`${ANDROID_WEBVIEW} TwitterAndroid`), 'x');
});

test('any other Android WebView is still caught, unnamed', () => {
	assert.equal(detectInAppBrowser(ANDROID_WEBVIEW), 'other');
	assert.equal(inAppBrowserName('other'), null);
	assert.equal(inAppBrowserName('facebook'), 'Facebook');
	assert.equal(inAppBrowserName('threads'), 'Threads');
});

test('a bare iOS WKWebView cannot be told from Safari and is left alone', () => {
	assert.equal(detectInAppBrowser(IOS_WEBVIEW), null);
});

const LOGIN = 'https://threkir.com/login?signup=1';

test('the copied link carries the tab first touch as UTM parameters', () => {
	assert.equal(
		externalBrowserLink(
			LOGIN,
			{ source: 'facebook', medium: 'social', campaign: 'richmond', referrer_host: 'l.facebook.com' },
			'facebook',
		),
		'https://threkir.com/login?signup=1&utm_source=facebook&utm_medium=social&utm_campaign=richmond',
	);
	assert.equal(
		externalBrowserLink(LOGIN, { source: 'instagram', medium: null, campaign: null, referrer_host: null }, 'instagram'),
		'https://threkir.com/login?signup=1&utm_source=instagram',
	);
});

test('with no usable first touch the detected app is the source', () => {
	assert.equal(
		externalBrowserLink(LOGIN, { source: 'direct', medium: null, campaign: null, referrer_host: null }, 'facebook'),
		'https://threkir.com/login?signup=1&utm_source=facebook&utm_medium=in-app-browser',
	);
	assert.equal(
		externalBrowserLink(LOGIN, null, 'threads'),
		'https://threkir.com/login?signup=1&utm_source=threads&utm_medium=in-app-browser',
	);
	assert.equal(externalBrowserLink(LOGIN, null, 'other'), LOGIN);
});

test('a link that already has a utm_source is left as it is', () => {
	const tagged = 'https://threkir.com/login?signup=1&utm_source=bio';
	assert.equal(
		externalBrowserLink(tagged, { source: 'facebook', medium: null, campaign: null, referrer_host: null }, 'facebook'),
		tagged,
	);
});

test('an unparseable href is returned unchanged', () => {
	assert.equal(externalBrowserLink('not a url', null, 'facebook'), 'not a url');
});
