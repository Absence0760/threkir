import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DM_LINK_REL, dmLinkDomain, dmTextSegments } from './dm_link.ts';

test('the rel names every value the anchor needs', () => {
	assert.deepEqual(DM_LINK_REL.split(' ').sort(), ['nofollow', 'noopener', 'noreferrer', 'ugc']);
});

test('a domain is the lower-cased host without www or port', () => {
	assert.equal(dmLinkDomain('https://www.Example.com/a?b#c'), 'example.com');
	assert.equal(dmLinkDomain('http://sub.example.co.uk:8080/x'), 'sub.example.co.uk');
	assert.equal(dmLinkDomain('HTTPS://EXAMPLE.ORG'), 'example.org');
});

test('anything that could pass for another domain stays text', () => {
	assert.equal(dmLinkDomain('https://google.com@evil.example/'), null);
	assert.equal(dmLinkDomain('https://user:pw@example.com/'), null);
	assert.equal(dmLinkDomain('https://xn--80ak6aa92e.com/'), 'xn--80ak6aa92e.com');
	assert.equal(dmLinkDomain('https://аррӏе.com/'), null);
	assert.equal(dmLinkDomain('javascript:alert(1)'), null);
	assert.equal(dmLinkDomain('ftp://example.com'), null);
	assert.equal(dmLinkDomain('https://localhost/'), null);
	assert.equal(dmLinkDomain('https://example..com/'), null);
	assert.equal(dmLinkDomain('https://.example.com/'), null);
});

test('text is cut into runs and links in order', () => {
	assert.deepEqual(dmTextSegments('see https://example.com/route, then reply'), [
		{ kind: 'text', text: 'see ' },
		{ kind: 'link', text: 'https://example.com/route', href: 'https://example.com/route', domain: 'example.com' },
		{ kind: 'text', text: ', then reply' },
	]);
	assert.deepEqual(dmTextSegments('no links here'), [{ kind: 'text', text: 'no links here' }]);
	assert.deepEqual(dmTextSegments(''), []);
});

test('trailing punctuation and an unbalanced paren are not part of the link', () => {
	const segs = dmTextSegments('(at https://example.com/a_(b)) ok.');
	assert.deepEqual(segs[1], {
		kind: 'link',
		text: 'https://example.com/a_(b)',
		href: 'https://example.com/a_(b)',
		domain: 'example.com',
	});
	assert.equal(dmTextSegments('Go: https://example.com!')[1].text, 'https://example.com');
});

test('a refused URL stays inside the plain text', () => {
	assert.deepEqual(dmTextSegments('x https://a@b.com y https://ok.example z'), [
		{ kind: 'text', text: 'x https://a@b.com y ' },
		{ kind: 'link', text: 'https://ok.example', href: 'https://ok.example', domain: 'ok.example' },
		{ kind: 'text', text: ' z' },
	]);
});

test('no markup survives as markup: segments are plain strings', () => {
	const segs = dmTextSegments('<img src=x onerror=alert(1)> https://example.com/<b>');
	assert.equal(segs[0].kind, 'text');
	assert.equal(segs[1].kind, 'link');
	assert.equal((segs[1] as { href: string }).href, 'https://example.com/');
});
