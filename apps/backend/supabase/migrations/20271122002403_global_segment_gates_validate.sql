-- Validates the catalogue timing-line CHECKs and the matched_by CHECK that
-- 20271122002402 added NOT VALID (decisions § 2402), in a transaction of its
-- own so the scan holds no stronger lock than VALIDATE's SHARE UPDATE
-- EXCLUSIVE (docs/backend/migration_locks.md). global_segment_efforts is the
-- one populated table scanned; every row carries the constant default.

alter table public.global_segments validate constraint global_segments_start_gate_lat_check;
alter table public.global_segments validate constraint global_segments_start_gate_lng_check;
alter table public.global_segments validate constraint global_segments_start_gate_bearing_deg_check;
alter table public.global_segments validate constraint global_segments_start_gate_half_width_m_check;
alter table public.global_segments validate constraint global_segments_start_gate_source_check;
alter table public.global_segments validate constraint global_segments_start_gate_complete_check;
alter table public.global_segments validate constraint global_segments_end_gate_lat_check;
alter table public.global_segments validate constraint global_segments_end_gate_lng_check;
alter table public.global_segments validate constraint global_segments_end_gate_bearing_deg_check;
alter table public.global_segments validate constraint global_segments_end_gate_half_width_m_check;
alter table public.global_segments validate constraint global_segments_end_gate_source_check;
alter table public.global_segments validate constraint global_segments_end_gate_complete_check;
alter table public.global_segment_efforts validate constraint global_segment_efforts_matched_by_check;
