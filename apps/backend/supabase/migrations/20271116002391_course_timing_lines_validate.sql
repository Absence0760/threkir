-- Validates the event_courses timing-line CHECKs 20271116002390 added NOT
-- VALID (decisions § 2390), in a transaction of its own so the scan holds no
-- stronger lock than VALIDATE's SHARE UPDATE EXCLUSIVE
-- (docs/backend/migration_locks.md).

alter table public.event_courses validate constraint event_courses_start_gate_lat_check;
alter table public.event_courses validate constraint event_courses_start_gate_lng_check;
alter table public.event_courses validate constraint event_courses_start_gate_bearing_deg_check;
alter table public.event_courses validate constraint event_courses_start_gate_half_width_m_check;
alter table public.event_courses validate constraint event_courses_start_gate_source_check;
alter table public.event_courses validate constraint event_courses_start_gate_complete_check;
alter table public.event_courses validate constraint event_courses_finish_gate_lat_check;
alter table public.event_courses validate constraint event_courses_finish_gate_lng_check;
alter table public.event_courses validate constraint event_courses_finish_gate_bearing_deg_check;
alter table public.event_courses validate constraint event_courses_finish_gate_half_width_m_check;
alter table public.event_courses validate constraint event_courses_finish_gate_source_check;
alter table public.event_courses validate constraint event_courses_finish_gate_complete_check;
