"""Replays the GPS ground-truth corpus through the reference estimator.

Every `*.manifest.json` under the corpus directory names one track file and
the course's known distance (surveyed, wheel-measured, or a certified lane-1
track -- never a watch reading). The track is replayed through
scripts/gps_distance/reference.py and the run fails when any entry's saved
distance lands outside that entry's error budget. The error is reported
SIGNED, so a filter that cuts corners under trees or between buildings shows
up as a negative number rather than hiding inside an absolute one.

Diagnostics printed per entry, for tuning (issue #1090 item 2):
  forward    the causal filter's distance (what the live screen shows)
  saved      smooth_distance's figure (what a saved run stores), when the
             reference has the smoother
  hop        the raw fix-to-fix haversine sum, for contrast
  device     the file's own distance (FIT record.distance), when it has one
  mean NIS   mean normalised innovation squared of the accepted fixes. With
             a consistent filter it averages 2 (two degrees of freedom);
             persistently above means R or Q_ACCEL is too small for this
             course, below means too large
  C          lag-1 autocorrelation of the fix-minus-smoothed residuals, an
             estimate of Ranacher et al. 2015's error autocorrelation
  rejected   fixes the innovation gate dropped

NEES needs the true state at every fix, which only a synthetic entry has; a
generator that writes truth beside its track can add it in `nees_hook`.

Stdlib only. Usage:
  python3 -I scripts/gps_distance/replay_corpus.py [corpus_dir] [--json]
Exit status: 0 all within budget, 1 any outside, 2 a malformed corpus.
"""
import gzip
import json
import math
import os
import struct
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reference  # noqa: E402

COURSE_TYPES = {"track", "road", "trail", "urban"}
MAX_SPEED_MPS = {"walk": 5.0, "cycle": 25.0, "hike": 6.0, "stroller": 9.0}
HAVERSINE_R_M = 6371000.0


class CorpusError(Exception):
    pass


# ---------------------------------------------------------------------------
# Track readers. Each returns a list of fix dicts {t, lat, lng, acc, speed,
# speedAcc, bearing} (t seconds since the first timestamp) plus the file's own
# total distance or None.

def _iso_seconds(ts):
    if not isinstance(ts, str):
        return None
    s = ts.strip().replace("Z", "+00:00")
    try:
        d = datetime.fromisoformat(s)
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.timestamp()


