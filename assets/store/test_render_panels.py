"""Tests for the store panel renderer (render_panels.py, store_numbers.py).

  python3 -m unittest discover -s assets/store -p 'test_*.py' -v

The fixture captures are solid-colour PNGs written at the sizes
test_fixtures/bounds.json records (its `size` key is for this test only), so
nothing binary is committed. The end-to-end render runs only where Inkscape
is installed; everything else is pure layout and data checking.
"""
from __future__ import annotations

import copy
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import render_panels as rp  # noqa: E402
from store_numbers import DataError, Numbers, resolve_caption, store_rule_problems  # noqa: E402

FIXTURES = HERE / "test_fixtures"


def write_png(path: Path, w: int, h: int, rgb=(18, 17, 23)):
    row = b"\x00" + bytes(rgb) * w
    raw = zlib.compress(row * h, 9)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", raw) + chunk(b"IEND", b""))


def numbers_raw() -> dict:
    return json.loads((FIXTURES / "numbers.json").read_text())


class CaptureDir:
    """A temporary capture directory: fixture bounds + numbers + PNGs."""

    def __init__(self, numbers=None, bounds=None):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)
        bounds = bounds or json.loads((FIXTURES / "bounds.json").read_text())
        for entry in bounds["captures"].values():
            write_png(self.path / entry["file"], *entry["size"])
        (self.path / "bounds.json").write_text(json.dumps(bounds))
        (self.path / "numbers.json").write_text(json.dumps(numbers or numbers_raw()))

    def __enter__(self):
        return self.path

    def __exit__(self, *exc):
        self.tmp.cleanup()


class NumbersTest(unittest.TestCase):
    def test_fixture_supports_every_claim(self):
        n = Numbers(numbers_raw())
        claims = {c for p in rp.load_config()["panels"] + rp.load_config()["alternates"] for c in p.get("claims", [])}
        for claim in claims | set(rp.load_config()["claims"]):
            self.assertIsNone(n.check(claim), claim)

    def test_placeholders(self):
        v = Numbers(numbers_raw()).placeholders()
        self.assertEqual((v["slowest.km"], v["slowest.raw"], v["slowest.gap"]), ("6", "5:55", "5:08"))
        self.assertEqual((v["plan.goal_hm"], v["predictor.half_hm"], v["plan.weeks"]), ("1:45", "1:45", "12"))

    def test_slowest_index_must_match_splits(self):
        raw = numbers_raw()
        raw["run"]["slowest_km"] = 5
        with self.assertRaisesRegex(DataError, "km 6 has the slowest"):
            Numbers(raw)

    def test_slowest_must_be_uphill(self):
        raw = numbers_raw()
        raw["run"]["splits"][5]["elev_delta_m"] = -2
        self.assertIn("net climb", Numbers(raw).check("slowest_km_uphill"))

    def test_gap_under_30_fails(self):
        raw = numbers_raw()
        raw["run"]["splits"][5]["raw"] = "5:37"  # 29 s over 5:08, still the slowest
        self.assertIn("30 s/km", Numbers(raw).check("slowest_gap_at_least_30"))

    def test_predicted_half_must_read_as_goal(self):
        raw = numbers_raw()
        raw["predictor"]["rungs"]["half"]["time"] = "1:45:30"  # rounds to 1:46
        self.assertIn("1:45:00 to 1:45:29", Numbers(raw).check("predicted_half_is_goal"))
        raw["predictor"]["rungs"]["half"]["time"] = "1:44:59"  # truncates to 1:44
        self.assertIsNotNone(Numbers(raw).check("predicted_half_is_goal"))

    def test_vdot_must_follow_goal(self):
        raw = numbers_raw()
        raw["plan"]["vdot"] = "45.0"
        self.assertIn("42.6", Numbers(raw).check("vdot_matches_goal"))

    def test_pacing_and_tier(self):
        raw = numbers_raw()
        raw["run"]["pacing"]["grade_adjusted"]["verdict"] = "positive"
        raw["tier"] = "pro"
        n = Numbers(raw)
        self.assertIsNotNone(n.check("raw_positive_gap_even"))
        self.assertIsNotNone(n.check("free_tier"))

    def test_alt_needs_gap_near_median(self):
        raw = numbers_raw()
        raw["run"]["splits"][5]["gap"] = "5:00"
        self.assertIsNotNone(Numbers(raw).check("slowest_gap_near_median"))


