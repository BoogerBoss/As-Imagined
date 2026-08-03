#!/usr/bin/env python3
"""
[M27I I1] Generates data/item_name_to_id.json: a flat {"ITEM_XXX": id} map,
parsed from the canonical reference enum
(reference/pokeemerald_expansion/include/constants/items.h).

Why this exists
---------------
Map scripts identify an item ONLY by constant name -- `giveitem ITEM_TM39`,
`checkitem ITEM_OAKS_PARCEL`. Every other part of this project identifies an
item by numeric id (`ItemData.item_id`, `ItemRegistry.get_item`,
`PokemonRegistry.get_item`). This builds the one bridge, so M27I's bag does not
re-derive the parse ad hoc.

Deliberately mirrors gen_move_name_map.py, which solved the identical problem
for moves -- same enum shape, same three entry forms, same alias hazard.

The three entry forms, all real in this enum
--------------------------------------------
  * explicit   `ITEM_TM01 = 582,`
  * bare       `ITEM_XXX,`            -- C semantics: previous + 1
  * ALIAS      `ITEM_OAKS_PARCEL = ITEM_PARCEL,`   ("Pre-Gen IV name")

⚠️ THE ALIASES ARE NOT COSMETIC AND THE CORRIDOR USES BOTH SIDES. Its scripts
reference `ITEM_DOWSING_MACHINE` AND `ITEM_ITEMFINDER`, which are the same item
(`ITEM_ITEMFINDER = ITEM_DOWSING_MACHINE`). A parser that only handles
`= <int>` drops every alias silently, and the script that wanted one then fails
to resolve an item that exists. Same class as the `MOVE_FAINT_ATTACK =
MOVE_FEINT_ATTACK` finding in [M27B Step 4].

⚠️ NON-ITEM SENTINELS MUST STILL ADVANCE THE COUNTER. `LAST_BERRY_INDEX`,
`ITEMS_COUNT` and friends sit inside the enum body; skipping them without
counting would shift every following item by one. They are recorded in the
running map (so a later `= LAST_BERRY_INDEX` alias resolves) but not emitted.

TMs and HMs are a macro, not constants
--------------------------------------
The move-named forms (`ITEM_TM_ROAR`, `ITEM_HM_FLY`) are generated inside the
enum by a preprocessor zip, not written out:

    #define ENUM_TM(n, id) CAT(ITEM_TM_, id) = CAT(ITEM_TM, n),
    RECURSIVELY(R_ZIP(ENUM_TM, TO_TMHM_NUMS NUMBERS_256, (FOREACH_TM(APPEND_COMMA))))

Source documents the result in its own comment: `ITEM_TM_FOCUS_PUNCH =
ITEM_TM01`. So rather than emulate the preprocessor, this reads the ordered
move list out of FOREACH_TM/FOREACH_HM (include/constants/tms_hms.h) and pairs
entry n with `ITEM_TM<n>` / `ITEM_HM<n>`. The corridor needs six of these
(TM_ROAR, TM_DIG, TM_TAUNT, TM_BULLET_SEED, TM_GIGA_DRAIN, TM_SECRET_POWER,
HM_FLY), so they are load-bearing, not completeness for its own sake.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
REFERENCE = os.path.join(os.path.dirname(PROJECT), "reference", "pokeemerald_expansion")
ITEMS_H = os.path.join(REFERENCE, "include", "constants", "items.h")
TMS_H = os.path.join(REFERENCE, "include", "constants", "tms_hms.h")
OUT = os.path.join(PROJECT, "data", "item_name_to_id.json")
ITEMS_JSON = os.path.join(PROJECT, "data", "items.json")

ENUM_RE = re.compile(r"^enum\s+__attribute__\(\(packed\)\)\s+Item\s*$", re.M)
EXPLICIT = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*=\s*(\d+)\s*,")
ALIAS = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*=\s*([A-Z][A-Z0-9_]*)\s*,")
BARE = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*,\s*(?://.*)?$")


def enum_body(text):
    """The lines between `enum ... Item` and its closing brace."""
    m = ENUM_RE.search(text)
    if not m:
        sys.exit("could not find `enum __attribute__((packed)) Item` in items.h")
    lines = text[m.end():].split("\n")
    out, depth, started = [], 0, False
    for line in lines:
        if "{" in line:
            depth += line.count("{")
            started = True
        if started:
            out.append(line)
        if "}" in line:
            depth -= line.count("}")
            if started and depth <= 0:
                break
    return out


def parse_enum():
    """{name: value} for every entry, sentinels included."""
    body = enum_body(open(ITEMS_H, encoding="utf-8").read())
    values, order, nxt = {}, [], 0
    for raw in body:
        line = raw.split("//")[0].split("/*")[0]
        if not line.strip() or "#" in line or "(" in line:
            # Macro lines (RECURSIVELY/ENUM_TM/...) are handled separately; a
            # preprocessor emulator here would be far more than this needs.
            continue
        m = EXPLICIT.match(line)
        if m:
            name, val = m.group(1), int(m.group(2))
        else:
            m = ALIAS.match(line)
            if m:
                name, target = m.group(1), m.group(2)
                if target not in values:
                    continue  # forward reference; none exist today
                val = values[target]
            else:
                m = BARE.match(line)
                if not m:
                    continue
                name, val = m.group(1), nxt
        values[name] = val
        order.append(name)
        nxt = val + 1
    return values, order


def parse_tmhm():
    """{ITEM_TM_<MOVE>: n} / {ITEM_HM_<MOVE>: n}, 1-based, in listed order."""
    text = open(TMS_H, encoding="utf-8").read()
    out = {}
    for kind in ("TM", "HM"):
        m = re.search(r"#define\s+FOREACH_%s\(F\)((?:.*\\\n)*.*)" % kind, text)
        if not m:
            sys.exit("could not find FOREACH_%s in tms_hms.h" % kind)
        names = re.findall(r"F\(([A-Z0-9_]+)\)", m.group(1))
        for i, move in enumerate(names, start=1):
            out["ITEM_%s_%s" % (kind, move)] = (kind, i)
    return out


def main():
    values, order = parse_enum()

    # Emit only real ITEM_* entries; sentinels stay in `values` so aliases that
    # point at them resolve, but they are not items and must not be offered.
    SENTINELS = ("ITEMS_COUNT", "ITEM_LIST_END")
    out = {n: v for n, v in values.items()
           if n.startswith("ITEM_") and n not in SENTINELS}

    # The macro-generated TM/HM move-name forms.
    tmhm, missing = parse_tmhm(), []
    for name, (kind, n) in tmhm.items():
        numbered = "ITEM_%s%02d" % (kind, n)
        if numbered in values:
            out[name] = values[numbered]
        else:
            missing.append((name, numbered))
    if missing:
        # Loud rather than silent: a shifted FOREACH list would otherwise
        # mis-map every TM after the gap.
        sys.exit("TM/HM alias target(s) missing from the enum: %r" % missing[:5])

    # --- guards -----------------------------------------------------------
    ids = json.load(open(ITEMS_JSON, encoding="utf-8"))
    known = {e["id"] for e in (ids if isinstance(ids, list) else ids.values())}
    dangling = sorted({v for v in out.values() if v not in known})
    if dangling:
        print("  WARNING: %d id(s) not present in items.json, e.g. %s"
              % (len(dangling), dangling[:8]))

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(out.items())), f, indent="\t", sort_keys=True)
        f.write("\n")

    aliases = len(out) - len({v for v in out.values()})
    print("item name map : %s" % os.path.relpath(OUT, PROJECT))
    print("  constants   : %d  (%d distinct ids, so %d are alias spellings)"
          % (len(out), len({v for v in out.values()}), aliases))
    print("  tm/hm forms : %d" % len(tmhm))
    print("  items.json  : %d entries" % len(known))


if __name__ == "__main__":
    main()
