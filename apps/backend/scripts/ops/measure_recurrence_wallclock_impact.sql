-- Read-only impact measure for the recurrence wall-clock fix (PR #1153).
-- Run against prod by an operator with read access; it opens a READ ONLY
-- transaction and rolls back. Output is counts plus the affected series, so
-- organisers can be told before their series moves to its intended day.
--
-- READ-ONLY. Measures which instance-keyed rows of timezoned recurring events
-- would move if expansion switched from the UTC clock to wall-clock-in-event-zone.
-- A key "survives" when, read in the event's own zone, it falls on a stored
-- byday (or starts_at's local weekday when byday is empty) at starts_at's local
-- time-of-day. Monthly: survives when local day-of-month (clamped) and local
-- time-of-day match starts_at's.
begin transaction read only;
with keyed as (
            select 'event_attendees' t, event_id, instance_start i from event_attendees
  union all select 'event_exceptions', event_id, instance_start from event_exceptions
  union all select 'event_orders', event_id, instance_start from event_orders
  union all select 'event_pricing', event_id, instance_start from event_pricing where instance_start is not null
  union all select 'event_results', event_id, instance_start from event_results
  union all select 'race_sessions', event_id, instance_start from race_sessions
  union all select 'race_pings', event_id, instance_start from race_pings
  union all select 'checkpoint_crossings', event_id, instance_start from checkpoint_crossings
  union all select 'run_photos', event_id, event_instance_start from run_photos where event_id is not null and event_instance_start is not null
  union all select 'club_posts', event_id, event_instance_start from club_posts where event_id is not null and event_instance_start is not null
  union all select 'notifications', event_id, event_instance_start from notifications where event_id is not null and event_instance_start is not null
), j as (
  select k.t, k.i, e.id, e.timezone tz, e.recurrence_freq f, e.recurrence_byday bd, e.starts_at s,
         (k.i at time zone e.timezone) li, (e.starts_at at time zone e.timezone) ls,
         (k.i at time zone 'UTC') ui, (e.starts_at at time zone 'UTC') us
  from keyed k join events e on e.id = k.event_id
  where e.recurrence_freq is not null and e.timezone is not null
), v as (
  select *,
    (array['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow from li)::int] lwd,
    (array['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow from ls)::int] swd,
    case when f = 'monthly' then
      extract(day from li) = least(extract(day from ls), extract(day from (date_trunc('month', li) + interval '1 month - 1 day')))
      and li::time = ls::time
    else
      (array['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow from li)::int]
        = any (coalesce(nullif(bd,'{}'), array[(array['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow from ls)::int]]))
      and li::time = ls::time
    end survives
  from j
)
select t as table_name,
       count(*) total,
       count(*) filter (where survives) survives_unchanged,
       count(*) filter (where not survives and i >= now()) future_would_move,
       count(*) filter (where not survives and i <  now()) past_would_move,
       count(*) filter (where not survives and li::time <> ls::time) wrong_local_time_dst,
       count(*) filter (where not survives and li::time = ls::time) wrong_local_weekday_only
from v group by rollup(t) order by t nulls last;
-- Event-level classification of every recurring series.
select
  count(*) filter (where timezone is null) as legacy_tz_null_viewer_dependent,
  count(*) filter (where timezone is not null and recurrence_freq in ('weekly','biweekly')
                   and coalesce(array_length(recurrence_byday,1),0) > 0
                   and (starts_at at time zone timezone)::date <> (starts_at at time zone 'UTC')::date)
    as wrong_weekday_chip_shape,
  count(*) filter (where timezone is not null
                   and (timestamptz '2027-01-15 12:00Z' at time zone timezone)
                       <> (timestamptz '2027-07-15 12:00Z' at time zone timezone) - interval '6 months')
    as dst_zone_hour_drift,
  count(*) filter (where timezone is not null) as timezoned_total,
  count(*) as recurring_total
from events where recurrence_freq is not null
  and (recurrence_until is null or recurrence_until > now());
-- Every live recurring series whose expansion would change, for organiser
-- comms: the wrong-weekday shape (a weekday chip whose local date differs from
-- the UTC date at starts_at) and the one-hour DST drift (any DST zone).
select c.slug as club_slug, e.id as event_id, e.title, e.timezone, e.recurrence_freq,
       e.recurrence_byday, e.starts_at,
       (e.timezone is not null and e.recurrence_freq in ('weekly','biweekly')
        and coalesce(array_length(e.recurrence_byday,1),0) > 0
        and (e.starts_at at time zone e.timezone)::date <> (e.starts_at at time zone 'UTC')::date) as wrong_weekday,
       (e.timezone is not null
        and (timestamptz '2027-01-15 12:00Z' at time zone e.timezone)
            <> (timestamptz '2027-07-15 12:00Z' at time zone e.timezone) - interval '6 months') as dst_drift
  from events e join clubs c on c.id = e.club_id
 where e.recurrence_freq is not null and e.timezone is not null
   and (e.recurrence_until is null or e.recurrence_until > now())
   and ((e.recurrence_freq in ('weekly','biweekly')
         and coalesce(array_length(e.recurrence_byday,1),0) > 0
         and (e.starts_at at time zone e.timezone)::date <> (e.starts_at at time zone 'UTC')::date)
        or (timestamptz '2027-01-15 12:00Z' at time zone e.timezone)
            <> (timestamptz '2027-07-15 12:00Z' at time zone e.timezone) - interval '6 months')
 order by c.slug, e.starts_at;
rollback;
