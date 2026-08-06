#!/usr/bin/env python3
"""
[M27G G3a] Generates data/ingame_trades.json: the `sIngameTrades[]` table
`GetInGameTradeSpeciesInfo`/`GetTradeSpecies`/`CreateInGameTradePokemon`
address, with species/item names already resolved to this project's own
numeric IDs.

Source: `src/data/trade.h:969-1215`, `static const struct InGameTrade
sIngameTrades[]`. 13 entries, index = `enum InGameTradeID`
(`include/constants/trade.h:8-24`) — `VAR_0x8005` holds this same index at
runtime (`copyvar VAR_0x8005, VAR_0x8008` in every real trade NPC's own
script, `data/event_scripts.s:1531-1551`), so this table is emitted as an
ARRAY, indexable directly, matching source's own `sIngameTrades[idx]`
rather than a name-keyed dict.

Only entries 4-12 (INGAME_TRADE_MR_MIME through INGAME_TRADE_SEEL) are ever
reachable from a Kanto/FRLG script — entries 0-3 (SEEDOT/PLUSLE/HORSEA/
MEOWTH) are RSE-only, confirmed via a full grep of every FRLG map script:
no FRLG script sets VAR_0x8008 to any of the four. Kept anyway, at zero
extra cost, matching this project's own "full extraction over selective"
precedent (`[M27B Step 4]`'s trainer-roster pull, `gen_trainer_data.py`'s
own both-region conversion) rather than dropping them.

⚠️ TWO ENTRIES (NIDORAN, NIDORINOA) ARE VERSION-GATED, `#if defined(FIRERED)
... #else ... #endif`. This project takes the `#else` (LeafGreen) branch —
the SAME choice `[M27K K-b]`'s own new-game-name-list already made, for the
same reason: `_PLAYER_BACK_PIC`/the overworld sprite are already Leaf, and
a game whose own player character is Leaf offering the FireRed-side content
first would be incoherent.

⚠️ FIELDS DELIBERATELY OMITTED, NOT FORGOTTEN: `otId`/`otName`/`otGender`/
`personality`/`sheen`/`mailNum`/`conditions` (contest stats). Checked
directly against every real corridor trade script's own text (none of the
8 FRLG NPCs ever buffer an OT name or reference mail/contest data anywhere
in their own dialogue) — these are load-bearing for the real link-trade
cinematic (`DoInGameTradeScene`, deferred to G3b) and for systems this
project does not model at all (mail, Pokéblocks/contests, Met info
display), not for anything G3a's own mechanics need. `friendship` is
likewise not stored here — source resets it to a FLAT 70 for every trade
(`TradeMons`, `src/trade.c:3104`), a constant, not per-entry data.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
REFERENCE = os.path.join(os.path.dirname(PROJECT), "reference", "pokeemerald_expansion")
TRADE_H = os.path.join(REFERENCE, "src", "data", "trade.h")
TRADE_CONST_H = os.path.join(REFERENCE, "include", "constants", "trade.h")
SPECIES_MAP = os.path.join(PROJECT, "data", "species_name_to_id.json")
ITEM_MAP = os.path.join(PROJECT, "data", "item_name_to_id.json")
OUT = os.path.join(PROJECT, "data", "ingame_trades.json")


def trade_id_order():
    """`enum InGameTradeID` in its own declared order — the array index each
    name resolves to, matching `VAR_0x8005`'s own runtime value."""
    text = open(TRADE_CONST_H, encoding="utf-8").read()
    m = re.search(r"enum InGameTradeID\s*\{(.*?)\};", text, re.S)
    if not m:
        sys.exit("enum InGameTradeID not found")
    names = []
    for line in m.group(1).splitlines():
        line = line.split("//")[0].strip().rstrip(",")
        if line:
            names.append(line)
    return names


def entry_blocks(text):
    """Yield (INGAME_TRADE_NAME, block_body) for each `[INGAME_TRADE_X] = {
    ... }` entry, brace-depth-tracked since `.ivs = {a,b,c,d,e,f}` also uses
    braces -- a naive "next closing brace" scan would stop there instead."""
    for m in re.finditer(r"\[INGAME_TRADE_(\w+)\]\s*=\s*\{", text):
        name = "INGAME_TRADE_" + m.group(1)
        start = m.end() - 1  # the opening '{' itself
        depth = 0
        i = start
        while i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    yield name, text[start + 1:i]
                    break
            i += 1


