/**
 * Fail-closed feature gate for Apple sign-in.
 *
 * The Apple button on /login only works once the `apple` provider is configured
 * on the Supabase side (Services ID + Team ID + Key ID + the Sign-in-with-Apple
 * `.p8`); until then `signInWithOAuth({provider: 'apple'})` just surfaces an
 * opaque provider error. This flag is the client-visible signal for "Apple auth
 * is live": when `PUBLIC_APPLE_AUTH_ENABLED` is not explicitly truthy the button
 * renders a "coming soon" pill and its click shows a friendly notice instead of
 * starting a redirect. Unset / empty / "false" / "0" → off.
 *
 * The twin of google_auth_flag.ts, with one deliberate asymmetry: Google is
 * turned ON in `.env.development` so the e2e specs can click it, and Apple is
 * not. GoTrue validates `google` and `apple` against the real providers rather
 * than accepting the mock (tests-e2e/sso stands in as `keycloak`), and the local
 * stack's `[auth.external.apple]` is `enabled = false` — so a dev build with
 * this on would surface exactly the opaque error the flag exists to prevent.
 */
import { env } from '$env/dynamic/public';
import { isTruthyFlagValue } from './env_flag';

export function appleAuthEnabled(): boolean {
	return isTruthyFlagValue(env.PUBLIC_APPLE_AUTH_ENABLED);
}
