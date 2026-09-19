#!/usr/bin/env bash
# Parity check for the watchOS String Catalogs. Runs WITHOUT Xcode — pure
# JSON/text parse — so CI on Linux (or a quick local sanity check) can catch a
# missing or empty translation before a Mac ever builds the app.
#
# Two catalogs are held to one bar: `Localizable.xcstrings` (the UI) and
# `InfoPlist.xcstrings` (the consent prompts). The second one is the
# first thing the app ever says to a runner, and until 2026-09-18 it did not
# exist — `Info.plist` carried the four `NS*UsageDescription` strings in
# English and nothing else, so a Lisbon or Tokyo wrist was asked for HealthKit
# and location access in English while the other 59 strings were translated.
#
# Six claims, in order:
#
#   1. The shipped locale set is DERIVED from the catalogs, not restated here.
#      A hand-written list is a second place a locale has to be added, and the
#      one the loop below reads: a seventh locale added to the entries and
#      missed in the list would be skipped by the check that exists to see it.
#      That shape was found six times on the web/wrist side (decisions § 748 /
#      § 755) and once more here (§ 761). The set is every locale ANY entry in
#      EITHER catalog declares; an entry short of it is what fails — which is
#      also how one catalog falling behind the other is caught, rather than
#      each being graded against its own smaller set.
#   2. Every entry carries a non-empty translation for every locale in that
#      set. ja is exempt from the plural "one" category (Japanese has no
#      singular/plural distinction; the catalog only declares "other" for ja
#      plural entries).
#   3. The source language may be implicit in `Localizable.xcstrings`, where
#      the key IS the English string, and may NOT be in `InfoPlist.xcstrings`,
#      where the key is a plist key name (`NSHealthShareUsageDescription`).
#      An implicit source there would ship the key itself as the English
#      prompt text.
#   4. Info.plist's CFBundleLocalizations and the Xcode project's
#      knownRegions declare exactly that set. A translated string the bundle
#      does not declare is never loaded at runtime: the app silently shows
#      English and nothing fails, which is precisely how a half-declared
#      locale ships.
#   5. Every `NS*UsageDescription` key Info.plist declares has an entry in
#      `InfoPlist.xcstrings`, and every entry names a key Info.plist actually
#      declares. A new capability adds a purpose string to the plist and
#      nothing anywhere asks for its six translations — the prompt just reads
#      English forever. The other direction is an entry for a key that no
#      longer exists: six translations of a prompt nobody sees.
#   6. Each entry's source-language value is byte-identical to the value in
#      Info.plist. The plist value is the fallback watchOS uses when no
#      localization matches, so a drifting pair means an English-speaking
#      runner and the catalog disagree about what the app promised.
#
# CI: the `watch-ios-locale-parity` job in .github/workflows/ci.yml.
# Referenced from apps/watch_ios/CLAUDE.md.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$DIR" <<'PY'
import json, re, sys, pathlib

root = pathlib.Path(sys.argv[1])
ui_catalog = root / "WatchApp" / "Localizable.xcstrings"
plist_catalog = root / "WatchApp" / "InfoPlist.xcstrings"
plist = root / "WatchApp" / "Info.plist"
pbxproj = root / "WatchApp.xcodeproj" / "project.pbxproj"

# Locales with no singular form — plural "one" is not required.
NO_SINGULAR = {"ja"}

errors = []
catalogs = {}
for path in (ui_catalog, plist_catalog):
    cat = json.loads(path.read_text(encoding="utf-8"))
    strings = cat.get("strings", {})
    if not strings:
        print(f"FAIL: no string entries parsed from {path}", file=sys.stderr)
        sys.exit(1)
    catalogs[path.name] = (cat.get("sourceLanguage", "en"), strings)

# (1) Derive the set across BOTH catalogs. Each source language is always
# shipped even when its entries leave it implicit, so it is in by construction.
locales = set()
for source, strings in catalogs.values():
    locales.add(source)
    for entry in strings.values():
        locales.update(entry.get("localizations", {}))
LOCALES = sorted(locales)


def unit_ok(unit):
    return bool(unit.get("value", "").strip())


