#!/usr/bin/env python3
"""Compile field scripts into data/map_scripts.json for ScriptVM.

[M27F Stage 1] Companion to gen_map_texts.py. That one extracts what a script
SAYS; this one extracts what it DOES.

Output shape:
    { "<Label>": [ {"op": "msgbox", "args": ["X", "MSGBOX_NPC"]}, ... ], ... }

msgbox IS EXPANDED HERE, not in the VM. Source defines it as a macro:

    .macro msgbox text, type=MSGBOX_DEFAULT
        loadword 0, \\text
        callstd \\type

...where the type indexes gStdScripts, and each of those decomposes into
primitives (`Std_MsgboxNPC` = lock/faceplayer/message/waitmessage/
waitbuttonpress/release/return). Expanding at compile time means the VM needs
`message`/`waitbuttonpress` and not `callstd` plus a std-script table — the
same "resolve at the boundary" choice gen_map_import makes for warp behaviours.

The expansions below are transcribed from data/scripts/std_msgbox.inc.

⚠️ [Field-script authoring fork] `REF` POINTS AT `field_script_source/`, A
PROJECT-OWNED, TRACKED, HAND-EDITABLE COPY — NOT `reference/
pokeemerald_expansion` ANY LONGER. This is deliberate, not a mistake to
"fix" back: the whole point of the fork is that this project's own field
scripts and dialogue are meant to be authored, and a generator reading from
the read-only upstream reference clone can never reflect a hand edit — it
would just regenerate the original content on the next run and silently
discard whatever was changed.

`field_script_source/data/` is a byte-for-byte copy of every `.inc`/`.s`
file `reference/pokeemerald_expansion/data/` ever had (1025 files, taken
2026-08-06, verified byte-identical output before any edit was made — see
`docs/field_script_authoring.md`), in the SAME relative layout, which is
why this file's own `iter_inc_files()` needed no change beyond the `REF`
value itself. From here on this directory is the real, hand-authorable
source for every field script and every line of dialogue in the game —
edit it directly, then re-run this script (and `gen_map_texts.py`) to
regenerate `data/map_scripts.json`/`data/map_texts.json`.

DO NOT REPOINT `REF` BACK AT `reference/pokeemerald_expansion`. Doing so
would silently discard every hand edit made to `field_script_source/` on
the very next regeneration.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trainer_keys import canonical_key, is_trainer_constant

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(PROJECT, "field_script_source")
OUT = os.path.join(PROJECT, "data", "map_scripts.json")

LABEL_RE = re.compile(r"^(\w+)::?\s*$", re.M)

# Verbatim from data/scripts/std_msgbox.inc. `message` takes the text label,
# substituted per call site.
# ⚠️ The trailing `return` of each std script is DROPPED. In source, `callstd`
# pushes a return address and the std script's own `return` pops back to the
# caller. Inlining removes the call, so keeping the `return` would return from
# the CALLER instead — caught by reading the compiled output of a Pewter Gym
# statue, where it would have skipped `releaseall` and `end` and left the player
# locked with the box open.
MSGBOX_EXPANSIONS = {
    "MSGBOX_NPC": ["lock", "faceplayer", "message", "waitmessage",
                   "waitbuttonpress", "release"],
    "MSGBOX_SIGN": ["lockall", "message", "waitmessage",
                    "waitbuttonpress", "releaseall"],
    "MSGBOX_DEFAULT": ["message", "waitmessage", "waitbuttonpress"],
    "MSGBOX_AUTOCLOSE": ["message", "waitmessage", "waitbuttonpress",
                         "closemessage"],
    "MSGBOX_YESNO": ["message", "waitmessage", "yesnobox"],
}


def iter_inc_files():
    for root, _dirs, files in os.walk(os.path.join(REF, "data")):
        for f in files:
            if f.endswith(".inc") or f.endswith(".s"):
                yield os.path.join(root, f)


def parse_args(rest):
    """Split an operand list, respecting quoted strings."""
    out, cur, depth, q = [], "", 0, False
    for ch in rest:
        if ch == '"':
            q = not q
        if ch == "," and not q and depth == 0:
            out.append(cur.strip())
            cur = ""
            continue
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        cur += ch
    if cur.strip():
        out.append(cur.strip())
    return [a for a in out if a != ""]


def _canonicalise_trainers(args):
    """Suffix every trainer-key argument with its roster of origin.

    ⚠️ WITHOUT THIS, EVERY TRAINER BATTLE IN KANTO IS UNSTARTABLE. Scripts carry
    the bare source constant (`TRAINER_LEADER_BROCK`) while the roster this
    project generates is keyed `TRAINER_LEADER_BROCK_FRLG`, so the lookup finds
    nothing and the battle silently refuses -- which reads as "the script did
    not run" rather than as a key mismatch.

    [M27B Step 5] fixed exactly this for PLACEMENTS in gen_map_import.py. This
    compiler was written later and never got the same treatment; found by
    live-driving Brock, whose intro speech played and whose battle then never
    started. Transforms only what the index recognises, so battle-MODE
    constants and TRAINER_NONE pass through untouched.
    """
    return [canonical_key(a) if isinstance(a, str) and is_trainer_constant(a) else a
            for a in args]


def compile_body(body):
    ops = []
    skipping = False
    for line in body.splitlines():
        line = line.split("@")[0].strip()
        if not line:
            continue
        if line.startswith("#"):
            d = line.split()[0]
            if d in ("#ifdef", "#if"):
                skipping = True
            elif d == "#ifndef":
                skipping = False
            elif d == "#else":
                skipping = not skipping
            elif d == "#endif":
                skipping = False
            continue
        if skipping:
            continue
        if line.startswith("."):
            # .string runs belong to gen_map_texts; a text label compiles to no
            # ops at all, which is how the two generators stay disjoint.
            if line.startswith(".string"):
                return None
            continue
        parts = line.split(None, 1)
        op = parts[0]
        args = parse_args(parts[1]) if len(parts) > 1 else []

        if op == "msgbox":
            text_label = args[0] if args else ""
            mtype = args[1] if len(args) > 1 else "MSGBOX_DEFAULT"
            for sub in MSGBOX_EXPANSIONS.get(mtype, MSGBOX_EXPANSIONS["MSGBOX_DEFAULT"]):
                ops.append({"op": sub, "args": [text_label] if sub == "message" else []})
            continue

        ops.append({"op": op, "args": _canonicalise_trainers(args)})
    return ops


def main():
    scripts = {}
    for path in iter_inc_files():
        try:
            src = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        marks = list(LABEL_RE.finditer(src))
        for i, m in enumerate(marks):
            name = m.group(1)
            start = m.end()
            end = marks[i + 1].start() if i + 1 < len(marks) else len(src)
            ops = compile_body(src[start:end])
            if ops is None or not ops:
                continue
            scripts.setdefault(name, ops)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(scripts, f, ensure_ascii=False, indent=0, sort_keys=True)

    total = sum(len(v) for v in scripts.values())
    print("gen_map_scripts: %d scripts, %d ops -> %s"
          % (len(scripts), total, os.path.normpath(OUT)))
    if not scripts:
        print("gen_map_scripts: FAILED - compiled zero scripts", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
