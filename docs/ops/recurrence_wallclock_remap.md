# Runbook — moving recurring-event rows onto wall-clock instants

Migration `20270808000011` (decisions § 1918) changed what a recurring event's
occurrences ARE for every series with a `timezone`: they are now the
organiser's wall-clock in that zone, where every earlier build read the
weekday, day-of-month and time of day on the UTC clock. Every row keyed by an
occurrence instant — RSVPs, orders, per-occurrence pricing, cancellations,
race sessions, results, pings, checkpoint crossings, gallery photos, event
posts, notifications — was written under the old instant. This runbook moves
them. Nothing moves until an operator runs it, and nothing here runs on
`supabase db push`.

Legacy series with no `timezone` are not touched: their instants were always
minted in each viewer's own zone and no stored fact says which zone a row
meant, so they keep the looser server rule (bounds plus a whole-day offset).

## What the migration did on push

- `private.is_event_occurrence` accepts the wall-clock instant **and**, while
  the transition window is open, the UTC-clock instant every pre-§ 1918 build
  mints. Old app builds keep writing photos and RSVPs.
- **Money paths are strict from the push.** `event_occurrence_exists` (what
  `events-checkout` asks) and the `event_orders_validate_occurrence` trigger
  call it with `p_allow_legacy => false` (migration `20270808000041`, decisions
  § 1921), so no new order is opened on an instant only the old clock
  produces: an old build buying a session of a series whose two clocks
  disagree gets `404 instance_not_found` until it updates. Orders already on
  old instants are moved by the remap; the trigger accepts the move because
  the target is a wall-clock instant.
- The window is the `recurrence_utc_clock_legacy` row in
  `private.feature_flags`, which the migration seeds **enabled**. Enabled =
  open; **absent or disabled = strict**, the rule every row in that table
  follows, so a lost row can only narrow what is accepted. Nothing writes it
  afterwards but the close function below.
- `private.remap_recurrence_wallclock(...)` exists and has never been called.
  No API role can execute it; connect as `postgres`.

## Order of operations

1. **Push the migration before the web release that carries the § 1918
   clients.** A new web build mints wall-clock instants, and the database
   before this migration refuses them for photos and orders.
2. **Measure.** The owner runs the read-only impact script and decides:
   `psql "$PROD_DB_URL" -f apps/backend/scripts/ops/measure_recurrence_wallclock_impact.sql`.
   It prints, per table, how many keyed rows survive unchanged and how many
   would move (future vs past, wrong weekday vs one-hour DST drift), and lists
   the live series that change so organisers can be told first.
3. **Dry run, in one shot.** Every move is made and rolled back inside the
   function, so the counts are real — and nothing is recorded, so a dry run
   cannot be batched: a loop of them would select the same series forever. The
   function enforces that: a dry run whose `p_max_events` is below the number
   of series it would select is refused (`22023`, naming the count to pass).
   Pass a ceiling at least that large, or narrow with `p_event_ids`:
   `psql "$PROD_DB_URL" -c "select * from private.remap_recurrence_wallclock(100000, false)"`.
   Read `shift` (the pairing offset chosen per series), `moved`, `conflicts`
   (rows whose target the same identity already holds — they stay put),
   `unmapped` (rows with no counterpart, e.g. the last occurrence of a
   count-limited series whose pairing shifted), `stray` (rows on an instant
   neither clock produces) and `refused` (trigger messages). Stop here unless
   the owner has approved.
4. **Apply, in batches.** Each call is one transaction and remaps up to N
   series and records them, so the next call selects the rest; loop until a
   call returns no rows. Only an apply (`p_apply => true`) can be looped. Small batches keep row locks
   short on `race_pings` and `notifications`:
   `until [ "$(psql "$PROD_DB_URL" -Atc "select count(*) from private.remap_recurrence_wallclock(10, true)")" = 0 ]; do sleep 1; done`.
   A pilot can pass `p_event_ids => array['<uuid>']::uuid[]` to remap only
   named series first.
5. **Deploy the web release** (and ship the mobile release) right after step 4,
   so viewers see their RSVPs on the instants they now expand.
6. **Sweep during the window.** Old mobile builds keep writing UTC-clock
   instants until they are updated. A sweep moves only rows still on a
   UTC-clock-only instant, over series already remapped and not swept since the
   cutoff; loop it with one fixed cutoff (a dry-run sweep is single-shot too):
   `T=$(psql "$PROD_DB_URL" -Atc "select clock_timestamp()") && until [ "$(psql "$PROD_DB_URL" -Atc "select count(*) from private.remap_recurrence_wallclock(10, true, '$T')")" = 0 ]; do sleep 1; done`.
7. **Close the window** once the minimum supported mobile build carries § 1918
   (or a fixed 30 days after the mobile release, whichever is later): run a
   last sweep, then `psql "$PROD_DB_URL" -c "select private.close_recurrence_wallclock_transition()"`,
   which disables `recurrence_utc_clock_legacy`.
   It refuses while any keyed row still sits on a UTC-clock-only instant and
   says how many; `select * from private.recurrence_wallclock_old_only_rows()`
   lists them. Resolve each (usually a conflict: the member already holds the
   target row, so the old one can be deleted) or pass `p_force => true` to
   close anyway and leave them orphaned.
8. **Retire the branch.** After the close has held through a release, a later
   migration drops the UTC-clock acceptance (and `p_allow_legacy`) from
   `is_event_occurrence`, the `recurrence_utc_clock_legacy` row, the remap
   functions and `private.recurrence_wallclock_remaps`.

## How a row's new instant is chosen

The i-th UTC-clock occurrence of a series moves to its (i + k)-th wall-clock
occurrence. That pairing is strictly increasing and one-to-one, so two
occurrences can never fold onto one key; nearest-instant matching would, on any
series with adjacent weekday chips. `k` is picked per series from −2..2 as the
offset that moves its first 60 occurrences the least, so a New York
Wednesday 21:30 series — whose UTC-clock expansion dropped the first night and
sat on Tuesdays — moves each Tuesday row to the following Wednesday, not to the
Wednesday before it. Rows move in an order that always vacates an instant
before another row moves onto it, and a row whose unique key is already held
at its target stays where it is and is counted as a conflict.

Each processed series is recorded in `private.recurrence_wallclock_remaps`,
which is what makes a second call a no-op; the sweep reuses the series'
recorded `k`.

## What cannot be moved

- **Stripe metadata.** A Checkout Session carries the `instance_start` it was
  opened with. The webhook reads the `event_orders` row by id, and the order
  row moves, so a session completing after the remap lands on the new instant.
- **Delivered notifications and emails.** Text already sent to a member names
  the old time; the row moves, the inbox does not.
- **Capacity.** Moving RSVPs does not re-run the capacity trigger, so an
  occurrence that new builds had already filled under its wall-clock instant
  can end up over capacity. The dry run's per-series `moved` count is the
  place to spot that before applying.
