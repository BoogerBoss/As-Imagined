#!/usr/bin/env python3
"""Detect hand edits a re-bake would destroy.

[M27B] The re-import-vs-hand-edits risk in one command. A baked map scene is
BOTH a generated artifact and a hand-editable file (docs/overworld_scope.md
§1.9), so the standing question for any re-bake session is: does this scene
still contain only what the baker would produce?

    python3 scripts/check_bake_diff.py Route3_Frlg [MoreMaps...]
    python3 scripts/check_bake_diff.py --all        # every scene in scenes/maps/

Exits 0 when every checked scene is reproducible, 1 (with a readable diff) when
one is not -- meaning it carries hand-authored content a `--force` re-bake would
silently overwrite.

WHY THIS IS NOT JUST `git diff`: Godot regenerates every node's `unique_id` on
each bake. Re-baking the 8-map corridor produced a 201-line diff of which only
26 lines were semantic -- so real content genuinely can hide inside the churn.
This normalises `unique_id` away before comparing, which is the difference
between a reviewable answer and a wall of noise.

NON-DESTRUCTIVE: the current scene is restored afterwards whether the check
passes or fails, so running this never costs you an edit. Nothing is wired into
the baker itself -- this is a standalone check a re-bake session runs first.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

from ref_path import PROJECT

# CLAUDE.md's canonical binary. Overridable so this runs from a worktree or
# another machine without editing the file.
GODOT = os.environ.get("GODOT", "/home/rob/Godot_v4.7.1-stable_linux.x86_64")
MAPS_DIR = os.path.join(PROJECT, "scenes", "maps")
BAKER_SCENE = "scenes/overworld/map_baker.tscn"

# Regenerated per bake, carries no meaning, and is the entire reason a
# reproducible scene still shows up as a large diff.
_UNIQUE_ID = re.compile(r" unique_id=\d+")


def normalize(text):
    return _UNIQUE_ID.sub("", text)


def scene_path(map_name):
    return os.path.join(MAPS_DIR, map_name + ".tscn")


def all_map_names():
    if not os.path.isdir(MAPS_DIR):
        return []
    return sorted(
        f[:-5] for f in os.listdir(MAPS_DIR)
        if f.endswith(".tscn") and not f.endswith("_data.tres"))


def bake(map_names):
    cmd = [GODOT, "--headless", "--path", PROJECT, BAKER_SCENE, "--"] \
        + list(map_names) + ["--force"]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    if "baked" not in proc.stdout:
        sys.stderr.write(proc.stdout + proc.stderr)
        raise SystemExit("check_bake_diff: baker did not report a result")
    return proc.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("maps", nargs="*", help="map names, e.g. Route3_Frlg")
    ap.add_argument("--all", action="store_true", help="check every scene in scenes/maps/")
    args = ap.parse_args()

    names = all_map_names() if args.all else args.maps
    if not names:
        ap.error("name at least one map, or pass --all")

    missing = [n for n in names if not os.path.exists(scene_path(n))]
    if missing:
        raise SystemExit("check_bake_diff: no baked scene for %s" % ", ".join(missing))

    stash = tempfile.mkdtemp(prefix="bakecheck_")
    try:
        before = {}
        for n in names:
            shutil.copy(scene_path(n), os.path.join(stash, n + ".tscn"))
            before[n] = open(scene_path(n), encoding="utf-8").read()

        bake(names)

        drifted = []
        for n in names:
            after = open(scene_path(n), encoding="utf-8").read()
            if normalize(before[n]) != normalize(after):
                drifted.append(n)

        # Always restore: this is a check, not a rebuild.
        for n in names:
            shutil.copy(os.path.join(stash, n + ".tscn"), scene_path(n))

        if not drifted:
            print("check_bake_diff: %d scene(s) reproducible — a re-bake would "
                  "lose nothing." % len(names))
            return 0

        print("check_bake_diff: %d of %d scene(s) are NOT reproducible.\n"
              % (len(drifted), len(names)))
        print("These carry content the baker does not produce — a --force re-bake")
        print("would overwrite it. Reconcile before re-baking.\n")
        import difflib
        for n in drifted:
            after = open(os.path.join(stash, n + ".tscn"), encoding="utf-8").read()
            fresh = normalize(before[n]).splitlines(keepends=True)
            # `before` is the tracked scene; re-bake it once more to show against.
            bake([n])
            rebaked = normalize(
                open(scene_path(n), encoding="utf-8").read()).splitlines(keepends=True)
            shutil.copy(os.path.join(stash, n + ".tscn"), scene_path(n))
            print("=== %s (unique_id normalised away) ===" % n)
            sys.stdout.writelines(
                difflib.unified_diff(rebaked, fresh,
                                     fromfile="freshly baked", tofile="tracked scene"))
            print()
        return 1
    finally:
        shutil.rmtree(stash, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
