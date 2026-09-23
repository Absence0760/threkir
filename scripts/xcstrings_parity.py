#!/usr/bin/env python3
"""String Catalog parity for an Apple target. Runs WITHOUT Xcode -- pure
JSON/text parse under a bare python3 -- so CI on Linux (or a quick local sanity
check) can catch a missing or empty translation before a Mac ever builds the
app.

Shared by both Apple tiers, each through its own thin wrapper that names its
files:

  apps/watch_ios/scripts/check_xcstrings_parity.sh   (the wrist: UI + consent)
  apps/mobile_ios/scripts/check_xcstrings_parity.sh  (the phone: consent only;
                                                      its UI strings are ARB)

One engine rather than two copies because the claims are the same claims, and
the second copy is where the next claim would be added to one tier and not the
other. The consent catalog is the first thing each app ever says to a runner.
Until 2026-09-18 neither had one: the wrist asked for HealthKit and location in
English in all seven locales (#951), and the phone did the same for eleven
prompts (#964).

Seven claims, in order:

  1. The shipped locale set is DERIVED from the catalogs, not restated here.
     A hand-written list is a second place a locale has to be added, and the
     one the loop below reads: a locale added to the entries and missed in the
     list would be skipped by the check that exists to see it (decisions
     § 748 / § 755 / § 761). The set is every locale ANY entry in ANY catalog
     declares; an entry short of it is what fails -- which is also how one
     catalog falling behind another is caught, rather than each being graded
     against its own smaller set.
  2. Every entry carries a non-empty translation for every locale in that set.
     ja is exempt from the plural "one" category (Japanese has no
     singular/plural distinction; a catalog declares only "other" for it).
  3. The source language may be implicit in a UI catalog, where the key IS the
     English string, and may NOT be in the consent catalog, where the key is a
     plist key name (`NSHealthShareUsageDescription`). An implicit source there
     would ship the key itself as the English prompt text.
  4. Info.plist's CFBundleLocalizations and the Xcode project's knownRegions
     declare exactly that set. A translated string the bundle does not declare
     is never loaded at runtime: the app silently shows English and nothing
     fails, which is precisely how a half-declared locale ships.
  5. Every `NS*UsageDescription` key Info.plist declares has an entry in the
     consent catalog, and every entry names a key Info.plist actually declares.
     A new capability adds a purpose string to the plist and nothing anywhere
     asks for its six translations -- the prompt just reads English forever.
     The other direction is an entry for a key that no longer exists: six
     translations of a prompt nobody sees.
  6. Each entry's source-language value is identical to the value in
     Info.plist (after XML entity decoding). The plist value is the fallback
     the OS uses when no localization matches, so a drifting pair means an
     English-speaking runner and the catalog disagree about what the app
     promised.
  7. Every catalog is a member of the named target's Resources build phase,
     through a file reference whose group chain resolves to the catalog's
     path. A catalog on disk that the target does not copy is never in the
     bundle, so every claim above would pass over translations no device can
     load -- the same silent English, one level further out.
"""

import argparse
import html
import json
import os
import re
import sys
import pathlib

# Locales with no singular form -- plural "one" is not required.
NO_SINGULAR = {"ja"}

parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
parser.add_argument("--root", required=True, help="the Xcode project's SRCROOT")
parser.add_argument("--plist", required=True, help="Info.plist, relative to --root")
parser.add_argument("--pbxproj", required=True, help="project.pbxproj, relative to --root")
parser.add_argument("--target", required=True, help="the PBXNativeTarget that must bundle the catalogs")
parser.add_argument("--plist-catalog", required=True, help="InfoPlist.xcstrings, relative to --root")
parser.add_argument(
    "--ui-catalog",
    action="append",
    default=[],
    help="a UI catalog whose keys are their own source strings (repeatable)",
)
parser.add_argument("--device", required=True, help="noun for the failure message: wrist, iPhone")
args = parser.parse_args()

root = pathlib.Path(args.root)
plist = root / args.plist
pbxproj = root / args.pbxproj
plist_catalog_rel = args.plist_catalog
catalog_rels = [*args.ui_catalog, plist_catalog_rel]

errors = []
catalogs = {}
for rel in catalog_rels:
    path = root / rel
    cat = json.loads(path.read_text(encoding="utf-8"))
    strings = cat.get("strings", {})
    if not strings:
        print(f"FAIL: no string entries parsed from {path}", file=sys.stderr)
        sys.exit(1)
    # An explicit sourceLanguage is required where the source may not be
    # implicit; a UI catalog without one is Xcode's own default, en.
    source = cat.get("sourceLanguage")
    if source is None:
        if rel == plist_catalog_rel:
            print(f"FAIL: {path} declares no sourceLanguage", file=sys.stderr)
            sys.exit(1)
        source = "en"
    catalogs[rel] = (os.path.basename(rel), source, strings)

