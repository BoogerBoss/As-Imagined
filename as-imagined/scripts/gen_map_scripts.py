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
## ⚠️ A SEPARATE FILE, not a key inside map_scripts.json. That file is a FLAT
## `label -> ops` dictionary with 17,159 entries and every consumer looks a
## label up in it directly; a top-level "data_lists" key would be indexed as a
## label named `data_lists`. A sidecar also matches the shape this project
## already uses for per-pair behaviours, layer types and authored encounters.
DATA_OUT = os.path.join(PROJECT, "data", "map_data_lists.json")

LABEL_RE = re.compile(r"^(\w+)::?[ \t]*(?:@.*)?$", re.M)
"""A label line.

⚠️ **THE TRAILING-COMMENT CASE WAS MISSING, AND IT SILENTLY LOST 16 LABELS.**
The pattern used to be ``^(\w+)::?\s*$``, which requires the label to be the
last thing on its line. The reference decorates some labels with the original
ROM address::

    PalletTown_ProfessorOaksLab_EventScript_EnterForNationalDexScene:: @ 8169002

That did not match, so the line was not recognised as a label at all: its body
merged into whichever label PRECEDED it, and the label line itself compiled as
a bogus opcode named ``Something::``. The label then did not exist in the
corpus, so anything jumping to it reported ``UNRESOLVED``.

⚠️ **ONE INSTANCE IS REACHABLE.** ``PalletTown_ProfessorOaksLab_OnFrame`` does
``map_script_2 VAR_MAP_SCENE_..., 7, ..._EventScript_EnterForNationalDexScene``
— a jump to a label that was not there. Unreachable in play today only because
it needs the postgame.

This is the SECOND bug of exactly this shape (labels merging into their
predecessor); the first was the missing ``.macro``/``.endm`` handling, which
truncated Oak's lab-entry cutscene. Both were found by measuring the compiled
corpus rather than by reading the compiler.
"""
MACRO_START_RE = re.compile(r"^[ \t]*\.macro[ \t]+(\w+)([^\n]*)$", re.M)
MACRO_END_RE = re.compile(r"^[ \t]*\.endm[ \t]*$", re.M)

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


def extract_macros(src):
    """Find every local `.macro NAME ... .endm` block in one file's raw text.

    ⚠️ [Bugfix, live-reported: Oak's lab-entry cutscene truncated to one step
    each way, player left invisible after the warp] This compiler had NO
    concept of `.macro`/`.endm` at all beyond incidentally skipping those two
    directive lines (they start with `.`, same as every other assembler
    directive `compile_body` already ignores) -- the macro's own BODY lines
    were left to fall wherever the label-slicing loop happened to land them
    (silently appended to whichever label precedes the definition in the
    file, harmless only because a `step_end` already terminates that label's
    own interpretation before reaching them), and an INVOCATION of the macro
    elsewhere compiled as a literal, unrecognised op named after the macro
    itself. `MovementRunner._begin()` treats an unrecognised action as "stop
    this mover here" by design (so a genuinely unported action reports as a
    coverage gap, not a cutscene that silently continues) -- which is exactly
    why Oak and the player both walked one real step, then hit the
    unexpanded `walk_to_lab` op and stopped, then immediately ran the NEXT
    `applymovement` in the script (the door-entry one, ending in
    `set_invisible`) early.

    Confirmed via a full corpus sweep this is not Pallet-Town-specific: Pewter
    City (`walk_to_gym`/`walk_to_gym_alt`/`walk_to_museum`/
    `walk_to_museum_south`) and One Island (`walk_to_pokecenter`) define the
    identical local-macro pattern for their own NPC-escort cutscenes -- all
    of them parameterless movement-list macros, the only shape this fixes.

    Returns (macros, spans): `macros` maps macro name -> list of raw body
    lines, for PARAMETERLESS macros only. `spans` is the list of
    (start, end) character offsets each definition occupies in `src`, blanked
    out by the caller before label boundaries are computed -- otherwise a
    macro definition sitting between two labels keeps leaking into whichever
    label precedes it.

    A macro declared WITH parameters (`setitemandprice item:req, price:req`,
    BattleFrontier_ExchangeServiceCorner's own shop-price macro -- a
    permanently-excluded facility, never baked) is intentionally left
    unexpanded: its own invocations keep compiling as an unresolved literal
    op, the exact pre-existing behaviour, rather than risk a wrong
    argument-substitution for a macro shape nothing in this project's real
    scope currently uses.
    """
    macros = {}
    spans = []
    pos = 0
    while True:
        m = MACRO_START_RE.search(src, pos)
        if not m:
            break
        name = m.group(1)
        params = m.group(2).strip()
        end_m = MACRO_END_RE.search(src, m.end())
        if not end_m:
            break  # Malformed/unterminated -- stop scanning this file.
        if not params:
            body_text = src[m.end():end_m.start()]
            macros[name] = body_text.splitlines()
        spans.append((m.start(), end_m.end()))
        pos = end_m.end()
    return macros, spans


