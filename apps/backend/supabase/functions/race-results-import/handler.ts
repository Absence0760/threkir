/// Request handler for race-results-import, factored out of index.ts behind
/// injected deps (env lookup, the caller-scoped Supabase client, `fetch`) so a
/// deno test can drive its gates, its rate-limit buckets and its upstream error
/// paths against fakes, the way auth-email/handler.ts is driven. index.ts passes
/// `Deno.env`, a `createClient` carrying the caller's JWT, and the global fetch.

import type { DbClient } from '../_shared/database.ts';
import { resolveImportAudience } from '../_shared/privacy_default.ts';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { isValidUuid } from '../_shared/input_validation.ts';
import {
  chronoTrackConfigured,
  chronoTrackResultsUrl,
  chronoTrackScopeGate,
  extractChronoTrackResults,
  extractRunSignUpResults,
  extractUltraSignUpPeople,
  filterResultsByBib,
  mapChronoTrackResult,
  mapRunSignUpResult,
  matchResultGate,
  parseRaceResultRow,
  resultsPossiblyTruncated,
  runSignUpErrorOf,
  runSignUpEventsOn,
  runSignUpRaceUrl,
  runSignUpResultsUrl,
  runSignUpScopeGate,
  ultraSignUpCandidates,
  ultraSignUpEnabled,
  ultraSignUpHistoryUrl,
  ultraSignUpImportRows,
  ultraSignUpNamePart,
  ultraSignUpProbe,
  ultraSignUpScopeGate,
  type MappedRaceRun,
} from './lib.ts';
import { reconcileImportBatch } from '../_shared/external_id_batch.ts';
import { isUpstreamTimeout, UPSTREAM_TIMEOUT_MS } from '../_shared/upstream_deadline.ts';

interface RequestBody {
  provider?: unknown; // 'runsignup' | 'ultrasignup' | 'chronotrack' | 'paste'
  listingId?: unknown; // race_listings.id to import onto / link
  ultraSignUpPersonId?: unknown; // UltraSignup: the picked person's `Id`
  ultraSignUpFirstName?: unknown; // UltraSignup: the name that person was found under
  ultraSignUpLastName?: unknown;
  ultraSignUpFlow?: unknown; // UltraSignup probe: 'person' from a client that speaks it
  lookup?: unknown; // UltraSignup: list the people a name answers with, import nothing
  bib?: unknown; // RunSignUp / ChronoTrack: the runner's bib, the only scope either honours
  result?: unknown; // paste-mode single result row
  matchRunId?: unknown; // when set, enrich THIS existing run instead of inserting
  probe?: unknown; // when true, only report whether `provider` is configured
}

export interface RaceResultsImportDeps {
  getEnv: (name: string) => string | undefined;
  /// A client that acts as the caller: their JWT, the publishable key.
  userClient: (authHeader: string) => DbClient;
  fetch: typeof fetch;
  /// Overrides `UPSTREAM_TIMEOUT_MS`, so a test can watch the deadline fire.
  upstreamTimeoutMs?: number;
}

type UpstreamRead = { payload: unknown } | { failed: Response };

