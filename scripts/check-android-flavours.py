#!/usr/bin/env python3
"""Fail if a Gradle flavour's applicationId disagrees with its brand file.

`brands/<id>.yaml` says what a brand's bundle id is; `android/app/build.gradle.kts`
declares one product flavour per brand with an `applicationId` typed out by
hand — deliberately, so the set of variants does not change with the contents
of a folder. Two places, and nothing kept them honest.

They disagree silently: the flavour builds, Play accepts the bundle, and the
release goes to whichever listing the flavour named. That is one brand's code
published under another brand's name.

Run from the repo root:  python3 scripts/check-android-flavours.py
"""

import json
import re
import subprocess
import sys
from pathlib import Path

GRADLE = Path("android/app/build.gradle.kts")

# create("fishers") { … applicationId = "com.fishers.app" … }
FLAVOUR = re.compile(
    r'create\("(?P<id>[^"]+)"\)\s*\{(?P<body>[^}]*)\}', re.S
)
APP_ID = re.compile(r'applicationId\s*=\s*"(?P<id>[^"]+)"')


def brands():
    """Each brand's id and mobile bundle id, from the brand files themselves."""
    ids = json.loads(
        subprocess.run(
            ["node", "tools/brand/index.mjs", "list", "--json"],
            capture_output=True, text=True, check=True,
        ).stdout
    )
    out = {}
    for brand in ids:
        lines = subprocess.run(
            ["node", "tools/brand/index.mjs", "mobile", brand],
            capture_output=True, text=True, check=True,
        ).stdout.splitlines()
        fields = dict(line.split("=", 1) for line in lines if "=" in line)
        out[brand] = fields["BRAND_APP_ID"]
    return out


def flavours():
    """Each flavour's id and applicationId, from the gradle file."""
    source = GRADLE.read_text()
    block = source[source.index("productFlavors"):]
    found = {}
    for match in FLAVOUR.finditer(block):
        app_id = APP_ID.search(match.group("body"))
        if app_id:
            found[match.group("id")] = app_id.group("id")
    return found


def main():
    if not GRADLE.exists():
        print(f"  ?  {GRADLE} is not there — did the tree move?", file=sys.stderr)
        return 1

    wanted, declared = brands(), flavours()
    problems = []

    for brand, app_id in wanted.items():
        if brand not in declared:
            problems.append(
                f"brands/{brand}.yaml has no flavour in {GRADLE}. "
                f'Add create("{brand}") {{ applicationId = "{app_id}" }}'
            )
        elif declared[brand] != app_id:
            problems.append(
                f"{brand}: the flavour says {declared[brand]}, "
                f"brands/{brand}.yaml says {app_id}"
            )

    for flavour in declared:
        if flavour not in wanted:
            problems.append(
                f"{GRADLE} has a flavour '{flavour}' with no brands/{flavour}.yaml"
            )

    if problems:
        print("The Android flavours and the brand files disagree:\n")
        for problem in problems:
            print(f"  {problem}")
        print("\nA release built from the wrong one goes to the wrong Play listing.")
        return 1

    for brand, app_id in sorted(wanted.items()):
        print(f"  ok   {brand:<14} {app_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
