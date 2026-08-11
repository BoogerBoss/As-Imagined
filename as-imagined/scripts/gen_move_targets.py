#!/usr/bin/env python3
"""Extract every move's real `.target` from the reference and emit
`data/move_targets.json` (move id -> MoveTarget ordinal).

Run this BEFORE gen_moves.py, which reads the JSON and writes the value
into each move_NNNN.tres. Same two-step shape as gen_move_descriptions.py.

GENERATED, NOT HAND-TYPED, for the reason this project keeps re-learning:
110 moves are TARGET_USER and a hand-maintained list of them silently rots
the moment a move is added. The ordinals mirror `enum MoveTarget`
(include/constants/battle.h) and MoveData's own TARGET_* constants exactly.

Ternary `.target` values (`B_UPDATED_MOVE_DATA >= GEN_x ? A : B`) resolve to
the GEN_LATEST branch, matching this project's standing "config resolves to
GEN_LATEST" precedent. There are 7 of them and every one is a real move
(Surf, Poison Gas, Conversion 2, Cotton Spore, Nature Power, Helping Hand,
Howl) -- reading only the plain `= TARGET_X,` form drops all 7 silently.
"""

import json
import pathlib
import re
import sys

REF = pathlib.Path("/home/rob/GodotAsImagined/reference/pokeemerald_expansion")
MOVES_INFO = REF / "src" / "data" / "moves_info.h"

PROJECT = pathlib.Path(__file__).parent.parent
NAME_MAP = PROJECT / "data" / "move_name_to_id.json"
OUT = PROJECT / "data" / "move_targets.json"

# enum MoveTarget, include/constants/battle.h
TARGETS = {
    "TARGET_NONE": 0,
    "TARGET_SELECTED": 1,
    "TARGET_SMART": 2,
    "TARGET_DEPENDS": 3,
    "TARGET_OPPONENT": 4,
    "TARGET_RANDOM": 5,
    "TARGET_BOTH": 6,
    "TARGET_USER": 7,
    "TARGET_ALLY": 8,
    "TARGET_USER_AND_ALLY": 9,
    "TARGET_USER_OR_ALLY": 10,
    "TARGET_FOES_AND_ALLY": 11,
    "TARGET_FIELD": 12,
    "TARGET_OPPONENTS_FIELD": 13,
    "TARGET_ALL_BATTLERS": 14,
}


def iter_entries(src: str):
    """Yield (MOVE_CONSTANT, body) by brace-matching each entry."""
    for m in re.finditer(r"\[(MOVE_[A-Z0-9_]+)\]\s*=\s*\{", src):
        i = m.end() - 1
        depth = 0
        while True:
            if src[i] == "{":
                depth += 1
            elif src[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        yield m.group(1), src[m.end():i]


def resolve_target(body: str, move: str) -> str | None:
    m = re.search(r"\.target\s*=\s*([^,\n]+?)\s*,", body)
    if not m:
        return None
    expr = m.group(1).strip()
    if expr in TARGETS:
        return expr
    # `<config> >= GEN_x ? A : B` -- take the GEN_LATEST branch.
    tern = re.match(r".*\?\s*(TARGET_[A-Z_]+)\s*:\s*(TARGET_[A-Z_]+)\s*$", expr)
    if tern:
        return tern.group(1)
    raise SystemExit(f"gen_move_targets: unparsed .target for {move}: {expr!r}")


def main() -> int:
    if not MOVES_INFO.exists():
        raise SystemExit(f"gen_move_targets: missing {MOVES_INFO}")
    src = MOVES_INFO.read_text(encoding="utf-8")
    name_to_id = json.loads(NAME_MAP.read_text(encoding="utf-8"))

    by_id: dict[int, int] = {}
    unresolved: list[str] = []
    missing_target: list[str] = []

    for move, body in iter_entries(src):
        target = resolve_target(body, move)
        if target is None:
            missing_target.append(move)
            continue
        move_id = name_to_id.get(move)
        if move_id is None:
            unresolved.append(move)
            continue
        # Aliased constants (MOVE_X = MOVE_Y) resolve to the same id; both
        # spellings carry the same .target, so a collision is benign -- but a
        # DISAGREEING collision means the name map is wrong, so fail loudly.
        prev = by_id.get(move_id)
        if prev is not None and prev != TARGETS[target]:
            raise SystemExit(
                f"gen_move_targets: id {move_id} has conflicting targets "
                f"({prev} vs {TARGETS[target]}) -- last seen {move}"
            )
        by_id[move_id] = TARGETS[target]

    if missing_target:
        raise SystemExit(
            "gen_move_targets: entries with no .target at all: "
            + ", ".join(missing_target)
        )
    if not by_id:
        raise SystemExit("gen_move_targets: parsed 0 moves -- refusing to write")

    OUT.write_text(
        json.dumps({str(k): v for k, v in sorted(by_id.items())}, indent=1) + "\n",
        encoding="utf-8",
    )

    counts: dict[int, int] = {}
    for v in by_id.values():
        counts[v] = counts.get(v, 0) + 1
    ordinal_to_name = {v: k for k, v in TARGETS.items()}
    print(f"gen_move_targets: {len(by_id)} move ids -> {OUT}")
    for ordinal, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {ordinal_to_name[ordinal]:24s} {n}")
    if unresolved:
        print(f"  ({len(unresolved)} source constants with no id in the name map)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
