#!/usr/bin/env python3
"""Check the workflow files the way GitHub does, not the way PyYAML does.

`yaml.safe_load` accepts a duplicate key and silently keeps the last one, so a
workflow with two `brand:` inputs parses cleanly here and is rejected by GitHub
with nothing more than "this run likely failed because of a workflow file
issue" — no line, no key, no clue.

That happened, so this exists.
"""
import sys
from pathlib import Path

import yaml


class DuplicateKeyLoader(yaml.SafeLoader):
    """A loader that refuses what GitHub refuses."""


def _no_duplicates(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            mark = key_node.start_mark
            raise yaml.constructor.ConstructorError(
                None, None,
                f"duplicate key {key!r} at line {mark.line + 1}, column {mark.column + 1}",
                node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


DuplicateKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates
)

def main(paths):
    problems = 0
    for path in sorted(paths):
        try:
            with open(path) as f:
                yaml.load(f, Loader=DuplicateKeyLoader)
        except yaml.YAMLError as e:
            print(f"  FAIL {path}\n       {e}")
            problems += 1
            continue
        print(f"  ok   {path}")
    return 1 if problems else 0


if __name__ == "__main__":
    files = sys.argv[1:] or [
        str(p) for p in Path(".github/workflows").glob("*.yml")
    ] + [str(p) for p in Path(".github/workflows").glob("*.yaml")]
    sys.exit(main(files))
