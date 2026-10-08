// The line the run-detail share image draws. The PNG leaves the page and is
// posted where anyone can read it, so it withholds what the public run page
// withholds: the owner's track with its leading and trailing fixes inside a
// privacy zone trimmed by `clipPointsToZones` (raw OR smoothed position in a
// zone, the rule `clip_track_for_user` applies), and no line at all while
// the zones are not known (`null`), which is never read as "no zones".
// Mirrors `runShareCardTrack` in apps/mobile_android/lib/widgets/run_share_card.dart,
// whose caller likewise refuses to open the sheet until the zones are known.

import { clipPointsToZones, type PrivacyZone } from '../routes/privacy';
import type { LinePointSource } from '../runs/track_line';

export function shareCardTrack<T extends LinePointSource>(
	track: T[],
	zones: PrivacyZone[] | null,
): T[] {
	return zones === null ? [] : clipPointsToZones(track, zones);
}
