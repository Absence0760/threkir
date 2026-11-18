"""The numbers a panel shows, and the checks that keep its headline honest.

The capture suite writes `numbers.json` beside its captures, from the same
code the screens draw with (README.md, "numbers.json"). Captions never carry a
typed number: they name a placeholder such as `{slowest.raw}`, which resolves
from that file here. Each panel then declares the claims its headline makes
(`claims` in panels.json), and a claim the demo data does not bear out fails
the render rather than shipping a panel whose words disagree with its screen.
"""
from __future__ import annotations

import math
import re
import statistics

SCHEMA = 1
HALF_MARATHON_M = 21097.5
PLACEHOLDER = re.compile(r"\{([a-z0-9_]+(?:\.[a-z0-9_]+)+)\}")


class DataError(ValueError):
    """numbers.json is malformed, or a claim it should support does not hold."""


def clock_seconds(text: str) -> int:
    """'5:52' -> 352, '1:45:12' -> 6312. Accepts a trailing '/km'."""
    body = text.strip().removesuffix("/km").strip()
    parts = body.split(":")
    if not 2 <= len(parts) <= 3 or not all(p.isdigit() for p in parts):
        raise DataError(f"{text!r} is not a m:ss or h:mm:ss time")
    total = 0
    for p in parts:
        total = total * 60 + int(p)
    return total


def hours_minutes(seconds: int) -> str:
    """h:mm, truncated: what a headline shows for a race time."""
    return f"{seconds // 3600}:{seconds % 3600 // 60:02d}"


def vdot_from_race(distance_m: float, seconds: int) -> float:
    """training.dart vdotFromRace (Daniels and Gilbert), transcribed."""
    minutes = seconds / 60.0
    v = distance_m / minutes
    vo2 = -4.6 + 0.182258 * v + 0.000104 * v * v
    pct = 0.8 + 0.1894393 * math.exp(-0.012778 * minutes) + 0.2989558 * math.exp(-0.1932605 * minutes)
    return vo2 / pct


def _need(obj: dict, key: str, where: str, kind=None):
    if not isinstance(obj, dict) or key not in obj:
        raise DataError(f"numbers.json: {where} has no {key!r}")
    value = obj[key]
    if kind is not None and not isinstance(value, kind):
        raise DataError(f"numbers.json: {where}.{key} should be {kind.__name__ if isinstance(kind, type) else kind}")
    return value


