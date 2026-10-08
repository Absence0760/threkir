#!/usr/bin/env python3
"""Regenerate every committed Manrope file from the variable master.

The master is Google Fonts' `Manrope[wght].ttf` (SIL OFL 1.1, beside it as
OFL.txt). Flutter cannot drive a variable font's weight axis from
`FontWeight`, so the app gets one static TTF per weight it uses; the web gets
the same weights as WOFF2, subset to the Latin ranges the shipped locales
need (Japanese falls back to the system face on both platforms); Wear OS
gets the TTFs as font resources. watchOS keeps the system face (SF Compact
is drawn for a watch dial).

Requires fontTools and brotli:  python3 -m pip install fonttools brotli
Run from anywhere:              python3 assets/fonts/gen-manrope.py
"""
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
MASTER = HERE / "manrope" / "Manrope[wght].ttf"
FLUTTER_OUT = REPO / "packages" / "ui_kit" / "fonts"
WEB_OUT = REPO / "apps" / "web" / "src" / "lib" / "assets" / "fonts"
# Android resource names must be lowercase with underscores.
WEAR_OUT = REPO / "apps" / "watch_wear" / "android" / "app" / "src" / "main" / "res" / "font"

WEIGHTS = {
    300: "Light",
    400: "Regular",
    500: "Medium",
    600: "SemiBold",
    700: "Bold",
    800: "ExtraBold",
}

# Basic Latin, Latin-1, Latin Extended-A, general punctuation, currency,
# letterlike symbols, arrows: everything de / fr / es / pt-PT / pt-BR and
# English need, plus the typographic marks the copy uses.
WEB_UNICODES = "U+0000-024F,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-21FF,U+2212"


def main() -> None:
    FLUTTER_OUT.mkdir(parents=True, exist_ok=True)
    WEB_OUT.mkdir(parents=True, exist_ok=True)
    WEAR_OUT.mkdir(parents=True, exist_ok=True)
    (FLUTTER_OUT / "OFL.txt").write_bytes((HERE / "manrope" / "OFL.txt").read_bytes())
    (WEB_OUT / "OFL.txt").write_bytes((HERE / "manrope" / "OFL.txt").read_bytes())
    wear_licence = WEAR_OUT.parent.parent / "assets" / "licenses" / "Manrope-OFL.txt"
    wear_licence.parent.mkdir(parents=True, exist_ok=True)
    wear_licence.write_bytes((HERE / "manrope" / "OFL.txt").read_bytes())
    for weight, name in WEIGHTS.items():
        font = instancer.instantiateVariableFont(
            TTFont(MASTER), {"wght": weight}, updateFontNames=True
        )
        ttf = FLUTTER_OUT / f"Manrope-{name}.ttf"
        font.save(ttf)
        font.save(WEAR_OUT / f"manrope_{name.lower()}.ttf")

        options = subset.Options()
        options.flavor = "woff2"
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        sub = subset.Subsetter(options)
        sub.populate(unicodes=subset.parse_unicodes(WEB_UNICODES))
        web = TTFont(ttf)
        sub.subset(web)
        web.flavor = "woff2"
        web.save(WEB_OUT / f"manrope-{weight}.woff2")
        print(f"wrote {ttf.name} and manrope-{weight}.woff2")


if __name__ == "__main__":
    main()
