/// Which non-owner read admitted a run, and the row it returned.
///
/// `public_runs` holds every public run and nothing else; `shared_runs`
/// (migration 20270802000003) holds the non-public runs whose audience — the
/// owner's followers, or a named-person grant — admits THIS caller, and never
/// the caller's own; `coached_runs` (20270822000011) holds the runs of the
/// athletes whose coaching link with THIS caller is active, while the
/// coach_run_map gate is open. All three are views that filter on the
/// caller's JWT, so a row from any of them is the database's own answer to
/// "may this caller see this run", and the track is served clipped against
/// the owner's zones in every case (decisions § 33, § 1878, § 1968).
///
/// Order matters only for cost: a public run is answered by the first read,
/// and an anonymous caller is in no audience and coaches nobody, so it never
/// makes the second or third. A failed read is reported as a failure rather
/// than a miss, so the handler can answer 502 for "could not find out" and
/// 404 for "not yours".

export type ViewableRunRow = {
  user_id: string | null;
  is_public: boolean | null;
  metadata: unknown;
};

export type RunAudience = 'public' | 'shared' | 'coach';

export type ViewableRunLookup =
  | { kind: 'found'; run: ViewableRunRow; audience: RunAudience }
  | { kind: 'missing' }
  | { kind: 'failed' };

export type RunViewReader = (
  view: 'public_runs' | 'shared_runs' | 'coached_runs',
) => Promise<{ data: ViewableRunRow | null; error: unknown }>;

export async function findViewableRun(
  read: RunViewReader,
  callerId: string | null,
): Promise<ViewableRunLookup> {
  const pub = await read('public_runs');
  if (pub.error) return { kind: 'failed' };
  if (pub.data) return { kind: 'found', run: pub.data, audience: 'public' };
  if (callerId === null) return { kind: 'missing' };
  const shared = await read('shared_runs');
  if (shared.error) return { kind: 'failed' };
  if (shared.data) return { kind: 'found', run: shared.data, audience: 'shared' };
  const coached = await read('coached_runs');
  if (coached.error) return { kind: 'failed' };
  if (coached.data) return { kind: 'found', run: coached.data, audience: 'coach' };
  return { kind: 'missing' };
}