class CaptionTest(unittest.TestCase):
    values = Numbers(numbers_raw()).placeholders()

    def test_resolves_with_accent(self):
        out = resolve_caption("x", {"kicker": "Your slowest km", "headline": ["{slowest.raw} up the hill."],
                                    "accent": ["{slowest.raw}"]}, ["slowest"], self.values)
        self.assertEqual(out["headline"], ["5:55 up the hill."])
        self.assertEqual(out["accent"], ["5:55"])

    def test_typed_number_fails(self):
        with self.assertRaisesRegex(DataError, "types a number"):
            resolve_caption("x", {"headline": ["5:52 up the hill."]}, ["slowest"], self.values)

    def test_number_from_another_screen_fails(self):
        with self.assertRaisesRegex(DataError, "not on this panel's screen"):
            resolve_caption("x", {"headline": ["a {plan.goal_hm} half."]}, ["predictor"], self.values)

    def test_subline_is_optional(self):
        out = resolve_caption("x", {"headline": ["Splits and zones."]}, [], self.values)
        self.assertNotIn("subline", out)

    def test_store_rules(self):
        for bad in ("Free splits", "Best app", "Try it now", "Strava sync", "10 miles", "Unlock zones",
                    "The REAL pace"):
            self.assertTrue(store_rule_problems(bad), bad)
        for good in ("Splits and zones.", "Nothing locked.", "Your slowest km", "wasn’t slow.",
                     "A coach that reads your plan"):
            self.assertEqual(store_rule_problems(good), [], good)

    def test_every_shipped_caption_resolves(self):
        config = rp.load_config()
        for locale_file in (HERE / "captions").glob("*.json"):
            captions = json.loads(locale_file.read_text())
            for target, _, panels in rp.panel_sets(config, list(config["targets"])):
                _, _, problems = rp.prepare(config, captions, Numbers(numbers_raw()), target, panels)
                self.assertEqual(problems, [], locale_file.name)


class LayoutTest(unittest.TestCase):
    def compose_all(self, numbers=None, bounds=None, target="play-phone"):
        config = rp.load_config()
        captions = json.loads((HERE / "captions" / "en.json").read_text())
        with CaptureDir(numbers, bounds) as d:
            captures, n = rp.load_capture_dir(d)
            out = {}
            for tgt, name, panels in rp.panel_sets(config, [target]):
                resolved, values, problems = rp.prepare(config, captions, n, tgt, panels)
                self.assertEqual(problems, [])
                for panel in panels:
                    out[(name, panel["id"])] = rp.compose(panel, tgt, config["targets"][tgt],
                                                          resolved[panel["id"]], captures, n, values)
            return out

    def test_every_panel_composes_at_both_sizes(self):
        for target in ("play-phone", "appstore-6.9"):
            out = self.compose_all(target=target)
            self.assertEqual(len([k for k in out if k[0] == target]), 6)
        self.assertIn(("play-phone-variant-b", "slowest-km-alt"), self.compose_all())

    def test_layout_follows_the_spec(self):
        out = self.compose_all()
        svg, report = out[("play-phone", "slowest-km")]
        self.assertEqual(report["headline_px"], 112)
        self.assertEqual(report["card"][:3], [60, 470, 960])
        self.assertGreaterEqual(min(report["contrast"].values()), 4.5)
        self.assertIn('fill="#EC8B7A">5:55</tspan>', svg)
        # The callout replaces the captured row and the other rows are dimmed:
        # the fixture's 8 rows exceed the 7-row window, which keeps km 3-8
        # around the slowest (km 6), so 5 rows are dimmed.
        self.assertIn(">Grade-adj.</text>", svg)
        self.assertEqual(svg.count('fill-opacity="0.55"'), 5)
        _, coach = out[("play-phone", "coach")]
        # Three lines move the card's top bound one step; the coach centres
        # its card in the room below, so it sits at or under that bound.
        self.assertGreaterEqual(coach["card"][1], 590)

    def test_appstore_scale(self):
        _, report = self.compose_all(target="appstore-6.9")[("appstore-6.9", "slowest-km")]
        self.assertEqual(report["headline_px"], 137)
        self.assertEqual(report["card"][:2], [73, 574])

    def test_split_window_drops_rows_far_from_the_slowest(self):
        bounds = json.loads((FIXTURES / "bounds.json").read_text())
        sections = bounds["captures"]["run-splits"]["sections"]
        step = sections["split-row-2"][1] - sections["split-row-1"][1]
        hint = sections.pop("splits-hint")
        for km in range(9, 13):  # twelve rows: more than the window's nine
            sections[f"split-row-{km}"] = [0, sections["split-row-8"][1] + (km - 8) * step, 960, step]
        hint[1] = sections["split-row-12"][1] + step
        sections["splits-hint"] = hint
        bounds["captures"]["run-splits"]["size"][1] = hint[1] + hint[3] + 200
        config = rp.load_config()
        with CaptureDir(bounds=bounds) as d:
            captures, n = rp.load_capture_dir(d)
            panel = config["panels"][0]
            pieces = rp.build_stack(panel, "play-phone", captures, n.placeholders(), 960, 1)
        images = [p for p in pieces if isinstance(p, rp.ImagePiece)]
        kept = sum(p.y1 - p.y0 for p in images)
        # header + rows 2-5 and 7-8 (the window around km 6) + hint, no rows 1 or 9-12
        self.assertLess(kept, (hint[1] + hint[3]) - sections["gap-header"][1] - 5 * step)

    def test_explicit_rect_fallback(self):
        bounds = json.loads((FIXTURES / "bounds.json").read_text())
        bounds["captures"]["plan"]["sections"] = {}
        config = copy.deepcopy(rp.load_config())
        plan = next(p for p in config["panels"] if p["id"] == "plan")
        with CaptureDir(bounds=bounds) as d:
            captures, n = rp.load_capture_dir(d)
            with self.assertRaisesRegex(rp.RenderError, "no fallback rect"):
                rp.build_stack(plan, "play-phone", captures, n.placeholders(), 960, 1)
            plan["crops"][0]["rect"] = [0, 290, 1080, 1282]
            pieces = rp.build_stack(plan, "play-phone", captures, n.placeholders(), 960, 1)
        self.assertEqual(len(pieces), 1)
        self.assertAlmostEqual(pieces[0].height, 1282 * 960 / 1080)

    def test_wrong_theme_or_width_fails(self):
        bounds = json.loads((FIXTURES / "bounds.json").read_text())
        bounds["captures"]["run-splits"]["theme"] = "light"
        with self.assertRaisesRegex(rp.RenderError, "is light, the panel needs dark"):
            self.compose_all(bounds=bounds)
        bounds = json.loads((FIXTURES / "bounds.json").read_text())
        bounds["captures"]["run-splits"]["dpr"] = 2.625
        with self.assertRaisesRegex(rp.RenderError, "366 dp wide"):
            self.compose_all(bounds=bounds)

    def test_forbidden_widget_inside_a_crop_fails(self):
        bounds = json.loads((FIXTURES / "bounds.json").read_text())
        coach = bounds["captures"]["coach"]
        ctx, last = coach["sections"]["coach-context"], coach["sections"]["coach-last-exchange"]
        # Below the chips and above the thread, as the app draws it: no crop
        # reaches it, so the panel renders.
        coach["forbidden"] = {"coach-limit-banner": [0, ctx[1] + ctx[3], 1080, 40]}
        self.compose_all(bounds=bounds)
        # Inside the last exchange: refused.
        coach["forbidden"] = {"coach-limit-banner": [0, last[1] + 100, 1080, 40]}
        with self.assertRaisesRegex(rp.RenderError, "shows coach-limit-banner"):
            self.compose_all(bounds=bounds)

    def test_pad_stops_at_a_forbidden_widget(self):
        bounds = json.loads((FIXTURES / "bounds.json").read_text())
        card = bounds["captures"]["progress"]["sections"]["predictor-card"]
        bounds["captures"]["progress"]["forbidden"] = {"banner": [0, card[1] + card[3] + 6, 960, 30]}
        config = rp.load_config()
        panel = next(p for p in config["panels"] if p["id"] == "predictor")
        with CaptureDir(bounds=bounds) as d:
            captures, _ = rp.load_capture_dir(d)
            r = rp._crop_rect(panel["crops"][0], captures["progress"], "play-phone", 3.0)
        self.assertEqual(r[3], card[1] + card[3] + 6)

    def test_too_long_headline_fails(self):
        caption = {"headline": ["A coach that reads your plan and runs."], "accent": []}
        with self.assertRaisesRegex(rp.RenderError, "rewrite the line"):
            rp.headline_svg(1080, 1920, "dark", caption, {"id": "coach"})

    def test_ground_sampler_matches_the_spec(self):
        self.assertEqual(rp.ground_colour("light", 1080, 1920, 0, 0), (1.0, 1.0, 1.0))
        r, g, b = rp.ground_colour("dark", 1080, 1920, 0, 1920)
        self.assertAlmostEqual(r * 255, 0x12, delta=1)