# (1) Derive the set across EVERY catalog. Each source language is always
# shipped even when its entries leave it implicit, so it is in by construction.
locales = set()
for _, source, strings in catalogs.values():
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
for rel, (name, source, strings) in catalogs.items():
    implicit_source_ok = rel != plist_catalog_rel
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
plist_usage = {
    k: html.unescape(v)
    for k, v in re.findall(
        r"<key>(NS\w*UsageDescription)</key>\s*<string>(.*?)</string>",
        plist_text,
        re.S,
    )
}
plist_name, plist_source, plist_strings = catalogs[plist_catalog_rel]
for key in sorted(set(plist_usage) - set(plist_strings)):
    errors.append(
        f"{plist_name}: Info.plist declares {key} with no catalog entry — "
        f"that consent prompt renders English on every {args.device}"
    )
for key in sorted(set(plist_strings) - set(plist_usage)):
    errors.append(
        f"{plist_name} [{key}]: no such NS*UsageDescription key in Info.plist"
    )
for key in sorted(set(plist_usage) & set(plist_strings)):
    unit = plist_strings[key].get("localizations", {}).get(plist_source, {}).get("stringUnit", {})
    if unit.get("value") != plist_usage[key]:
        errors.append(
            f"{plist_name} [{key}]: {plist_source} value differs from the "
            "Info.plist string it falls back to"
        )

# (7) Each catalog is bundled by the target. Objects are read by id out of the
# pbxproj's two shapes: a multi-line `ID /* c */ = {\n ... \n\t\t};` block and
# a one-line `ID /* c */ = {isa = ...; };`.
def pbx_object(obj_id):
    m = re.search(
        rf"^\t\t{obj_id} /\*[^\n]*?\*/ = \{{\n(.*?)^\t\t\}};$|^\t\t{obj_id} /\*[^\n]*?\*/ = \{{([^\n]*)\}};$",
        pbx_text,
        re.S | re.M,
    )
    if m is None:
        return None
    return m.group(1) if m.group(1) is not None else m.group(2)


def list_ids(body, field):
    m = re.search(rf"\b{field} = \((.*?)\);", body or "", re.S)
    return re.findall(r"\b([0-9A-F]{24})\b", m.group(1)) if m else []


def field(body, name):
    m = re.search(rf"\b{name} = (\"[^\"]*\"|[^;]+);", body or "")
    return m.group(1).strip('"') if m else None


group_parent = {}
for gm in re.finditer(r"^\t\t([0-9A-F]{24}) /\*[^\n]*?\*/ = \{\n\t\t\tisa = PBXGroup;", pbx_text, re.M):
    for child in list_ids(pbx_object(gm.group(1)), "children"):
        group_parent[child] = gm.group(1)


def ref_path(ref_id):
    """The file reference's path relative to SRCROOT, walking its group chain."""
    parts = []
    node = ref_id
    while node is not None:
        body = pbx_object(node)
        tree = field(body, "sourceTree")
        path = field(body, "path")
        if path:
            parts.append(path)
        if tree not in (None, "<group>"):
            # SOURCE_ROOT anchors at SRCROOT; anything else (an absolute or
            # SDK-relative ref) is not a file in this tree.
            if tree != "SOURCE_ROOT":
                return None
            break
        node = group_parent.get(node)
    return os.path.normpath(os.path.join(*reversed(parts))) if parts else None


target = re.search(
    rf"^\t\t([0-9A-F]{{24}}) /\* {re.escape(args.target)} \*/ = \{{\n\t\t\tisa = PBXNativeTarget;",
    pbx_text,
    re.M,
)
if target is None:
    errors.append(f"project.pbxproj has no native target named {args.target}")
else:
    bundled = set()
    for phase in list_ids(pbx_object(target.group(1)), "buildPhases"):
        body = pbx_object(phase)
        if field(body, "isa") != "PBXResourcesBuildPhase":
            continue
        for build_file in list_ids(body, "files"):
            ref = field(pbx_object(build_file), "fileRef")
            ref = ref.split()[0] if ref else None
            if ref:
                p = ref_path(ref)
                if p:
                    bundled.add(p)
    for rel in catalog_rels:
        if os.path.normpath(rel) not in bundled:
            errors.append(
                f"{os.path.basename(rel)}: not in the {args.target} target's Resources "
                f"phase as {rel} — the catalog never reaches the bundle, so every "
                f"{args.device} reads the Info.plist English"
            )

count = sum(len(strings) for _, _, strings in catalogs.values())
if errors:
    print(f"FAIL: {len(errors)} problem(s) across {count} string(s):", file=sys.stderr)
    for e in errors:
        print("  - " + e, file=sys.stderr)
    sys.exit(1)

print(
    f"OK: {count} string(s) across {len(catalogs)} catalog(s) each translated for "
    f"{', '.join(LOCALES)}; {len(plist_usage)} NS*UsageDescription key(s) localized; "
    f"Info.plist and knownRegions declare the same set; every catalog is bundled "
    f"by {args.target}"
)