def check_localization(name, key, loc, block):
    # A localization is either a plain stringUnit or a variations/plural block.
    if "stringUnit" in block:
        if not unit_ok(block["stringUnit"]):
            errors.append(f"{name} [{key}] {loc}: empty value")
        return
    variations = block.get("variations", {})
    plural = variations.get("plural")
    if plural is None:
        errors.append(f"{name} [{key}] {loc}: no stringUnit and no plural variations")
        return
    required = ["other"] if loc in NO_SINGULAR else ["one", "other"]
    for cat_name in required:
        cat_block = plural.get(cat_name)
        if cat_block is None or "stringUnit" not in cat_block or not unit_ok(cat_block["stringUnit"]):
            errors.append(f"{name} [{key}] {loc}: missing/empty plural '{cat_name}'")


# (2) + (3) Every entry covers every derived locale. The source language is
# implicit-allowed only where the key is itself the source string.
for name, (source, strings) in catalogs.items():
    implicit_source_ok = name == ui_catalog.name
    for key, entry in strings.items():
        locs = entry.get("localizations", {})
        for loc in LOCALES:
            if loc not in locs:
                if loc == source and implicit_source_ok:
                    continue
                if loc == source:
                    errors.append(
                        f"{name} [{key}] {loc}: no source-language localization — "
                        "the key is a plist key name, not the English text"
                    )
                else:
                    errors.append(f"{name} [{key}] {loc}: missing translation")
                continue
            check_localization(name, key, loc, locs[loc])

# (4) Both declaration sites agree with the derived set. Neither is parsed
# with a real plist/pbxproj reader on purpose: this has to run under a bare
# python3 on a Linux runner with nothing installed.
plist_text = plist.read_text(encoding="utf-8")
block = re.search(
    r"<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>",
    plist_text,
    re.S,
)
if block is None:
    errors.append("Info.plist declares no CFBundleLocalizations array")
else:
    declared = sorted(re.findall(r"<string>([^<]+)</string>", block.group(1)))
    if declared != LOCALES:
        errors.append(
            f"Info.plist CFBundleLocalizations is {declared}, catalogs ship {LOCALES}"
        )

pbx_text = pbxproj.read_text(encoding="utf-8")
block = re.search(r"knownRegions = \((.*?)\);", pbx_text, re.S)
if block is None:
    errors.append("project.pbxproj declares no knownRegions")
else:
    regions = [r.strip().strip('",') for r in block.group(1).split("\n")]
    # `Base` is Xcode's own development-region marker, not a shipped locale.
    regions = sorted(r for r in regions if r and r != "Base")
    if regions != LOCALES:
        errors.append(
            f"project.pbxproj knownRegions is {regions}, catalogs ship {LOCALES}"
        )

# (5) + (6) The plist catalog names exactly the usage-description keys the
# plist declares, and agrees with each on the source string.
plist_usage = dict(
    re.findall(
        r"<key>(NS\w*UsageDescription)</key>\s*<string>(.*?)</string>",
        plist_text,
        re.S,
    )
)
plist_source, plist_strings = catalogs[plist_catalog.name]
for key in sorted(set(plist_usage) - set(plist_strings)):
    errors.append(
        f"{plist_catalog.name}: Info.plist declares {key} with no catalog entry — "
        "that consent prompt renders English on every wrist"
    )
for key in sorted(set(plist_strings) - set(plist_usage)):
    errors.append(
        f"{plist_catalog.name} [{key}]: no such NS*UsageDescription key in Info.plist"
    )
for key in sorted(set(plist_usage) & set(plist_strings)):
    unit = plist_strings[key].get("localizations", {}).get(plist_source, {}).get("stringUnit", {})
    if unit.get("value") != plist_usage[key]:
        errors.append(
            f"{plist_catalog.name} [{key}]: {plist_source} value differs from the "
            "Info.plist string it falls back to"
        )

count = sum(len(strings) for _, strings in catalogs.values())
if errors:
    print(f"FAIL: {len(errors)} problem(s) across {count} string(s):", file=sys.stderr)
    for e in errors:
        print("  - " + e, file=sys.stderr)
    sys.exit(1)

print(
    f"OK: {count} string(s) across {len(catalogs)} catalog(s) each translated for "
    f"{', '.join(LOCALES)}; {len(plist_usage)} NS*UsageDescription key(s) localized; "
    "Info.plist and knownRegions declare the same set"
)
PY
