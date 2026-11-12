import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	CONSENT_PATH,
	ONBOARDING_PATH,
	holdAppShell,
	pendingGate,
	postAuthDestination,
} from './post_auth_route.js';

const fresh = { consent_recorded: true, onboarded_at: null };
const onboarded = { consent_recorded: true, onboarded_at: '2026-10-01T00:00:00Z' };
const unconsented = { consent_recorded: false, onboarded_at: null };

test('pendingGate puts consent ahead of onboarding', () => {
	assert.equal(pendingGate(unconsented), CONSENT_PATH);
	assert.equal(pendingGate({ consent_recorded: false, onboarded_at: '2026-10-01' }), CONSENT_PATH);
	assert.equal(pendingGate(fresh), ONBOARDING_PATH);
	assert.equal(pendingGate(onboarded), null);
});

test('a fresh account signing in to the default landing goes straight to onboarding', () => {
	assert.equal(postAuthDestination(fresh, '/dashboard'), ONBOARDING_PATH);
	assert.equal(postAuthDestination(fresh, '/dashboard?tab=week'), ONBOARDING_PATH);
	assert.equal(postAuthDestination(unconsented, '/dashboard'), CONSENT_PATH);
});

test('an onboarded account keeps its target', () => {
	assert.equal(postAuthDestination(onboarded, '/dashboard'), '/dashboard');
	assert.equal(postAuthDestination(onboarded, '/runs/abc'), '/runs/abc');
});

test('an explicit return_to is left for the layout to judge', () => {
	assert.equal(postAuthDestination(fresh, '/clubs/join/xyz'), '/clubs/join/xyz');
	assert.equal(postAuthDestination(fresh, '/runs/abc'), '/runs/abc');
});

test('a profile that failed to load never diverts to a gate', () => {
	assert.equal(postAuthDestination(null, '/dashboard'), '/dashboard');
});

test('holdAppShell never holds a signed-out visitor or a public surface', () => {
	assert.equal(holdAppShell({ loggedIn: false, gatedPath: true, profile: null, profileFailed: false }), false);
	assert.equal(holdAppShell({ loggedIn: true, gatedPath: false, profile: null, profileFailed: false }), false);
	assert.equal(holdAppShell({ loggedIn: true, gatedPath: false, profile: fresh, profileFailed: false }), false);
});

test('holdAppShell holds a gated page until the profile is known', () => {
	assert.equal(holdAppShell({ loggedIn: true, gatedPath: true, profile: null, profileFailed: false }), true);
});

test('holdAppShell keeps holding while a gate is owed', () => {
	assert.equal(holdAppShell({ loggedIn: true, gatedPath: true, profile: fresh, profileFailed: false }), true);
	assert.equal(holdAppShell({ loggedIn: true, gatedPath: true, profile: unconsented, profileFailed: false }), true);
});

test('holdAppShell releases for an onboarded account and on a failed load', () => {
	assert.equal(holdAppShell({ loggedIn: true, gatedPath: true, profile: onboarded, profileFailed: false }), false);
	assert.equal(holdAppShell({ loggedIn: true, gatedPath: true, profile: null, profileFailed: true }), false);
});