class Numbers:
    """A validated numbers.json, plus the placeholders captions resolve from."""

    def __init__(self, raw: dict, source: str = "numbers.json"):
        self.source = source
        if raw.get("schema") != SCHEMA:
            raise DataError(f"{source}: schema should be {SCHEMA}, is {raw.get('schema')!r}")
        self.raw = raw
        self.tier = _need(raw, "tier", "root", str)
        self.labels = _need(raw, "labels", "root", dict)
        run = _need(raw, "run", "root", dict)
        self.splits = _need(run, "splits", "run", list)
        if not self.splits:
            raise DataError(f"{source}: run.splits is empty")
        for i, s in enumerate(self.splits):
            where = f"run.splits[{i}]"
            if _need(s, "km", where, int) != i + 1:
                raise DataError(f"{source}: {where}.km should be {i + 1}")
            s["raw_s"] = clock_seconds(_need(s, "raw", where, str))
            s["gap_s"] = clock_seconds(_need(s, "gap", where, str))
            _need(s, "elev_delta_m", where, (int, float))
        raw_secs = [s["raw_s"] for s in self.splits]
        slowest = raw_secs.index(max(raw_secs)) + 1
        declared = _need(run, "slowest_km", "run", int)
        if declared != slowest:
            raise DataError(f"{source}: run.slowest_km is {declared}, but km {slowest} has the slowest raw split")
        if raw_secs.count(max(raw_secs)) > 1:
            raise DataError(f"{source}: two splits tie for slowest, so the app highlights more than one row")
        self.slowest = self.splits[slowest - 1]
        self.pacing = _need(run, "pacing", "run", dict)
        for half in ("raw", "grade_adjusted"):
            p = _need(self.pacing, half, "run.pacing", dict)
            _need(p, "verdict", f"run.pacing.{half}", str)
            _need(p, "delta_s", f"run.pacing.{half}", (int, float))
        self.zones = _need(run, "zones", "run", list)
        self.hr = _need(run, "hr", "run", dict)
        pred = _need(raw, "predictor", "root", dict)
        self.rungs = _need(pred, "rungs", "predictor", dict)
        for name in ("5k", "10k", "half", "marathon"):
            rung = _need(self.rungs, name, "predictor.rungs", dict)
            for key in ("distance", "time", "pace", "confidence", "confidence_label"):
                _need(rung, key, f"predictor.rungs.{name}", str)
            if rung["confidence"] not in ("high", "moderate", "low"):
                raise DataError(f"{source}: predictor.rungs.{name}.confidence is {rung['confidence']!r}")
            rung["time_s"] = clock_seconds(rung["time"])
        self.plan = _need(raw, "plan", "root", dict)
        _need(self.plan, "weeks", "plan", int)
        _need(self.plan, "goal_distance_m", "plan", (int, float))
        self.plan["goal_s"] = clock_seconds(_need(self.plan, "goal", "plan", str))
        _need(self.plan, "vdot", "plan", str)

    def placeholders(self) -> dict[str, str]:
        half = self.rungs["half"]
        return {
            "slowest.km": str(self.slowest["km"]),
            "slowest.raw": self.slowest["raw"],
            "slowest.gap": self.slowest["gap"],
            "plan.weeks": str(self.plan["weeks"]),
            "plan.goal": self.plan["goal"],
            "plan.goal_hm": hours_minutes(self.plan["goal_s"]),
            "plan.vdot": self.plan["vdot"],
            "predictor.half": half["time"],
            "predictor.half_hm": hours_minutes(half["time_s"]),
        }

    # Each claim returns None when it holds, else the reason it does not.
    def claim_free_tier(self):
        if self.tier != "free":
            return f"the captures are on the {self.tier!r} tier; every panel is captured on 'free' (spec item 2)"

    def claim_slowest_km_uphill(self):
        if self.slowest["elev_delta_m"] <= 0:
            return (f"km {self.slowest['km']} is the slowest, but it gains {self.slowest['elev_delta_m']} m: "
                    "'up the hill' needs a net climb inside that km")

    def claim_slowest_gap_at_least_30(self):
        gap = self.slowest["raw_s"] - self.slowest["gap_s"]
        if gap < 30:
            return (f"the slowest km is {self.slowest['raw']} raw and {self.slowest['gap']} grade-adjusted, "
                    f"{gap} s/km apart; the hook needs 30 s/km or more")

    def claim_slowest_gap_near_median(self):
        median = statistics.median(s["gap_s"] for s in self.splits)
        if abs(self.slowest["gap_s"] - median) > 3:
            return (f"the slowest km's grade-adjusted pace ({self.slowest['gap']}) is more than 3 s/km from the "
                    f"run's median grade-adjusted split ({median:g} s/km), so 'wasn't slow' is not true")

    def claim_raw_positive_gap_even(self):
        raw, ga = self.pacing["raw"], self.pacing["grade_adjusted"]
        if raw["verdict"] != "positive" or ga["verdict"] != "even":
            return (f"pacing reads raw {raw['verdict']!r} and grade-adjusted {ga['verdict']!r}; "
                    "the panel needs 'positive' then 'even'")
        if abs(ga["delta_s"] - raw["delta_s"]) < 2:
            return "the raw and grade-adjusted half deltas are under 2 s/km apart, so the app hides the sentence"

    def claim_zones_all_five(self):
        if len(self.zones) != 5 or any(z.get("pct", 0) <= 0 for z in self.zones):
            return "the run's heart rate does not reach all five zones, so the legend shows empty zones"

    def claim_predicted_half_is_goal(self):
        goal, half = self.plan["goal_s"], self.rungs["half"]["time_s"]
        start = goal - goal % 60
        if not start <= half <= start + 29:
            return (f"the predictor's Half reads {self.rungs['half']['time']}, the plan's goal "
                    f"{self.plan['goal']}; the half must show {hours_minutes(goal)}:00 to "
                    f"{hours_minutes(goal)}:29 so it reads {hours_minutes(goal)} rounded or truncated")

    def claim_plan_is_half(self):
        if abs(self.plan["goal_distance_m"] - HALF_MARATHON_M) > 50:
            return f"the plan's race is {self.plan['goal_distance_m']} m, not a half marathon"

    def claim_vdot_matches_goal(self):
        expected = f"{round(vdot_from_race(self.plan['goal_distance_m'], self.plan['goal_s']), 2):.1f}"
        if self.plan["vdot"] != expected:
            return (f"the VDOT chip reads {self.plan['vdot']}, but the app derives {expected} from the "
                    f"{self.plan['goal']} goal (spec open issue 2)")

    def check(self, claim: str):
        fn = getattr(self, f"claim_{claim}", None)
        if fn is None:
            raise DataError(f"unknown claim {claim!r}")
        return fn()