export function makeRaceResultsImportHandler(
  deps: RaceResultsImportDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    const guarded = await readJsonWithLimit<RequestBody>(req, 8192);
    if ('tooLarge' in guarded) return guarded.tooLarge;

    // Authenticate before parsing the body (parity with parkrun-import).
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return Response.json({ error: 'unauthorized' }, { status: 401 });

    const supabase = deps.userClient(authHeader);

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });

    const body = (guarded.body ?? {}) as RequestBody;

    // Every provider call in this request reads through here and shares ONE
    // deadline, started at the first call: the RunSignUp leg can make nine in
    // sequence, and a bound per call would let them sum past the runtime's
    // 150 s clock, which answers a bare 500 (decisions § 1912). A timeout is a
    // 504 and an unreachable feed a 502. Nothing is written until every call
    // has answered, so a deadline that fires mid-leg inserts nothing.
    let deadline: AbortSignal | null = null;
    const userAgent = deps.getEnv('RACE_IMPORT_USER_AGENT') || 'RunApp/1.0';
    const readUpstream = async (provider: string, url: string): Promise<UpstreamRead> => {
      deadline ??= AbortSignal.timeout(deps.upstreamTimeoutMs ?? UPSTREAM_TIMEOUT_MS);
      const timeout = () =>
        Response.json({ error: `${provider} upstream timeout` }, { status: 504 });
      let upstream: Response;
      try {
        deadline.throwIfAborted();
        upstream = await deps.fetch(url, { headers: { 'User-Agent': userAgent }, signal: deadline });
      } catch (err) {
        return {
          failed: isUpstreamTimeout(err)
            ? timeout()
            : Response.json({ error: `${provider} upstream unreachable` }, { status: 502 }),
        };
      }
      if (!upstream.ok) {
        // Fail loud on a non-2xx upstream rather than feeding an error page in.
        upstream.body?.cancel().catch(() => {});
        return {
          failed: Response.json({ error: `${provider} upstream ${upstream.status}` }, { status: 502 }),
        };
      }
      try {
        return { payload: await upstream.json() };
      } catch (err) {
        return {
          failed: isUpstreamTimeout(err)
            ? timeout()
            : Response.json({ error: `${provider} upstream not JSON` }, { status: 502 }),
        };
      }
    };
    const provider = typeof body.provider === 'string' ? body.provider : '';
    const isProbe = body.probe === true;
    const isLookup = !isProbe && provider === 'ultrasignup' && body.lookup === true;

    // Separate buckets, because these are different costs wearing one name — the
    // split `race-listings-sync` already carries (decisions § 977).
    //
    // An IMPORT makes an outbound call carrying OUR RunSignUp / ChronoTrack
    // credential (or, for UltraSignup, from OUR egress IP), whose budget is
    // per-application and shared by the whole deployment, and then writes the caller's `runs`. 8/hour free is right
    // for that, and falling open on an RPC error would spend the credential on a
    // request whose insert is headed for the same database that just failed
    // (decisions § 974).
    //
    // A PROBE reads env vars and returns. Charging it to the import bucket meant
    // every settings-screen load spent an import: one probe per credential-gated
    // leg the screen offers, so a runner who opened Settings a few times in an
    // hour lost the ability to import a result at all — and since § 1007 an
    // exhausted bucket answers 429, which every client grades as "provider
    // unavailable", so the failure is silent and total rather than a limit the
    // runner can see. Its own generous bucket costs nothing.
    //
    // An UltraSignup LOOKUP is a third cost: one outbound call to a keyless feed
    // on our egress IP, and no write. It gets a bucket of its own so finding
    // yourself in Settings cannot spend the imports, while still bounding how
    // hard one account can drive our IP at UltraSignup (decisions § 1841).
    const denied = isProbe
      ? await checkRateLimitTiered(
        supabase,
        user.id,
        'race-results-import:probe',
        60,
        240,
        3600,
        { failClosed: true },
      )
      : isLookup
      ? await checkRateLimitTiered(
        supabase,
        user.id,
        'race-results-import:lookup',
        20,
        60,
        3600,
        { failClosed: true },
      )
      : await checkRateLimitTiered(supabase, user.id, 'race-results-import', 8, 32, 3600, {
        failClosed: true,
      });
    if (denied) return denied;

    // Provider-availability probe: report fail-closed (503 provider_not_configured)
    // when the named provider's credentials are unset, without needing a listing.
    // The ChronoTrack Settings card uses this to disable itself with an explainer.
    if (isProbe) {
      // Every credential-gated provider has to be probed: reporting
      // `configured: true` for a leg whose keys are unset made the UI enable a
      // card that 503s on the very next call. RunSignUp is not one of them any
      // more — its results feed is public, so it answers on any deployment.
      if (provider === 'chronotrack' && !chronoTrackConfigured(deps.getEnv)) {
        return Response.json({ error: 'provider_not_configured' }, { status: 503 });
      }
      // UltraSignup needs no key — its feed is keyless — so it answers on the
      // deployment's opt-in, and on whether the CALLER speaks the person flow: a
      // client that would send the old athlete id is told the leg is unavailable
      // rather than shown a tile whose every import 400s (decisions § 1841).
      if (provider === 'ultrasignup') {
        const gate = ultraSignUpProbe(deps.getEnv, body.ultraSignUpFlow);
        if (!gate.ok) {
          return Response.json(
            gate.reason ? { error: gate.error, reason: gate.reason } : { error: gate.error },
            { status: gate.status },
          );
        }
      }
      if (!['runsignup', 'ultrasignup', 'chronotrack', 'paste'].includes(provider)) {
        // An unrecognised provider is not "configured" — answering true for it is
        // the same class of bug as the two credential-gated legs above.
        return Response.json({ error: 'unknown_provider' }, { status: 400 });
      }
      return Response.json({ configured: true });
    }

    // UltraSignup lookup: the people a name answers with, so the runner can pick
    // themselves in Settings. Reads nothing of ours and writes nothing.
    if (isLookup) {
      if (!ultraSignUpEnabled(deps.getEnv)) {
        return Response.json({ error: 'provider_not_configured' }, { status: 503 });
      }
      const firstName = ultraSignUpNamePart(body.ultraSignUpFirstName);
      const lastName = ultraSignUpNamePart(body.ultraSignUpLastName);
      if (!firstName || !lastName) {
        return Response.json({ error: 'ultrasignup_name_required' }, { status: 400 });
      }
      const people = await readUpstream('ultrasignup', ultraSignUpHistoryUrl(firstName, lastName));
      if ('failed' in people) return people.failed;
      return Response.json({
        candidates: ultraSignUpCandidates(extractUltraSignUpPeople(people.payload)),
      });
    }

    const listingId = typeof body.listingId === 'string' ? body.listingId : '';
    if (!listingId) return Response.json({ error: 'listingId required' }, { status: 400 });
    // Without this the listing lookup below raises 22P02, which the
    // `listingErr || !listing` collapse reports as a 404 "not found" — a
    // malformed id looks to the caller like a missing race.
    if (!isValidUuid(listingId)) {
      return Response.json({ error: 'listingId must be a UUID' }, { status: 400 });
    }

    // The calendar is public-read through the redacted public_race_listings
    // view (20270320_001 — the base table is submitter-own-rows only), so the
    // user's own client resolves the race name / date / distance there.
    const { data: listing, error: listingErr } = await supabase
      .from('public_race_listings')
      .select('id, provider, provider_race_id, name, race_date, distance_m')
      .eq('id', listingId)
      .maybeSingle();
    if (listingErr || !listing) {
      return Response.json({ error: 'race listing not found' }, { status: 404 });
    }

    // Honour privacy_default (parity with parkrun / Strava / manual saves); any
    // read error falls closed to owner-only.
    const audience = await resolveImportAudience(supabase, user.id);

    const mapOpts = {
      userId: user.id,
      listingId: listing.id as string,
      raceName: (listing.name as string) ?? '',
      raceDate: (listing.race_date as string) ?? '',
      distanceM: (listing.distance_m as number | null) ?? null,
      isPublic: audience.isPublic,
      followersOnly: audience.followersOnly,
    };

    let mapped: MappedRaceRun[] = [];
    // Whether the provider fetch may have been cut short of the whole field. A
    // paste carries one row and can never be, so it stays false.
    let complete = true;

    if (provider === 'runsignup') {
      // Keyless: the race and results feeds are public, and the key pair is
      // sent only when both halves are set (decisions § 1899 for listings, the
      // same rule here).
      const apiKey = deps.getEnv('RUNSIGNUP_API_KEY') ?? null;
      const apiSecret = deps.getEnv('RUNSIGNUP_API_SECRET') ?? null;
      const raceId = (listing.provider_race_id as string | null) ?? '';
      if (!raceId) {
        return Response.json({ error: 'listing has no RunSignUp race id' }, { status: 400 });
      }
      // Fail closed: an unscoped fetch returns the entire finisher field, which
      // would be imported as the caller's own runs (issue #360). A bib is the
      // only scope the feed honours, so it is required before any fetch.
      const bib = typeof body.bib === 'string' ? body.bib : undefined;
      const scope = runSignUpScopeGate({ bib });
      if (!scope.ok) {
        return Response.json({ error: scope.error }, { status: scope.status });
      }
      const readFeed = async (url: string): Promise<UpstreamRead> => {
        const read = await readUpstream('runsignup', url);
        // RunSignUp refuses a request with HTTP 200 and an error envelope;
        // reading that as an empty field would tell the runner they were not
        // in a race they ran.
        if ('payload' in read && runSignUpErrorOf(read.payload) !== null) {
          return { failed: Response.json({ error: 'runsignup upstream error' }, { status: 502 }) };
        }
        return read;
      };

      const race = await readFeed(runSignUpRaceUrl({ raceId, apiKey, apiSecret }));
      if ('failed' in race) return race.failed;
      // get-results needs an event id, and one race morning can hold several
      // events. Each of the listing day's running events is asked for this bib,
      // the listing's own distance first, until one answers.
      const events = runSignUpEventsOn(race.payload, mapOpts.raceDate, mapOpts.distanceM);
      if (events.length === 0) {
        return Response.json({ error: 'runsignup_event_not_found' }, { status: 404 });
      }
      for (const event of events) {
        const results = await readFeed(
          runSignUpResultsUrl({ raceId, eventId: event.eventId, bib: bib!, apiKey, apiSecret }),
        );
        if ('failed' in results) return results.failed;
        const rows = extractRunSignUpResults(results.payload);
        if (resultsPossiblyTruncated(rows.length)) complete = false;
        // The run is as long as the event the runner ran, which is not the
        // listing's headline distance when they ran its 5K.
        const eventOpts = { ...mapOpts, distanceM: event.distanceM ?? mapOpts.distanceM };
        mapped = filterResultsByBib(
          rows
            .map((r) => mapRunSignUpResult(r, eventOpts))
            .filter((r): r is MappedRaceRun => r !== null),
          bib!,
        );
        if (mapped.length > 0) break;
      }
    } else if (provider === 'ultrasignup') {
      // Opt-in per deployment; the feed is keyless, so the switch is the gate.
      if (!ultraSignUpEnabled(deps.getEnv)) {
        return Response.json({ error: 'provider_not_configured' }, { status: 503 });
      }
      const providerRaceId = (listing.provider_race_id as string | null) ?? '';
      if (!providerRaceId) {
        return Response.json({ error: 'listing has no UltraSignup race id' }, { status: 400 });
      }
      // Scope BEFORE the fetch: the feed is keyed by name and answers with every
      // same-named person, so without the picked `Id` there is no telling which
      // of them is the caller (issue #360's failure mode, by name instead of by
      // race).
      const person = ultraSignUpScopeGate({
        personId: body.ultraSignUpPersonId,
        firstName: body.ultraSignUpFirstName,
        lastName: body.ultraSignUpLastName,
      });
      if (!person.ok) {
        return Response.json({ error: person.error }, { status: person.status });
      }
      const history = await readUpstream(
        'ultrasignup',
        ultraSignUpHistoryUrl(person.firstName, person.lastName),
      );
      if ('failed' in history) return history.failed;
      const payload = history.payload;
      // Attribution happens here and nowhere else: the runner's own results,
      // and of those only the one whose `event_distance_id` and date are this
      // listing's (decisions § 975, § 1841).
      const rows = ultraSignUpImportRows(payload, {
        ...mapOpts,
        personId: person.personId,
        providerRaceId,
      });
      if (!rows.personFound) {
        // The stored person is not among the people that name answers with any
        // more. Saying "no result for this race" would be false; the link needs
        // redoing.
        return Response.json({ error: 'ultrasignup_person_not_found' }, { status: 404 });
      }
      complete = !resultsPossiblyTruncated(rows.considered);
      mapped = rows.mapped;
    } else if (provider === 'chronotrack') {
      // Fail closed when the ChronoTrack Live credentials are unconfigured. The
      // whole ChronoTrack leg is gated on its own CHRONOTRACK_* creds; until they
      // are provisioned the EF is inert and the UI shows the unavailable explainer.
      if (!chronoTrackConfigured(deps.getEnv)) {
        return Response.json({ error: 'provider_not_configured' }, { status: 503 });
      }
      const clientId = deps.getEnv('CHRONOTRACK_CLIENT_ID')!;
      const ctUserId = deps.getEnv('CHRONOTRACK_USER_ID')!;
      const password = deps.getEnv('CHRONOTRACK_PASSWORD')!;
      const eventId = (listing.provider_race_id as string | null) ?? '';
      if (!eventId) {
        return Response.json({ error: 'listing has no ChronoTrack event id' }, { status: 400 });
      }
      // Scope BEFORE the fetch, exactly as the RunSignUp leg does: an unscoped
      // ChronoTrack request returns the whole finisher field, and every row of it
      // would be inserted as the caller's own run (issue #360's failure mode, on
      // the provider that never got the gate).
      const ctBib = typeof body.bib === 'string' ? body.bib.trim() : undefined;
      const ctScope = chronoTrackScopeGate({ bib: ctBib });
      if (!ctScope.ok) {
        return Response.json({ error: ctScope.error }, { status: ctScope.status });
      }
      const url = chronoTrackResultsUrl({
        eventId,
        clientId,
        userId: ctUserId,
        password,
        bib: ctBib,
      });
      const feed = await readUpstream('chronotrack', url);
      if ('failed' in feed) return feed.failed;
      const rows = extractChronoTrackResults(feed.payload);
      complete = !resultsPossiblyTruncated(rows.length);
      mapped = rows
        .map((r) => mapChronoTrackResult(r, mapOpts))
        .filter((r): r is MappedRaceRun => r !== null);
      // Narrow client-side too, exactly as the RunSignUp leg does: the gate only
      // proves the REQUEST was scoped, not that the upstream honoured `?bib=`.
      // An API that ignores a filter it cannot parse returns the whole field, and
      // every row of it carries the caller's user_id by then (issue #360).
      // mapChronoTrackResult populates metadata.bib, so this is the same helper.
      if (ctBib) mapped = filterResultsByBib(mapped, ctBib);
    } else if (provider === 'paste') {
      if (!body.result || typeof body.result !== 'object') {
        return Response.json({ error: 'result required for paste import' }, { status: 400 });
      }
      const one = parseRaceResultRow(body.result as Record<string, unknown>, mapOpts);
      if (!one) {
        return Response.json({ error: 'pasted result has no usable time' }, { status: 400 });
      }
      mapped = [one];
    } else {
      return Response.json({ error: 'unsupported provider' }, { status: 400 });
    }

    if (mapped.length === 0) {
      // "We read the whole field and you are not in it" and "we read the first
      // 2,000 finishers and you were not among them" are different sentences, and
      // reporting the second as the first tells a runner they did not finish a
      // race they finished. Refuse rather than answer a successful import of
      // nothing (decisions § 976).
      if (!complete) {
        return Response.json(
          { error: 'upstream_results_truncated', complete: false },
          { status: 502 },
        );
      }
      return Response.json({ imported: 0, skipped: 0, enriched: 0, complete: true });
    }

    // Enrich an existing recorded run rather than inserting a duplicate when the
    // user matched an in-app run to this race (the auto-match-on-record seam).
    // The match writes onto the runner's OWN run row (RLS-scoped) — a single
    // result is expected in this mode.
    const matchRunId = typeof body.matchRunId === 'string' ? body.matchRunId : '';
    if (matchRunId && !isValidUuid(matchRunId)) {
      return Response.json({ error: 'matchRunId must be a UUID' }, { status: 400 });
    }
    if (matchRunId) {
      // Enrich merges ONE result onto the caller's own run. More than one mapped
      // result is ambiguous — reject rather than stamp a stranger's mapped[0]
      // onto the run (issue #360).
      const gate = matchResultGate(mapped.length);
      if (!gate.ok) {
        return Response.json({ error: gate.error }, { status: gate.status });
      }
      const result = mapped[0];
      const { data: existing } = await supabase
        .from('runs')
        .select('id, metadata, user_id')
        .eq('id', matchRunId)
        .maybeSingle();
      if (!existing || existing.user_id !== user.id) {
        return Response.json({ error: 'run not found' }, { status: 404 });
      }
      // `runs.metadata` is jsonb, so the column can legally hold an array or a
      // scalar as well as an object, and spreading a string would splat its
      // characters in as numeric keys. `typeof x === 'object'` alone is true for
      // an array (decisions § 662), so both halves of the check are load-bearing.
      const prior = existing.metadata;
      const merged = {
        ...(prior !== null && typeof prior === 'object' && !Array.isArray(prior) ? prior : {}),
        ...result.metadata,
      };
      const { error } = await supabase
        .from('runs')
        .update({ metadata: merged, race_listing_id: result.race_listing_id })
        .eq('id', matchRunId)
        .eq('user_id', user.id);
      if (error) {
        return Response.json({ error: 'failed to enrich run' }, { status: 500 });
      }
      return Response.json({ imported: 0, skipped: 0, enriched: 1, complete });
    }

    // Plain-insert path (no recorded counterpart). Dedupe per-user against
    // existing external_ids first — the runs.external_id index is a PER-USER
    // PARTIAL unique, which PostgREST onConflict can't target (see parkrun).
    const externalIds = mapped.map((r) => r.external_id);
    const { data: seenRows, error: seenErr } = await supabase
      .from('runs')
      .select('external_id')
      .eq('user_id', user.id)
      .in('external_id', externalIds);
    // ... and against the bibs already imported for THIS listing. The
    // external_id spells the listing's name, and the race-calendar sweep
    // rewrites that name whenever the provider does (decisions § 1902), so a
    // runner re-importing after a rename would get an id nothing stored carries
    // and a second copy of the same race. One listing is one race on one day,
    // so a bib already filed under it is that result, whatever it was called.
    const { data: listingRows, error: listingRunsErr } = await supabase
      .from('runs')
      .select('bib:metadata->>bib')
      .eq('user_id', user.id)
      .eq('race_listing_id', mapOpts.listingId);
    if (seenErr || listingRunsErr) {
      // A failed read is not an empty history: going on would insert a race
      // the runner may already hold.
      return Response.json({ error: 'race import could not check for duplicates' }, { status: 500 });
    }
    const filedBibs = new Set(
      (listingRows ?? []).map((r) => r.bib).filter((b): b is string => typeof b === 'string' && b !== ''),
    );
    const alreadyFiled = mapped
      .filter((r) => typeof r.metadata.bib === 'string' && filedBibs.has(r.metadata.bib))
      .map((r) => r.external_id);
    // Reconciled against the batch itself as well as against what is stored.
    // `external_id` is `race:{name}:{date}:{bib}` and both the name and the date
    // come from the ONE listing, so two mapped results carrying the same bib
    // collide — which the RunSignUp extractor produces whenever a runner appears
    // in more than one of the race's `individual_results_sets`. The insert below
    // is a single statement against a per-user unique index, so that collision
    // loses every other result in the import rather than the duplicate.
    const batch = reconcileImportBatch(
      mapped,
      [
        ...(seenRows ?? []).map((r) => r.external_id).filter((id): id is string => id !== null),
        ...alreadyFiled,
      ],
    );
    const fresh = batch.fresh.map((r) => ({ ...r, id: crypto.randomUUID(), user_id: user.id }));
    const skipped = batch.skipped;

    let imported = 0;
    if (fresh.length > 0) {
      const { error } = await supabase.from('runs').insert(fresh);
      if (error) {
        return Response.json({ error: 'race import failed to save' }, { status: 500 });
      }
      imported = fresh.length;
    }

    return Response.json({ imported, skipped, enriched: 0, complete });
  };
}
