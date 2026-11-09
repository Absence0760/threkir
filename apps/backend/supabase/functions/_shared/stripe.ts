/// The Stripe SDK for the whole tier, imported once. Import Stripe from
/// here, never by specifier — `stripe_boundary.test.ts` fails on a direct
/// import.
///
/// It comes from npm, not esm.sh. esm.sh builds stripe's dependency graph
/// itself (370 modules, `qs` -> `get-intrinsic` among them) and serves a
/// rebuilt module under the same versioned URL, so in November 2026 its CDN
/// handed out two different builds of `get-intrinsic@1.3.1` at once and no
/// `deno.lock` pin could match both (decisions § 2257). An npm tarball is
/// immutable once published, and its integrity is the registry's.
///
/// npm's own declarations bind directly, so the `@ts-types` shim that
/// § 765 needed for esm.sh's rewritten ambient module is gone. The version
/// must match the root package.json's `stripe` devDependency, which is what
/// `deno check` reads the declarations from; the boundary test pins both.
/// The Stripe functions already needed the npm registry to boot (stripe
/// imports `node:http`, decisions § 699), so this adds no boot dependency.
import Stripe from 'npm:stripe@23.1.0';

/// The proof that the declarations bound, and the reason this file cannot
/// go quietly back to `any` on a Deno release, a registry change or a
/// version bump.
///
/// It has to be a NEGATIVE test. Every assignability test passes under
/// `any`, in both directions, so a positive assertion is satisfied by the
/// very collapse it exists to catch — including the usual
/// `0 extends 1 & T` any-detector, which over this import resolves to
/// `any` itself and then satisfies any constraint at all. That was tried
/// first (decisions § 765) and reported nothing with the declarations
/// unbound: a check that goes quiet. `Account.id` is a string, so
/// constraining it to `number` must fail; if it ever stops failing, the
/// `@ts-expect-error` below is unused and `deno check` reports THAT
/// instead, naming this file. No source-grep guard could see
/// a collapse here — the import it would grep for is unchanged.
type MustBeNumber<T extends number> = T;
// @ts-expect-error -- Stripe.Account['id'] is a string, not a number.
type StripeDeclarationsBind = MustBeNumber<Stripe.Account['id']>;
export type { StripeDeclarationsBind };

/// Assert that every key of a hand-shaped params object is one the SDK's
/// own params type declares. Used as a pair at the call site, which is
/// where Stripe is already imported:
///
///   type _ = AssertNoUnknownParamKeys<
///     UnknownParamKeys<Shape, Stripe.SomeCreateParams>
///   >;
///
/// Assignability alone does not check this. The value handed to a Stripe
/// call is a function RETURN, not a fresh object literal, so TypeScript
/// runs no excess-property check on it: a params helper carrying a
/// misspelled optional field compiles, and Stripe answers `Received
/// unknown parameter` at request time — a 502 for every caller. Measured
/// on this tree with the declarations fully bound: a `defualt_currency`
/// added to `events-connect-onboard`'s `AccountCreateParams` passed
/// `deno check` without a word.
///
/// The params helpers themselves stay Stripe-free on purpose:
/// `events-checkout`'s is imported by `stripe-events-webhook`, which has
/// no Stripe in its runtime graph and must not grow one (decisions § 699
/// measured a value import at 228 KB -> 2.4 MB per eszip). So the
/// assertion lives at the call site instead of in the helper's return
/// type.
export type UnknownParamKeys<Shape, Params> = Exclude<keyof Shape, keyof Params>;
export type AssertNoUnknownParamKeys<K extends never> = K;

export default Stripe;
