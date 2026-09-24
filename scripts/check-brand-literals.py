#!/usr/bin/env python3
"""Fail if a mobile app hardcodes the brand instead of reading it.

The generator writes `Brand.generated.swift` and each flavour's `strings.xml`,
but writing them is not using them: a hardcoded palette still compiles and a
hardcoded name still renders, so the build stays green and the wrong brand
ships. That is exactly what happened — the iOS app carried the generated file
without one reference to it, and every screen said Fishers.

Run from the repo root:  python3 scripts/check-brand-literals.py
"""

import re
import sys
from pathlib import Path

BRAND = "Fishers"


def is_identifier(text):
    """A symbol the build resolves, not a sentence somebody reads.

    Type names, style names, asset names and launch arguments — `FishersTheme`,
    `Theme.Fishers`, `.FishersApp`, `-FishersSignOutOnLaunch`. None of them has
    a space in it, which is the whole rule. The one exception is the brand word
    standing alone: `Text("Fishers")` has no space either, and it is the most
    wrong string in the app.
    """
    return " " not in text.strip() and text.strip() != BRAND

STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')

# Source that ships to a user. Tests drive the Fishers build by name on
# purpose, and the generated files are the brand.
TARGETS = [
    (Path("ios/Fishers"), (".swift",)),
    (Path("android/app/src/main"), (".kt", ".xml")),
]

SKIP = ("Generated", "generated", "build/")


def literals(path):
    """Brand names in shipped strings — not in comments, not identifiers."""
    for n, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith(("///", "//", "*", "<!--")):
            continue
        for m in STRING.finditer(line):
            text = m.group(1)
            if BRAND in text and not is_identifier(text):
                yield n, text


def main():
    found = []
    for root, suffixes in TARGETS:
        if not root.exists():
            print(f"  ?  {root} is not there — did the tree move?", file=sys.stderr)
            continue
        for f in sorted(root.rglob("*")):
            if f.suffix not in suffixes or any(s in str(f) for s in SKIP):
                continue
            found += [(f, n, t) for n, t in literals(f)]

    if not found:
        print("  ok   no brand hardcoded in the iOS or Android app")
        return 0

    print("These say Fishers where they should read the brand:\n")
    for f, n, text in found:
        print(f"  {f}:{n}\n      {text}")
    print(
        f"\n{len(found)} of them. Use Brand.name (Swift) or"
        " R.string.brand_name (Android) — both are written from brands/<id>.yaml,"
        " so they are already right for every brand."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
