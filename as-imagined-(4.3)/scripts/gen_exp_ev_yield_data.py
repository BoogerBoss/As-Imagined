#!/usr/bin/env python3
"""
[M20a] Adds per-species exp_yield (already a dormant PokemonSpecies field,
just never populated in pokemon.json) and 6 new ev_yield_hp/atk/def/spa/spd/
spe fields (0-3 each, matching source's own 2-bit bitfields) to
data/pokemon.json. Needed by M20's already-shipped EXP formula
(BattleManager._compute_exp_award reads species.exp_yield directly) and by
the still-unbuilt M20c EV-gain grant logic.

Usage (from project root):
    python3 scripts/gen_exp_ev_yield_data.py

Source: reference/pokeemerald_expansion/src/data/pokemon/species_info/
gen_{1,2,3}_families.h (same 3 files every prior per-species extractor in
this project reads — [M15]/[M18.5d Phase 1]/[M19-pre1]'s own precedent: no
rerunnable extractor tool exists in this repo for any species field, so this
parses source directly). Struct fields: include/pokemon.h:403-410 ::
`u16 expYield` / `u16 evYield_HP:2` / `evYield_Attack:2` / `evYield_Defense:2`
/ `evYield_Speed:2` / `evYield_SpAttack:2` / `evYield_SpDefense:2`.

Each field's raw value is one of three shapes, all resolved against this
project's real GEN_LATEST=GEN_9 config (confirmed: GEN_1=0 ... GEN_9=8,
`include/config/general.h:62-70` — a genuinely 0-INDEXED enum, not 1-indexed;
GEN_9 is ordinal 8):
  1. A plain integer literal (the common case).
  2. An inline ternary gated on P_UPDATED_EXP_YIELDS (expYield) or
     P_UPDATED_EVS (evYield_*) — the only 2 config vars ever used for
     either field family (confirmed via a full-source grep before writing
     this script, not assumed), e.g. `(P_UPDATED_EXP_YIELDS >= GEN_5) ? 142
     : 141`. Both configs resolve to GEN_LATEST=GEN_9 in this project.
  3. A named macro reference (expYield only — confirmed zero evYield_*
     fields ever use one): 9 species (Blastoise/Butterfree/Charizard/
     Deoxys/Gengar/Machamp/Pikachu/Raichu/Venusaur) route through a
     `#if/#elif/#else #define NAME value #endif` block defined just above
     their own species entry, resolved the same GEN-ordinal way.

Deoxys (dex 386, multi-form) and every other multi-form species use the
same "first occurrence per dex number wins (base form only)" dedup rule
[M15]/[gen_weight_data.py] already established — no special-casing needed
beyond that.

Unown (#201) is hardcoded — its species block uses the UNOWN_MISC_INFO
macro, not a plain struct literal (the same extractor blind spot every
prior per-species script here has independently hit and documented).
Confirmed directly from source (gen_2_families.h:4059-4061):
`.expYield = (P_UPDATED_EXP_YIELDS >= GEN_5) ? 118 : 61` (-> 118 at GEN_9),
`.evYield_Attack = 1`, `.evYield_SpAttack = 1`, all other evYield_* absent
(implicit 0, matching C struct-literal default-init semantics).

evYield_* fields absent from a species' own struct literal are legitimate
0s (C default-initializes unmentioned struct members) — NOT a missing-data
error, unlike a genuinely absent expYield/dex-number pairing.

Idempotent: overwrites any existing exp_yield/ev_yield_* fields with the
freshly re-parsed values, so reruns are safe.
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "..", "reference", "pokeemerald_expansion")
POKEDEX_H = os.path.join(REF, "include", "constants", "pokedex.h")
FAMILY_FILES = [
    os.path.join(REF, "src", "data", "pokemon", "species_info", f"gen_{n}_families.h")
    for n in (1, 2, 3)
]
POKEMON_JSON = os.path.join(ROOT, "data", "pokemon.json")

UNOWN_DEX = 201
UNOWN_YIELDS = {
    "exp_yield": 118,
    "ev_yield_hp": 0, "ev_yield_atk": 1, "ev_yield_def": 0,
    "ev_yield_spa": 1, "ev_yield_spd": 0, "ev_yield_spe": 0,
}

# include/config/general.h:62-70 -- confirmed 0-indexed, NOT 1-indexed.
GEN_ORDINAL = {f"GEN_{n}": n - 1 for n in range(1, 10)}
CURRENT_GEN = GEN_ORDINAL["GEN_9"]  # this project's real GEN_LATEST config

EV_FIELD_MAP = {
    "evYield_HP": "ev_yield_hp",
    "evYield_Attack": "ev_yield_atk",
    "evYield_Defense": "ev_yield_def",
    "evYield_SpAttack": "ev_yield_spa",
    "evYield_SpDefense": "ev_yield_spd",
    "evYield_Speed": "ev_yield_spe",
}

OPS = {
    ">=": lambda a, b: a >= b, "<=": lambda a, b: a <= b,
    ">": lambda a, b: a > b, "<": lambda a, b: a < b,
    "==": lambda a, b: a == b, "!=": lambda a, b: a != b,
}

TERNARY_RE = re.compile(
    r"\(\s*(P_UPDATED_EXP_YIELDS|P_UPDATED_EVS)\s*(>=|<=|>|<|==|!=)\s*(GEN_\d)\s*\)"
    r"\s*\?\s*(\d+)\s*:\s*(\d+)")


def eval_cond(op: str, gen_name: str) -> bool:
    return OPS[op](CURRENT_GEN, GEN_ORDINAL[gen_name])


def resolve_value(raw: str, macro_table: dict) -> int:
    raw = raw.strip()
    if raw.isdigit():
        return int(raw)
    m = TERNARY_RE.match(raw)
    if m:
        _config, op, gen_name, then_val, else_val = m.groups()
        return int(then_val) if eval_cond(op, gen_name) else int(else_val)
    if raw in macro_table:
        return macro_table[raw]
    raise ValueError(f"unrecognized expYield/evYield expression: {raw!r}")


def build_dex_ordinal_map():
    with open(POKEDEX_H, encoding="utf-8") as f:
        content = f.read()
    enum_m = re.search(r"enum NationalDexOrder\s*\{(.*?)\n\};", content, re.DOTALL)
    ordinal = 0
    mapping = {}
    for line in enum_m.group(1).split("\n"):
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        m = re.match(r"(NATIONAL_DEX_\w+)\s*,?", line)
        if m:
            mapping[m.group(1)] = ordinal
            ordinal += 1
    return mapping


def build_macro_table(contents: list) -> dict:
    """Resolves every `#if/#elif/#else #define <NAME>_EXP_YIELD <value> ... #endif`
    block to a single GEN_9-correct int, for all 9 known named-macro species.
    Branches are evaluated in file order (first true #if/#elif wins, bare
    #else is the unconditional fallback) -- mirrors real preprocessor
    evaluation order, not assumed equivalent to "first/last branch"."""
    macro_table = {}
    define_re = re.compile(r"#define\s+(\w+_EXP_YIELD)\s+(\d+)")
    cond_re = re.compile(r"#(if|elif)\s+(P_UPDATED_EXP_YIELDS)\s*(>=|<=|>|<|==|!=)\s*(GEN_\d)")
    for content in contents:
        lines = content.split("\n")
        pending_branches = {}  # name -> list of (cond_or_None, value)
        current_cond = None
        for line in lines:
            cm = cond_re.search(line)
            if cm:
                _kw, _config, op, gen_name = cm.groups()
                current_cond = (op, gen_name)
                continue
            if line.strip() == "#else":
                current_cond = "ELSE"
                continue
            if line.strip() == "#endif":
                current_cond = None
                continue
            dm = define_re.search(line)
            if dm:
                name, value = dm.group(1), int(dm.group(2))
                pending_branches.setdefault(name, []).append((current_cond, value))
        for name, branches in pending_branches.items():
            resolved = None
            for cond, value in branches:
                if cond == "ELSE" or cond is None:
                    resolved = value
                    break
                op, gen_name = cond
                if eval_cond(op, gen_name):
                    resolved = value
                    break
            if resolved is None:
                raise SystemExit(f"ERROR: could not resolve macro {name} for GEN_9")
            macro_table[name] = resolved
    return macro_table


def extract_yields(dex_ordinal: dict, macro_table: dict) -> dict:
    dex_to_yields = {UNOWN_DEX: dict(UNOWN_YIELDS)}
    field_re = re.compile(
        r"\.(expYield|evYield_\w+)\s*=\s*([^,\n]+),")
    for path in FAMILY_FILES:
        with open(path, encoding="utf-8") as f:
            content = f.read()
        block_starts = [m.start() for m in re.finditer(r"\n    \[SPECIES_\w+\]\s*=\s*\n    \{", content)]
        for i, start in enumerate(block_starts):
            end = block_starts[i + 1] if i + 1 < len(block_starts) else len(content)
            block = content[start:end]
            ndm = re.search(r"\.natDexNum\s*=\s*(NATIONAL_DEX_\w+)", block)
            if not ndm:
                continue
            dex = dex_ordinal.get(ndm.group(1))
            if dex is None or not (1 <= dex <= 386):
                continue
            if dex in dex_to_yields:
                continue  # first occurrence per dex wins (base form only)

            entry = {
                "exp_yield": None,
                "ev_yield_hp": 0, "ev_yield_atk": 0, "ev_yield_def": 0,
                "ev_yield_spa": 0, "ev_yield_spd": 0, "ev_yield_spe": 0,
            }
            for fm in field_re.finditer(block):
                field_name, raw_value = fm.group(1), fm.group(2)
                value = resolve_value(raw_value, macro_table)
                if field_name == "expYield":
                    entry["exp_yield"] = value
                else:
                    entry[EV_FIELD_MAP[field_name]] = value

            if entry["exp_yield"] is None:
                continue  # no expYield found in this block -- not a real species entry
            dex_to_yields[dex] = entry
    return dex_to_yields


def main():
    dex_ordinal = build_dex_ordinal_map()
    contents = []
    for path in FAMILY_FILES:
        with open(path, encoding="utf-8") as f:
            contents.append(f.read())
    macro_table = build_macro_table(contents)
    expected_macros = {
        "BLASTOISE_EXP_YIELD", "BUTTERFREE_EXP_YIELD", "CHARIZARD_EXP_YIELD",
        "DEOXYS_EXP_YIELD", "GENGAR_EXP_YIELD", "MACHAMP_EXP_YIELD",
        "PIKACHU_EXP_YIELD", "RAICHU_EXP_YIELD", "VENUSAUR_EXP_YIELD",
    }
    missing_macros = expected_macros - set(macro_table.keys())
    if missing_macros:
        raise SystemExit(f"ERROR: expected named macros not found: {sorted(missing_macros)}")

    dex_to_yields = extract_yields(dex_ordinal, macro_table)

    missing = set(range(1, 387)) - set(dex_to_yields.keys())
    if missing:
        raise SystemExit(f"ERROR: missing exp/ev yield for dex numbers: {sorted(missing)}")

    for dex, entry in dex_to_yields.items():
        for ev_field in ("ev_yield_hp", "ev_yield_atk", "ev_yield_def",
                          "ev_yield_spa", "ev_yield_spd", "ev_yield_spe"):
            v = entry[ev_field]
            if not (0 <= v <= 3):
                raise SystemExit(f"ERROR: dex {dex} {ev_field}={v} out of 2-bit range [0,3]")
        if entry["exp_yield"] <= 0:
            raise SystemExit(f"ERROR: dex {dex} exp_yield={entry['exp_yield']} not positive")

    with open(POKEMON_JSON, encoding="utf-8") as f:
        pokemon = json.load(f)

    changed = 0
    for pentry in pokemon:
        dex = pentry["dex"]
        yields = dex_to_yields[dex]
        for key, value in yields.items():
            if pentry.get(key) != value:
                pentry[key] = value
                changed += 1

    with open(POKEMON_JSON, "w", encoding="utf-8") as f:
        json.dump(pokemon, f, indent=2)
        f.write("\n")

    print(f"exp_yield/ev_yield_*: {changed} field values updated across "
          f"{len(pokemon)} species, {len(dex_to_yields)} dex numbers resolved "
          f"from source, {len(macro_table)} named exp-yield macros resolved")


if __name__ == "__main__":
    main()