# --------------------------------------------------------------------- captions

STORE_BANNED = [
    # Play metadata policy and the brief: no ranking or promo words, no CTA.
    r"free", r"best", r"#1", r"top", r"new", r"sale", r"download", r"install", r"try", r"now", r"get",
    r"unlock", r"elevate",
    # No other app or platform.
    r"strava", r"garmin", r"runna", r"nike", r"apple", r"iphone", r"android", r"google", r"play",
    r"wear os", r"health connect", r"healthkit",
    # Metric only.
    r"miles?", r"mi", r"feet", r"ft",
    # A model estimate is never "real" or "true" pace.
    r"real", r"true", r"live", r"instant",
]
CURRENCY = re.compile(r"[$€£¥₹]|\b(?:usd|eur|gbp|price)\b", re.I)
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿]")


def store_rule_problems(text: str) -> list[str]:
    found = []
    for word in STORE_BANNED:
        if re.search(rf"(?<![\w#]){word}(?!\w)", text, re.I):
            found.append(f"uses {word!r}")
    if CURRENCY.search(text):
        found.append("names a price or currency")
    if EMOJI.search(text):
        found.append("has an emoji")
    for w in re.findall(r"[A-Za-z]{2,}", text):
        if w.isupper() and w != "km":
            found.append(f"has the all-caps word {w!r}")
    return found


def resolve_caption(panel_id: str, caption: dict, allowed_roots: list[str], values: dict[str, str]) -> dict:
    """Resolve a caption's placeholders. Fails on a typed digit, a placeholder
    this panel's screen does not show, or an accent that is not in a line."""
    if not isinstance(caption.get("headline"), list) or not caption["headline"]:
        raise DataError(f"{panel_id}: the caption has no headline lines")
    problems = []

    def one(text: str, field: str) -> str:
        if re.search(r"\d", PLACEHOLDER.sub("", text)):
            problems.append(f"{panel_id}.{field} types a number ({text!r}); use a numbers.json placeholder")

        def sub(m):
            key = m.group(1)
            if key.split(".")[0] not in allowed_roots:
                problems.append(f"{panel_id}.{field} shows {{{key}}}, which is not on this panel's screen "
                                f"(its numbers: {', '.join(allowed_roots) or 'none'})")
                return m.group(0)
            if key not in values:
                problems.append(f"{panel_id}.{field}: unknown placeholder {{{key}}}")
                return m.group(0)
            return values[key]
        return PLACEHOLDER.sub(sub, text)

    out = {"headline": [one(l, f"headline[{i}]") for i, l in enumerate(caption["headline"])]}
    if caption.get("kicker"):
        out["kicker"] = one(caption["kicker"], "kicker")
    out["accent"] = [one(a, "accent") for a in caption.get("accent", [])]
    if caption.get("subline"):
        out["subline"] = one(caption["subline"], "subline")
    for a in out["accent"]:
        if not any(a in line for line in out["headline"]):
            problems.append(f"{panel_id}: accent {a!r} is not in the headline")
    for field in ("headline", "kicker", "subline"):
        texts = out[field] if field == "headline" else [out.get(field)]
        for t in filter(None, texts):
            for p in store_rule_problems(t):
                problems.append(f"{panel_id}.{field} {p}: {t!r}")
    if problems:
        raise DataError("\n".join(problems))
    return out
