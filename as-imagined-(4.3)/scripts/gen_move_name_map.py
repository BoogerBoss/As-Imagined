#!/usr/bin/env python3
"""
[M23.4] Generates data/move_name_to_id.json: a flat {"MOVE_XXX": id} map,
parsed directly from the canonical reference enum
(reference/pokeemerald_expansion/include/constants/moves.h) — the same
source-of-truth file gen_moves.py's own header comment cites for move IDs.

Why this exists: PokemonRegistry.get_learnable_moves(dex) (and the raw
learnsets.json/all_learnables.json data files it reads) return move
identity as "MOVE_TACKLE"-style constant-name strings, never numeric IDs.
Every other part of this project (MoveRegistry, PokemonFactory,
BattlePokemon.add_move) identifies a move by its numeric ID. This script
builds the one reusable bridge between the two, so the M23.4 team builder
(and any future consumer) can resolve get_learnable_moves()'s own string
output into a real move ID without re-deriving this parse ad hoc.

Sequential C-enum resolution (matching this project's own established
pattern — see e.g. the M20a "Hone Claws" sequential-ID-resolution note in
CLAUDE.md): most entries are `MOVE_XXX = <int>,`; many later ones (G-Max
moves, the tail of each generation's block) are auto-incremented bare
`MOVE_XXX,` with no explicit value; some are aliases,
`MOVE_XXX = MOVE_YYY,` (pre-Gen-VI/VIII name variants) or
`MOVE_XXX = MOVES_COUNT_GENn,` (the "next real move after this
generation's placeholder" pattern) — both resolved by looking up the
right-hand identifier in the map being built so far. A plain running
counter (mirroring real C enum semantics: no explicit value = previous
value + 1) handles every case uniformly, including non-MOVE_-prefixed
sentinels like `MOVES_COUNT_GEN1,` which must still advance the counter
even though they aren't stored in the output map.
"""
import json
import re

SRC = "reference/pokeemerald_expansion/include/constants/moves.h"
OUT = "data/move_name_to_id.json"

ENTRY_RE = re.compile(r"^\s*([A-Z_][A-Z0-9_]*)\s*(?:=\s*([^,]+?))?\s*,?\s*$")


def main():
    with open(SRC) as f:
        text = f.read()

    # Isolate the enum body only (between the opening brace of `enum
    # __attribute__((packed)) Move { ... }` and its closing `};`).
    start = text.index("enum __attribute__((packed)) Move")
    body_start = text.index("{", start) + 1
    body_end = text.index("};", body_start)
    body = text[body_start:body_end]

    values: dict[str, int] = {}
    move_ids: dict[str, int] = {}
    counter = -1  # first entry (MOVE_NONE = 0) sets this explicitly

    for raw_line in body.splitlines():
        line = re.sub(r"//.*", "", raw_line).strip()
        if not line:
            continue
        m = ENTRY_RE.match(line)
        if not m:
            continue
        name, expr = m.group(1), m.group(2)

        if expr is None:
            counter += 1
            value = counter
        else:
            expr = expr.strip()
            if re.fullmatch(r"-?\d+", expr):
                value = int(expr)
            elif re.fullmatch(r"0[xX][0-9a-fA-F]+", expr):
                value = int(expr, 16)
            elif expr in values:
                value = values[expr]
            else:
                # Unresolvable expression (e.g. arithmetic on an unknown
                # symbol) — skip rather than guess; none observed in
                # practice for the real Move enum, but fail loud if one
                # ever appears so it isn't silently mis-mapped.
                print("WARNING: could not resolve '%s = %s', skipping" % (name, expr))
                continue
            counter = value

        values[name] = value
        if name.startswith("MOVE_"):
            move_ids[name] = value

    with open(OUT, "w") as f:
        json.dump(move_ids, f, indent=1, sort_keys=True)

    print("Wrote %d MOVE_* entries to %s" % (len(move_ids), OUT))

    # Spot-checks against well-known IDs (also confirmed against
    # data/moves.json's own real "id" field for these same moves elsewhere
    # in this project).
    checks = {
        "MOVE_TACKLE": 33, "MOVE_GROWL": 45, "MOVE_VINE_WHIP": 22,
        "MOVE_SOLAR_BEAM": 76, "MOVE_DOUBLESLAP": 3, "MOVE_DOUBLE_SLAP": 3,
        "MOVE_SKETCH": 166, "MOVE_HONE_CLAWS": 468, "MOVE_TERA_BLAST": 779,
    }
    for name, expected in checks.items():
        actual = move_ids.get(name)
        status = "OK" if actual == expected else "MISMATCH"
        print("  %s: expected %d, got %s [%s]" % (name, expected, actual, status))


if __name__ == "__main__":
    main()