def resolve_version_branch(body):
    """`#if defined(FIRERED) ... #else ... #endif` -> the #else (LeafGreen)
    content, spliced back into the rest of the entry -- the gate can wrap
    the WHOLE body (NIDORAN/NIDORINOA) or just one trailing field
    (LICKITUNG's own `.requestedSpecies`), so this substitutes in place
    rather than discarding everything outside the matched span."""
    if "#if defined(FIRERED)" not in body:
        return body
    return re.sub(r"#if defined\(FIRERED\).*?#else(.*?)#endif",
            lambda m: m.group(1), body, flags=re.S)


def field(body, name, pattern):
    m = re.search(r"\." + name + r"\s*=\s*" + pattern, body)
    return m.group(1) if m else None


def parse_entry(body):
    nickname = field(body, "nickname", r'_\("([^"]+)"\)')
    species = field(body, "species", r"(SPECIES_\w+)")
    ivs_raw = field(body, "ivs", r"\{([^}]+)\}")
    ivs = [int(v.strip()) for v in ivs_raw.split(",")] if ivs_raw else None
    ability_num = field(body, "abilityNum", r"(\d+)")
    held_item = field(body, "heldItem", r"(ITEM_\w+)")
    requested_species = field(body, "requestedSpecies", r"(SPECIES_\w+)")
    missing = [k for k, v in {
        "nickname": nickname, "species": species, "ivs": ivs,
        "abilityNum": ability_num, "heldItem": held_item,
        "requestedSpecies": requested_species,
    }.items() if v is None]
    if missing:
        sys.exit("entry missing field(s) %r in block: %r" % (missing, body[:120]))
    return {
        "nickname": nickname,
        "species_const": species,
        "ivs": ivs,
        "ability_num": int(ability_num),
        "held_item_const": held_item,
        "requested_species_const": requested_species,
    }


def main():
    order = trade_id_order()
    species_map = json.load(open(SPECIES_MAP, encoding="utf-8"))
    item_map = json.load(open(ITEM_MAP, encoding="utf-8"))

    text = open(TRADE_H, encoding="utf-8").read()
    raw = {}
    for name, body in entry_blocks(text):
        raw[name] = parse_entry(resolve_version_branch(body))

    if set(raw.keys()) != set(order):
        sys.exit("parsed entries %r do not match enum order %r" % (sorted(raw), order))

    out = []
    unresolved = []
    for name in order:
        e = raw[name]
        species_dex = species_map.get(e["species_const"])
        requested_dex = species_map.get(e["requested_species_const"])
        held_id = 0 if e["held_item_const"] == "ITEM_NONE" else item_map.get(e["held_item_const"])
        if species_dex is None or requested_dex is None or held_id is None:
            unresolved.append((name, e["species_const"], e["requested_species_const"],
                    e["held_item_const"]))
            continue
        out.append({
            "constant": name,
            "nickname": e["nickname"],
            "species": species_dex,
            "ivs": e["ivs"],
            "ability_num": e["ability_num"],
            "held_item": held_id,
            "requested_species": requested_dex,
        })

    if unresolved:
        sys.exit("unresolvable constant(s): %r" % unresolved)

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, indent="\t")
        f.write("\n")

    frlg_start = order.index("INGAME_TRADE_MR_MIME")
    print("ingame trades : %s" % os.path.relpath(OUT, PROJECT))
    print("  entries     : %d (index 0-%d, matching VAR_0x8005's own value)"
            % (len(out), len(out) - 1))
    print("  FRLG-reachable : %d (index %d-%d)" % (len(order) - frlg_start,
            frlg_start, len(order) - 1))
    have_item = sum(1 for e in out if e["held_item"] > 0
            and os.path.exists(os.path.join(PROJECT, "data", "items",
                    "item_%04d.tres" % e["held_item"])))
    print("  held item has a real .tres: %d of %d" % (have_item,
            sum(1 for e in out if e["held_item"] > 0)))


if __name__ == "__main__":
    main()
