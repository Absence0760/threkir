package livehub

import "math"

// PrivacyZone is one geofence the broadcaster has marked as off-limits.
// The runner's home / work coordinates live here; the hub MUST NOT
// publish pings that fall inside any zone. Mirrors the on-disk shape
// stored in `user_settings.prefs.privacy_zones`:
//
//	{ "lat": 47.37, "lng": 8.54, "radius_m": 200 }
type PrivacyZone struct {
	Lat     float64 `json:"lat"`
	Lng     float64 `json:"lng"`
	RadiusM float64 `json:"radius_m"`
}

// IsInAnyZone returns true when the lat/lng falls inside any of the
// supplied [zones]. Pure haversine — matches:
//
//   - `apps/web/src/lib/privacy.ts`  → `isInAnyZone`
//   - `apps/mobile_android/lib/privacy.dart` → `isInAnyZone`
//
// Keep this implementation in lockstep with those when extending —
// the spectator-side clip on the legacy Supabase Realtime path is
// enforced by the `live_run_pings_drop_in_zone` BEFORE-INSERT
// trigger in `apps/backend/supabase/migrations/20260618_001_*.sql`;
// the hub-side clip below is the equivalent for the WebSocket path.
func IsInAnyZone(lat, lng float64, zones []PrivacyZone) bool {
	for _, z := range zones {
		if haversineMetres(lat, lng, z.Lat, z.Lng) <= z.EffectiveRadiusM() {
			return true
		}
	}
	return false
}

// MinZoneRadiusM is the smallest radius a zone covers. The phone once
// offered 50 m; a zone saved then covers 100 m now, so aligning every
// platform on 100-1000 m never shrank anyone's privacy. Mirrors
// `PRIVACY_ZONE_MIN_RADIUS_M` (web), `privacyZoneMinRadiusM` (mobile) and
// `privacy_in_any_zone` (Postgres).
const MinZoneRadiusM = 100.0

// EffectiveRadiusM is the radius the zone covers: what was stored, never
// less than [MinZoneRadiusM]. A NaN radius is the floor.
func (z PrivacyZone) EffectiveRadiusM() float64 {
	if z.RadiusM > MinZoneRadiusM {
		return z.RadiusM
	}
	return MinZoneRadiusM
}

const earthRadiusMetres = 6371000.0

// haversineMetres — great-circle distance in metres between two
// lat/lng pairs. Package-private; callers go through [IsInAnyZone].
func haversineMetres(lat1, lng1, lat2, lng2 float64) float64 {
	const degToRad = math.Pi / 180
	phi1 := lat1 * degToRad
	phi2 := lat2 * degToRad
	dPhi := (lat2 - lat1) * degToRad
	dLambda := (lng2 - lng1) * degToRad
	a := math.Sin(dPhi/2)*math.Sin(dPhi/2) +
		math.Cos(phi1)*math.Cos(phi2)*
			math.Sin(dLambda/2)*math.Sin(dLambda/2)
	return earthRadiusMetres * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