class TargetsTest(unittest.TestCase):
    def test_missing_ios_captures_fail_without_the_flag(self):
        config = rp.load_config()
        given = {"play-phone": Path("/x")}
        with self.assertRaisesRegex(rp.RenderError, "no captures for appstore-6.9"):
            rp.resolve_dirs(config, given, list(config["targets"]), False)
        dirs = rp.resolve_dirs(config, given, list(config["targets"]), True)
        self.assertEqual(dirs["appstore-6.9"], Path("/x"))


@unittest.skipUnless(shutil.which("inkscape"), "needs Inkscape")
class RenderTest(unittest.TestCase):
    def test_renders_every_panel_as_store_png(self):
        with CaptureDir() as d, tempfile.TemporaryDirectory() as out:
            env = dict(os.environ)
            result = subprocess.run(
                ["bash", str(HERE / "gen-store-screenshots.sh"), "--captures", f"play-phone={d}",
                 "--appstore-from-android", "--out", out], capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            files = sorted(p.relative_to(out).as_posix() for p in Path(out).rglob("*.png"))
            self.assertEqual(len(files), 24)
            self.assertIn("en/appstore-6.3/01-slowest-km.png", files)
            self.assertIn("en/play-phone-variant-b/01-slowest-km-alt.png", files)
            self.assertIn("::warning::appstore-6.9", result.stderr)


if __name__ == "__main__":
    unittest.main()