def blank_spans(src, spans):
    """Replace each (start, end) span's own characters with spaces/newlines,
    preserving every other character offset so `LABEL_RE`'s match positions
    (computed against the ORIGINAL text) still slice the right label bodies
    out of the result.
    """
    if not spans:
        return src
    chars = list(src)
    for start, end in spans:
        for i in range(start, end):
            chars[i] = "\n" if chars[i] == "\n" else " "
    return "".join(chars)


def expand_macros(body, macros):
    """Inline every whole-line invocation of a known parameterless macro.

    One pass is enough for this project's real corpus (confirmed: none of
    the movement macros found invoke another macro), but the loop tolerates
    a chain up to a small depth defensively rather than assuming it.
    """
    for _ in range(4):
        lines = body.splitlines()
        changed = False
        out = []
        for line in lines:
            name = line.strip()
            if name in macros:
                out.extend(macros[name])
                changed = True
            else:
                out.append(line)
        body = "\n".join(out)
        if not changed:
            break
    return body


def compile_body(body):
    """Returns (ops, data) -- the opcodes, and any `.2byte` data block.

    ⚠️ **A LABEL CAN BE BOTH.** A mart's stock list is DATA that sits under an
    ordinary label, and in FRLG's own asm it is followed by leftover script
    lines, so the label compiles to real opcodes AND carries a list. Returning
    only one of the two is what dropped every shop's stock silently: `.2byte`
    lines start with `.`, and every `.`-prefixed line was skipped.
    """
    ops = []
    data = []
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
                return None, None
            if line.startswith(".2byte"):
                val = line.split(None, 1)[1].strip() if len(line.split()) > 1 else ""
                # ⚠️ ITEM_NONE is a TERMINATOR, not stock. Source counts
                # `while (itemList[i])` (SetShopItemsForSale, shop.c:384), so
                # emitting it would put a phantom row on every shelf.
                if val and val != "ITEM_NONE":
                    data.append(val)
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
    return ops, data


def main():
    scripts = {}
    data_lists = {}
    for path in iter_inc_files():
        try:
            src = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        macros, macro_spans = extract_macros(src)
        # Label boundaries are computed against the ORIGINAL text (so match
        # offsets stay valid), but each label's own BODY is sliced out of a
        # copy with every macro definition blanked -- otherwise a macro
        # sitting between two labels keeps leaking into whichever label
        # precedes it (see extract_macros' own doc comment).
        src_clean = blank_spans(src, macro_spans)
        marks = list(LABEL_RE.finditer(src))
        for i, m in enumerate(marks):
            name = m.group(1)
            start = m.end()
            end = marks[i + 1].start() if i + 1 < len(marks) else len(src)
            body = expand_macros(src_clean[start:end], macros)
            ops, data = compile_body(body)
            if data:
                data_lists.setdefault(name, data)
            if ops is None or not ops:
                continue
            scripts.setdefault(name, ops)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(scripts, f, ensure_ascii=False, indent=0, sort_keys=True)

    with open(DATA_OUT, "w", encoding="utf-8") as f:
        json.dump(data_lists, f, ensure_ascii=False, indent=0, sort_keys=True)

    # ⚠️ **FAIL THE BUILD, NOT THE SHOP.** Every `pokemart` argument must name a
    # NON-EMPTY list. Before this generator understood `.2byte`, the label still
    # resolved and simply carried no items -- so a shop would have opened onto an
    # empty shelf and looked like a design decision rather than a broken build.
    bad = []
    for label, ops in scripts.items():
        for o in ops:
            if o["op"] == "pokemart":
                target = o["args"][0] if o["args"] else ""
                if not data_lists.get(target):
                    bad.append("%s -> %s" % (label, target or "(no argument)"))
    if bad:
        print("gen_map_scripts: %d pokemart(s) resolve to no stock:" % len(bad),
              file=sys.stderr)
        for b in bad[:20]:
            print("   " + b, file=sys.stderr)
        return 1

    # ...and every item a shop stocks must be a real constant. Checked HERE
    # rather than at runtime so an unknown name is a build failure naming the
    # list, not a shelf that is quietly one row short in play.
    name_map = os.path.join(PROJECT, "data", "item_name_to_id.json")
    if os.path.exists(name_map):
        known = json.load(open(name_map, encoding="utf-8"))
        stocked = set()
        for label, ops in scripts.items():
            for o in ops:
                if o["op"] == "pokemart" and o["args"]:
                    stocked.add(o["args"][0])
        unknown = []
        for label in sorted(stocked):
            for it in data_lists.get(label, []):
                if it not in known:
                    unknown.append("%s -> %s" % (label, it))
        if unknown:
            print("gen_map_scripts: %d stocked item(s) resolve to no id:"
                  % len(unknown), file=sys.stderr)
            for u in unknown[:20]:
                print("   " + u, file=sys.stderr)
            return 1

    total = sum(len(v) for v in scripts.values())
    print("gen_map_scripts: %d scripts, %d ops -> %s"
          % (len(scripts), total, os.path.normpath(OUT)))
    print("gen_map_scripts: %d data list(s), %d entries -> %s"
          % (len(data_lists), sum(len(v) for v in data_lists.values()),
             os.path.normpath(DATA_OUT)))
    if not scripts:
        print("gen_map_scripts: FAILED - compiled zero scripts", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