def _finite(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def read_threkir_json(path):
    """The stored track blob (`{user_id}/{run_id}.json.gz` in the `runs`
    bucket, or the same list from the data export). Carries the Doppler keys,
    so this is the format that replays what the phone actually saw."""
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8") as f:
        pts = json.load(f)
    if not isinstance(pts, list):
        raise CorpusError("%s: expected a JSON list of waypoints" % path)
    fixes = []
    for p in pts:
        if not isinstance(p, dict):
            continue
        t = _iso_seconds(p.get("ts"))
        if t is None or not (_finite(p.get("lat")) and _finite(p.get("lng"))):
            continue
        fixes.append({"t": t, "lat": float(p["lat"]), "lng": float(p["lng"]),
                      "acc": p.get("accuracyMetres"), "speed": p.get("speedMps"),
                      "speedAcc": p.get("speedAccuracyMps"), "bearing": p.get("bearingDeg")})
    return fixes, None


def read_gpx(path):
    """GPX 1.0 / 1.1 trkpt with <time>. Position only: no GPX writer in the
    tree or on a Garmin exports Doppler speed."""
    root = ET.parse(path).getroot()
    fixes = []
    for el in root.iter():
        if not el.tag.endswith("trkpt"):
            continue
        try:
            lat, lng = float(el.get("lat")), float(el.get("lon"))
        except (TypeError, ValueError):
            continue
        t = None
        for child in el:
            if child.tag.endswith("time"):
                t = _iso_seconds(child.text)
        if t is None or not (math.isfinite(lat) and math.isfinite(lng)):
            continue
        fixes.append({"t": t, "lat": lat, "lng": lng})
    return fixes, None


_FIT_EPOCH = 631065600  # 1989-12-31T00:00:00Z


def read_fit(path):
    """Minimal FIT activity decoder: record messages (global 20) for
    timestamp, position and distance. Position only goes to the estimator --
    a Garmin's record.speed is its own filtered speed, not raw Doppler -- and
    the last record.distance comes back as the device's figure."""
    with open(path, "rb") as f:
        b = f.read()
    if len(b) < 12 or b[8:12] != b".FIT":
        raise CorpusError("%s: not a FIT file" % path)
    hsize = b[0]
    data_size = struct.unpack_from("<I", b, 4)[0]
    off, end = hsize, min(len(b), hsize + data_size)
    defs = {}
    last_ts = None
    fixes, device = [], None
    while off < end:
        h = b[off]
        off += 1
        compressed = h & 0x80
        if not compressed and h & 0x40:
            local = h & 0x0F
            arch = b[off + 1]
            fmt = ">" if arch == 1 else "<"
            gnum = struct.unpack_from(fmt + "H", b, off + 2)[0]
            nf = b[off + 4]
            off += 5
            fields = []
            for _ in range(nf):
                fields.append((b[off], b[off + 1]))
                off += 3
            size = sum(s for _, s in fields)
            if h & 0x20:
                nd = b[off]
                off += 1
                for _ in range(nd):
                    size += b[off + 1]
                    off += 3
            defs[local] = (gnum, fmt, fields, size)
            continue
        local = (h >> 5) & 0x03 if compressed else h & 0x0F
        if local not in defs:
            raise CorpusError("%s: data message before its definition" % path)
        gnum, fmt, fields, size = defs[local]
        if gnum == 20:
            vals = {}
            o = off
            for num, sz in fields:
                if num in (0, 1) and sz == 4:
                    v = struct.unpack_from(fmt + "i", b, o)[0]
                    if v != 0x7FFFFFFF:
                        vals[num] = v * (180.0 / 2 ** 31)
                elif num in (5, 253) and sz == 4:
                    v = struct.unpack_from(fmt + "I", b, o)[0]
                    if v != 0xFFFFFFFF:
                        vals[num] = v
                o += sz
            ts = vals.get(253)
            if compressed and last_ts is not None:
                t_off = h & 0x1F
                ts = (last_ts & ~0x1F) + t_off + (0x20 if t_off < (last_ts & 0x1F) else 0)
            if ts is not None:
                last_ts = ts
            if 5 in vals:
                device = vals[5] / 100.0
            if ts is not None and 0 in vals and 1 in vals and abs(vals[0]) <= 90:
                fixes.append({"t": float(ts + _FIT_EPOCH), "lat": vals[0], "lng": vals[1]})
        off += size
    return fixes, device


READERS = {"threkir_json": read_threkir_json, "gpx": read_gpx, "fit": read_fit}


def infer_format(track_file):
    lower = track_file.lower()
    if lower.endswith((".json", ".json.gz")):
        return "threkir_json"
    if lower.endswith(".gpx"):
        return "gpx"
    if lower.endswith(".fit"):
        return "fit"
    raise CorpusError("cannot infer the format of %s; set `format`" % track_file)


# ---------------------------------------------------------------------------
# Manifest.

REQUIRED = ("id", "track_file", "known_distance_m", "distance_source", "course_type",
            "device", "platform", "error_budget_pct")


def load_manifest(path):
    with open(path, encoding="utf-8") as f:
        m = json.load(f)
    missing = [k for k in REQUIRED if k not in m]
    if missing:
        raise CorpusError("%s: missing %s" % (path, ", ".join(missing)))
    if m["course_type"] not in COURSE_TYPES:
        raise CorpusError("%s: course_type %r is not one of %s"
                          % (path, m["course_type"], sorted(COURSE_TYPES)))
    for k in ("known_distance_m", "error_budget_pct"):
        if not (_finite(m[k]) and m[k] > 0):
            raise CorpusError("%s: %s must be a positive number" % (path, k))
    m.setdefault("format", infer_format(m["track_file"]))
    if m["format"] not in READERS:
        raise CorpusError("%s: format %r is not one of %s" % (path, m["format"], sorted(READERS)))
    m.setdefault("synthetic", False)
    m["_dir"] = os.path.dirname(path)
    return m


# ---------------------------------------------------------------------------
# Replay.

def _haversine(a, b):
    p1, p2 = math.radians(a["lat"]), math.radians(b["lat"])
    dp, dl = p2 - p1, math.radians(b["lng"] - a["lng"])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * HAVERSINE_R_M * math.asin(math.sqrt(h))


def _median_interval(fixes):
    iv = sorted(b["t"] - a["t"] for a, b in zip(fixes, fixes[1:]) if b["t"] > a["t"])
    if not iv:
        return 1.0
    mid = len(iv) // 2
    return iv[mid] if len(iv) % 2 else (iv[mid - 1] + iv[mid]) / 2


def _forward(fixes, max_speed, interval):
    """Forward filter replay plus mean NIS over accepted fixes. NIS is
    recomputed from the recorded prediction with the same formula the gate
    uses; when the reference does not record predictions it is None."""
    try:
        est = reference.GpsDistanceEstimator(max_speed, interval, None, record=True)
    except TypeError:
        est = reference.GpsDistanceEstimator(max_speed, interval, None)
    min_sigma = getattr(reference, "MIN_POS_SIGMA_M", 3.0)
    gate = getattr(reference, "GATE_CHI2", math.inf)
    nis_sum, nis_n = 0.0, 0
    for f in fixes:
        r_scale = getattr(est, "r_scale", 1.0)
        recs = getattr(est, "records", None) or []
        n_before = len(recs)
        est.add_fix(f["t"], f["lat"], f["lng"], f.get("acc"), f.get("speed"),
                    f.get("speedAcc"), f.get("bearing"))
        recs = getattr(est, "records", None) or []
        if len(recs) <= n_before:
            continue
        rec = recs[-1]
        pred = rec.get("pred")
        if pred is None or rec.get("anchor"):
            continue
        acc = f.get("acc")
        sigma = acc if (_finite(acc) and acc > 0) else min_sigma
        r = max(max(sigma, min_sigma) ** 2 * r_scale, min_sigma ** 2)
        zx, zy = est._project(f["lat"], f["lng"])
        (px, _, ax, _, _), (py, _, ay, _, _) = pred
        nis = (zx - px) ** 2 / (ax + r) + (zy - py) ** 2 / (ay + r)
        if nis <= gate:
            nis_sum += nis
            nis_n += 1
    if fixes and hasattr(est, "finish"):
        est.finish(fixes[-1]["t"])
    return est, (nis_sum / nis_n if nis_n else None)


def _smoothed(fixes, max_speed, interval):
    if not hasattr(reference, "smooth_distance"):
        return None
    events = [dict(f, type="fix") for f in fixes]
    if fixes:
        events.append({"type": "finish", "t": fixes[-1]["t"]})
    return reference.smooth_distance(events, max_speed, interval)


def _residual_lag1(fixes, smoothed):
    """Lag-1 autocorrelation of fix-minus-smoothed residuals, both axes pooled."""
    if not smoothed:
        return None
    lat0 = next((f["lat"] for f in fixes), None)
    if lat0 is None:
        return None
    k = math.radians(1.0) * reference.EARTH_RADIUS_M
    res = []
    for f, pos in zip(fixes, smoothed["positions"]):
        if pos is None:
            res.append(None)
            continue
        res.append(((f["lng"] - pos[1]) * k * math.cos(math.radians(lat0)), (f["lat"] - pos[0]) * k))
    num = den = 0.0
    for a, b in zip(res, res[1:]):
        if a is None or b is None:
            continue
        num += a[0] * b[0] + a[1] * b[1]
    for a in res:
        if a is not None:
            den += a[0] * a[0] + a[1] * a[1]
    return num / den if den > 0 else None


def nees_hook(manifest, fixes, est):
    """Mean NEES against a per-fix true state. No corpus entry carries truth
    yet: return None. A synthetic generator that writes truth beside its
    track computes it here."""
    return None


def replay(m):
    path = os.path.join(m["_dir"], m["track_file"])
    if not os.path.isfile(path):
        raise CorpusError("%s: track file %s not found" % (m["id"], m["track_file"]))
    fixes, device = READERS[m["format"]](path)
    fixes.sort(key=lambda f: f["t"])
    if len(fixes) < 2:
        raise CorpusError("%s: %d timestamped fixes; need at least 2" % (m["id"], len(fixes)))
    t0 = fixes[0]["t"]
    for f in fixes:
        f["t"] -= t0
    max_speed = MAX_SPEED_MPS.get(m.get("activity_type"), 10.0)
    interval = m.get("expected_interval_s") or _median_interval(fixes)
    est, mean_nis = _forward(fixes, max_speed, interval)
    sm = _smoothed(fixes, max_speed, interval)
    saved = sm["distance_m"] if sm else est.distance_m
    known = float(m["known_distance_m"])
    err = (saved - known) / known * 100.0
    return {
        "id": m["id"],
        "synthetic": bool(m["synthetic"]),
        "course_type": m["course_type"],
        "platform": m["platform"],
        "fixes": len(fixes),
        "interval_s": round(interval, 3),
        "known_m": known,
        "forward_m": round(est.distance_m, 2),
        "saved_m": round(saved, 2),
        "saved_is_smoothed": sm is not None,
        "hop_m": round(sum(_haversine(a, b) for a, b in zip(fixes, fixes[1:])), 2),
        "device_m": None if device is None else round(device, 2),
        "error_pct": round(err, 3),
        "forward_error_pct": round((est.distance_m - known) / known * 100.0, 3),
        "budget_pct": float(m["error_budget_pct"]),
        "pass": abs(err) <= float(m["error_budget_pct"]),
        "mean_nis": None if mean_nis is None else round(mean_nis, 3),
        "lag1_c": None if sm is None else _round(_residual_lag1(fixes, sm)),
        "mean_nees": nees_hook(m, fixes, est),
        "rejected": getattr(est, "rejected_fixes", None),
    }


def _round(v, n=3):
    return None if v is None else round(v, n)


def _fmt(v, spec):
    return "-" if v is None else format(v, spec)


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    here = os.path.dirname(os.path.abspath(__file__))
    corpus = args[0] if args else os.path.join(here, "..", "..", "fixtures", "gps_corpus")
    try:
        names = sorted(n for n in os.listdir(corpus) if n.endswith(".manifest.json"))
        if not names:
            raise CorpusError("no *.manifest.json in %s" % corpus)
        results = [replay(load_manifest(os.path.join(corpus, n))) for n in names]
    except (CorpusError, OSError, ValueError, ET.ParseError) as e:
        print("gps corpus: %s" % e, file=sys.stderr)
        return 2
    if as_json:
        print(json.dumps({"spec": getattr(reference, "SPEC_VERSION", None), "entries": results}, indent=2))
    else:
        print("reference spec %s, %d entr%s" % (getattr(reference, "SPEC_VERSION", "?"), len(results),
                                               "y" if len(results) == 1 else "ies"))
        print("%-34s %-6s %8s %9s %9s %9s %9s %8s %7s %6s %6s %5s  %s" % (
            "id", "course", "known", "saved", "forward", "hop", "device", "err%", "budget",
            "NIS", "C", "rej", "verdict"))
        for r in results:
            print("%-34s %-6s %8.1f %9.1f %9.1f %9.1f %9s %+8.2f %7.1f %6s %6s %5s  %s" % (
                r["id"][:34], r["course_type"], r["known_m"], r["saved_m"], r["forward_m"], r["hop_m"],
                _fmt(r["device_m"], ".1f"), r["error_pct"], r["budget_pct"],
                _fmt(r["mean_nis"], ".2f"), _fmt(r["lag1_c"], ".2f"), _fmt(r["rejected"], "d"),
                ("ok" if r["pass"] else "OUTSIDE BUDGET") + (" (synthetic)" if r["synthetic"] else "")))
    failed = [r for r in results if not r["pass"]]
    for r in failed:
        print("gps corpus: %s saved %.1f m against a known %.1f m: %+.2f%%, budget +/-%.1f%%"
              % (r["id"], r["saved_m"], r["known_m"], r["error_pct"], r["budget_pct"]), file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
