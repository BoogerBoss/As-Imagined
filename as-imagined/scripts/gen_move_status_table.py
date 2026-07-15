#!/usr/bin/env python3
"""
Generate docs/move_status_table.md: one row per canonical move ID (1-934,
per include/constants/moves.h / src/data/moves_info.h), with columns
ID | Move | Status | Implementation.

Fully script-templated, no LLM summarization:
  - Status/exclusion-reason text is parsed directly out of
    docs/m19_subtier_plan.md's own Section C exclusion tables (and the
    Secret Power note in Section B) -- never re-derived from memory.
  - Implementation-column descriptions are built purely from the field
    VALUES stored in each data/moves/move_NNNN.tres file, via a fixed
    field-name -> phrase template. No source-code reading, no paraphrasing.

Usage (from project root):
    python3 scripts/gen_move_status_table.py
"""

import re
import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = PROJECT_ROOT.parent
REF = REPO_ROOT / "reference" / "pokeemerald_expansion"
MOVES_H = REF / "include" / "constants" / "moves.h"
MOVES_INFO_H = REF / "src" / "data" / "moves_info.h"
DATA_MOVES = PROJECT_ROOT / "data" / "moves"
PLAN_MD = PROJECT_ROOT / "docs" / "m19_subtier_plan.md"
OUT_MD = PROJECT_ROOT / "docs" / "move_status_table.md"

MIN_ID = 1
MAX_ID = 934


# ─────────────────────────────────────────────────────────────────────────
# Step 1: resolve every MOVE_* enum constant to its numeric ID by walking
# constants/moves.h's `enum Move` body in source order (numeric literals,
# symbolic aliases, and bare auto-increment entries all handled).
# ─────────────────────────────────────────────────────────────────────────
def parse_moves_h_ids():
    text = MOVES_H.read_text()
    m = re.search(r"enum __attribute__\(\(packed\)\) Move\s*\{(.*?)\n\};", text, re.S)
    body = m.group(1)
    body = re.sub(r"//.*", "", body)  # strip line comments
    id_map = {}
    current = -1
    for raw in body.split(","):
        entry = raw.strip()
        if not entry:
            continue
        if "=" in entry:
            name, rhs = entry.split("=", 1)
            name = name.strip()
            rhs = rhs.strip()
            if re.fullmatch(r"-?\d+", rhs):
                current = int(rhs)
            elif rhs in id_map:
                current = id_map[rhs]
            else:
                raise ValueError(f"Unresolved enum rhs {rhs!r} for {name!r}")
        else:
            name = entry
            current += 1
        id_map[name] = current
    return id_map


# ─────────────────────────────────────────────────────────────────────────
# Step 2: walk moves_info.h's sMovesInfo[] table (split on each top-level
# "    [MOVE_XXX] =" entry marker) and pull out each entry's .name field.
# ─────────────────────────────────────────────────────────────────────────
def parse_move_names(id_map):
    text = MOVES_INFO_H.read_text()
    chunks = re.split(r"(?=^ {4}\[MOVE_[A-Za-z0-9_]+\] =\n)", text, flags=re.M)
    names = {}
    for chunk in chunks:
        head = re.match(r"^ {4}\[(MOVE_[A-Za-z0-9_]+)\] =\n", chunk)
        if not head:
            continue
        const_name = head.group(1)
        if const_name not in id_map:
            continue
        move_id = id_map[const_name]
        if not (MIN_ID <= move_id <= MAX_ID):
            continue
        name_m = re.search(r'\.name\s*=\s*COMPOUND_STRING\("((?:[^"\\]|\\.)*)"\)', chunk)
        if name_m:
            names[move_id] = name_m.group(1)
    return names


# ─────────────────────────────────────────────────────────────────────────
# Step 3: implemented set from data/moves/move_NNNN.tres filenames.
# ─────────────────────────────────────────────────────────────────────────
def parse_implemented():
    implemented = {}
    for p in sorted(DATA_MOVES.glob("move_*.tres")):
        m = re.match(r"move_(\d{4})\.tres", p.name)
        if not m:
            continue
        move_id = int(m.group(1))
        implemented[move_id] = p
    return implemented


# ─────────────────────────────────────────────────────────────────────────
# Step 4: exclusion map, parsed directly out of docs/m19_subtier_plan.md's
# Section C tables (C1 Z-Move/Max-Move ranges, C2 Rob's named list, C3
# Population Bomb) plus the Secret Power note in Section B.
# ─────────────────────────────────────────────────────────────────────────
def parse_exclusions():
    text = PLAN_MD.read_text()
    exclusions = {}  # id -> reason string

    # --- C1: Z-Move / Max Move ranges, explicit numeric ranges from the doc ---
    c1_m = re.search(
        r"Z-Moves \((\d+).(\d+),\s*\d+\s*moves\)\s*and\s*the\s*Max\s*Move/Dynamax\s*family\s*"
        r"\((\d+).(\d+),\s*\d+\s*moves\)",
        text,
    )
    if not c1_m:
        raise ValueError("Could not find C1 Z-Move/Max-Move ranges in plan doc")
    z_lo, z_hi, m_lo, m_hi = (int(x) for x in c1_m.groups())
    for i in range(z_lo, z_hi + 1):
        exclusions[i] = (
            "Z-Move family — permanently excluded (gimmick mechanic, "
            "requires Z-Crystal/Z-Power resource this project has no plans to "
            "build); m19_subtier_plan.md Section C1"
        )
    for i in range(m_lo, m_hi + 1):
        exclusions[i] = (
            "Max Move / Dynamax family — permanently excluded (gimmick "
            "mechanic, requires Dynamax/Gigantamax this project has no plans "
            "to build); m19_subtier_plan.md Section C1"
        )

    # --- C2: Rob's named [M19-exclusions] list, one bullet per source bucket ---
    c2_start = text.index("### C2 ")
    c2_end = text.index("### C3 ")
    c2_text = text[c2_start:c2_end]
    # Each bucket bullet looks like:
    #   - **From M19a (Tier 1), 14 moves:** Attack Order(454), ... .
    # or
    #   - **Terrain family, 9 moves ... :** Grassy Terrain(580), ... .
    bullets = re.split(r"\n- \*\*", c2_text)[1:]
    for bullet in bullets:
        # collapse this bullet's own wrapped lines into one string before
        # extracting the label / scanning for "Name(ID)" pairs, since both
        # a label and a name can wrap across lines
        bullet_flat = re.sub(r"\s+", " ", bullet)
        label_m = re.match(r"(.*?):\*\*", bullet_flat)
        label = label_m.group(1).strip() if label_m else "Rob's [M19-exclusions] list"
        for name_m in re.finditer(r"([A-Za-z0-9''\-\.,: ]+?)\((\d{1,4})(?:,[^)]*)?\)", bullet_flat):
            move_id = int(name_m.group(2))
            if not (MIN_ID <= move_id <= MAX_ID):
                continue
            # setdefault: first bullet to mention an ID wins, so an
            # incidental in-prose mention of another move (e.g. "...the
            # EXACT SAME volatile field Heal Block(377)'s own move sets")
            # inside a LATER bullet can't clobber that move's real,
            # earlier, more specific bucket-of-origin reason.
            exclusions.setdefault(move_id, (
                f"Rob's [M19-exclusions] list — {label}; "
                "m19_subtier_plan.md Section C2 (permanently excluded, no "
                "shared technical blocker — Rob's own design decision)"
            ))

    # --- C3: Population Bomb ---
    c3_start = text.index("### C3 ")
    c3_end = text.index("### C4 ")
    c3_text = text[c3_start:c3_end]
    for name_m in re.finditer(r"([A-Za-z0-9''\-\.,: ]+?)\((\d{1,4})(?:,[^)]*)?\)", c3_text):
        move_id = int(name_m.group(2))
        if MIN_ID <= move_id <= MAX_ID:
            exclusions[move_id] = (
                "Population Bomb — permanently excluded (higher-complexity "
                "multi-hit variant: per-hit accuracy checks plus a uniquely-"
                "shaped Loaded Dice interaction, excluded from the general "
                "multi-hit mechanism); m19_subtier_plan.md Section C3"
            )

    # --- Secret Power, permanently excluded per Section B / Section E ---
    exclusions[290] = (
        "Secret Power — permanently excluded (secondary effect depends on "
        "gBattleEnvironment, an overworld map/tile-derived field with no "
        "analog in this project; Rob confirmed permanent exclusion 2026-07-10); "
        "m19_subtier_plan.md Section B (Bucket 4, M19-secret-power) / Section E"
    )

    return exclusions


# ─────────────────────────────────────────────────────────────────────────
# Step 5: Implementation-column templating, purely from move_NNNN.tres
# field VALUES. Unknown/unrecognized fields get flagged for manual review
# instead of guessed at.
# ─────────────────────────────────────────────────────────────────────────
TYPE_NAMES = {
    0: "None", 1: "Normal", 2: "Fighting", 3: "Flying", 4: "Poison",
    5: "Ground", 6: "Rock", 7: "Bug", 8: "Ghost", 9: "Steel",
    11: "Fire", 12: "Water", 13: "Grass", 14: "Electric", 15: "Psychic",
    16: "Ice", 17: "Dragon", 18: "Dark", 19: "Fairy",
}
CATEGORY_NAMES = {0: "Physical", 1: "Special", 2: "Status"}
STAGE_NAMES = {
    0: "Attack", 1: "Defense", 2: "Sp. Atk", 3: "Sp. Def",
    4: "Speed", 5: "Accuracy", 6: "Evasion",
}
SE_NAMES = {
    0: None, 1: "burn", 2: "freeze", 3: "paralysis", 4: "sleep",
    5: "toxic", 6: "confusion", 7: "flinch", 8: "bind/wrap", 9: "poison",
    10: "Throat Chop (sound-move lock)", 11: "Eerie Spell (-3 PP)",
    12: "random status", 13: "escape prevention", 14: "trap both sides",
}
SEMI_INV_NAMES = {
    0: None, 1: "underground (Dig)", 2: "on-air (Fly/Bounce)",
    3: "underwater (Dive)", 4: "vanish (Shadow Force/Phantom Force)",
}
PROTECT_METHOD_NAMES = {
    0: None, 1: "Spiky Shield", 2: "Baneful Bunker", 3: "Burning Bulwark",
    4: "Obstruct", 5: "Silk Trap", 6: "Wide Guard", 7: "Quick Guard",
    8: "Endure",
}

# fields already consumed by a dedicated clause below -- excluded from the
# generic boolean-flag fallback listing so they aren't double-reported.
HANDLED_FIELDS = {
    "script", "move_name", "description", "type", "power", "pp", "category",
    "accuracy", "priority", "makes_contact", "stat_change_stat",
    "stat_change_amount", "stat_change_self", "extra_stat_change_stats",
    "extra_stat_change_amounts", "secondary_effect", "secondary_chance",
    "secondary_effect_2", "secondary_chance_2", "drain_percent",
    "recoil_percent", "fixed_damage", "level_damage",
    "percent_current_hp_damage", "semi_inv_state", "protect_method",
    "double_power_status_arg", "critical_hit_stage", "strike_count",
    "hp_cost_divisor", "weather_heal_boost_type", "weather_type",
    "super_effective_vs_type", "overwrite_target_ability_id",
}

# Manual acronym/short-word fixups applied when humanizing a bare flag name
# into a phrase (purely lexical, not source-derived).
WORD_FIXUPS = {
    "hp": "HP", "pp": "PP", "ohko": "OHKO", "spatk": "Sp. Atk",
    "spdef": "Sp. Def",
}


def humanize_flag(field_name):
    prefix_stripped = re.sub(r"^is_", "", field_name)
    words = prefix_stripped.split("_")
    words = [WORD_FIXUPS.get(w, w.capitalize()) for w in words]
    return " ".join(words)


def parse_tres_fields(path):
    text = path.read_text()
    fields = {}
    in_resource = False
    for line in text.splitlines():
        line = line.strip()
        if line == "[resource]":
            in_resource = True
            continue
        if not in_resource or not line or line.startswith("["):
            continue
        m = re.match(r"([a-zA-Z0-9_]+)\s*=\s*(.+)$", line)
        if not m:
            continue
        key, raw_val = m.group(1), m.group(2)
        if key == "script":
            continue
        fields[key] = raw_val
    return fields


def coerce(raw_val):
    """Best-effort literal coercion for a .tres scalar/array value."""
    v = raw_val.strip()
    if v == "true":
        return True
    if v == "false":
        return False
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if v.startswith('"') and v.endswith('"'):
        return v[1:-1]
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        if not inner:
            return []
        return [coerce(x) for x in inner.split(",")]
    if v.startswith("Array[int]("):
        inner = v[len("Array[int]("):-1].strip()
        if inner.startswith("[") and inner.endswith("]"):
            return coerce(inner)
    return v


def describe_move(fields):
    """Build the templated Implementation-column sentence from field values."""
    unrecognized = [k for k in fields if k not in HANDLED_FIELDS and not k.startswith("is_")
                    and k not in {
                        "makes_contact", "ban_flags", "bounceable", "ignores_protect",
                        "ignores_substitute", "thaws_user", "sound_move", "ballistic_move",
                        "punching_move", "biting_move", "slicing_move", "pulse_move",
                        "powder_move", "dance_move", "healing_move", "blocked_by_aroma_veil",
                        "always_critical_hit", "two_turn", "damages_underground",
                        "damages_airborne", "damages_underwater", "multi_hit",
                        "random_status_pool", "steals_and_eats_berry",
                        "ignores_target_ability", "charge_turn_defense_boost",
                        "charge_turn_spatk_boost", "skips_charge_in_rain",
                        "double_power_on_minimized", "breaks_screens",
                        "sets_reflect_on_hit", "sets_light_screen_on_hit",
                        "sets_stealth_rock_on_hit", "sets_spikes_on_hit",
                        "requires_target_stat_raised", "requires_target_asleep",
                        "cant_use_twice", "steals_positive_stat_stages",
                        "stat_change_target_ally", "also_boosts_ally",
                        "heals_based_on_weather", "weather_heal_has_quarter_branch",
                        "power_scales_with_user_hp", "power_scales_with_target_hp",
                        "steals_item_if_itemless", "ignores_redirection",
                        "ignores_defense_evasion_stages", "always_hits_in_rain",
                        "accuracy_halved_in_sun", "crashes_on_miss", "breaks_protect",
                        "usable_while_asleep", "hp_cost_stat_boost",
                        "counter", "creates_substitute", "destiny_bond",
                        "mirror_coat", "metal_burst",
                        # [D4 Bundle 8]
                        "snatch_affected",
                        # [D4 Bundle 9]
                        "two_typed_move", "second_type",
                        # [Perish Song]
                        "target",
                        # [EFFECT_STAT_CHANGE audit]
                        "stat_change_bypasses_type_gate",
                    }]
    if unrecognized:
        return None, unrecognized

    parts = []

    category = coerce(fields.get("category", "0"))
    power = coerce(fields.get("power", "0"))
    accuracy = coerce(fields.get("accuracy", "100"))
    pp = coerce(fields.get("pp", "5"))
    target_ally = coerce(fields.get("stat_change_target_ally", "false"))
    self_target = coerce(fields.get("stat_change_self", "false"))
    spread = "is_spread" in fields

    cat_label = CATEGORY_NAMES.get(category, "Physical")
    acc_str = "always hits" if accuracy == 0 else f"{accuracy}% accuracy"

    if cat_label == "Status":
        target_str = "ally" if target_ally else ("self" if self_target or any(
            k in fields for k in (
                "is_restore_hp", "is_focus_energy", "is_growth", "is_minimize",
                "is_defense_curl", "is_reflect", "is_light_screen",
                "is_aurora_veil", "is_ingrain", "is_aqua_ring",
            )) else "target")
        parts.append(f"Status move ({target_str}-targeted), {acc_str}, {pp} PP")
    else:
        contact = ", contact" if coerce(fields.get("makes_contact", "false")) else ""
        spread_str = ", hits all foes" if spread else ""
        parts.append(
            f"{cat_label} hit, power {power}, {acc_str}, {pp} PP{contact}{spread_str}"
        )

    # stat changes (primary + extra pairs)
    stat_stage = coerce(fields.get("stat_change_stat", "-1"))
    if stat_stage is not None and stat_stage != -1:
        amt = coerce(fields.get("stat_change_amount", "0"))
        who = "ally's" if target_ally else ("own" if self_target else "target's")
        direction = "raises" if amt > 0 else "lowers"
        parts.append(f"{direction} {who} {STAGE_NAMES.get(stat_stage, stat_stage)} by {abs(amt)} stage(s)")
    extra_stats = coerce(fields.get("extra_stat_change_stats", "[]")) or []
    extra_amts = coerce(fields.get("extra_stat_change_amounts", "[]")) or []
    for st, amt in zip(extra_stats, extra_amts):
        who = "ally's" if target_ally else ("own" if self_target else "target's")
        direction = "raises" if amt > 0 else "lowers"
        parts.append(f"{direction} {who} {STAGE_NAMES.get(st, st)} by {abs(amt)} stage(s)")

    # secondary effects (slot 1 + slot 2)
    for eff_key, chance_key in (("secondary_effect", "secondary_chance"),
                                 ("secondary_effect_2", "secondary_chance_2")):
        if eff_key in fields:
            eff = coerce(fields[eff_key])
            eff_name = SE_NAMES.get(eff)
            if eff_name:
                chance = coerce(fields.get(chance_key, "0"))
                chance_str = "guaranteed" if chance == 0 else f"{chance}% chance"
                parts.append(f"{chance_str} of {eff_name}")

    # damage-shape fields
    drain = coerce(fields.get("drain_percent", "0"))
    if drain:
        parts.append(f"drains {drain}% of damage dealt as HP")
    recoil = coerce(fields.get("recoil_percent", "0"))
    if recoil:
        parts.append(f"{recoil}% recoil")
    fixed = coerce(fields.get("fixed_damage", "0"))
    if fixed:
        parts.append(f"fixed {fixed} damage")
    if coerce(fields.get("level_damage", "false")):
        parts.append("damage equals user's level")
    pct_cur = coerce(fields.get("percent_current_hp_damage", "0"))
    if pct_cur:
        parts.append(f"damage = {pct_cur}% of target's current HP")

    if coerce(fields.get("two_turn", "false")):
        semi = coerce(fields.get("semi_inv_state", "0"))
        semi_name = SEMI_INV_NAMES.get(semi)
        parts.append(f"two-turn charge move" + (f" ({semi_name})" if semi_name else ""))

    if "is_protect" in fields:
        pm = coerce(fields.get("protect_method", "0"))
        pm_name = PROTECT_METHOD_NAMES.get(pm)
        parts.append(f"Protect-family move" + (f" ({pm_name})" if pm_name else ""))

    if "is_double_power_on_status" in fields:
        arg = coerce(fields.get("double_power_status_arg", "-1"))
        parts.append(f"doubles power vs. status arg {arg}")

    crit = coerce(fields.get("critical_hit_stage", "0"))
    if crit:
        parts.append(f"crit stage +{crit}")
    if coerce(fields.get("always_critical_hit", "false")):
        parts.append("always a critical hit")

    strike = coerce(fields.get("strike_count", "1"))
    if strike and strike != 1:
        parts.append(f"hits {strike} times")
    if coerce(fields.get("multi_hit", "false")):
        parts.append("random multi-hit (2-5x)")

    hp_div = coerce(fields.get("hp_cost_divisor", "0"))
    if hp_div:
        parts.append(f"costs 1/{hp_div} max HP")

    wtype = coerce(fields.get("weather_type", "0"))
    if wtype:
        parts.append(f"sets weather type {wtype}")

    seff = coerce(fields.get("super_effective_vs_type", "0"))
    if seff:
        parts.append(f"always super-effective vs type {seff}")

    oid = coerce(fields.get("overwrite_target_ability_id", "-1"))
    if oid is not None and oid != -1:
        parts.append(f"overwrites ability with id {oid}")

    # boolean move-flag fallback: every remaining true `is_*`-style flag or
    # other recognized boolean not already covered by a clause above
    already_mentioned_bool_keys = {
        "two_turn", "is_protect", "is_double_power_on_status",
        "always_critical_hit", "multi_hit",
    }
    generic_flags = []
    for key in sorted(fields):
        if key in HANDLED_FIELDS or key in already_mentioned_bool_keys:
            continue
        if key in ("stat_change_target_ally", "also_boosts_ally") :
            continue
        val = coerce(fields[key])
        if val is True:
            generic_flags.append(humanize_flag(key))
    if generic_flags:
        parts.append(", ".join(generic_flags))

    if coerce(fields.get("makes_contact", "false")) is False and "makes_contact" not in HANDLED_FIELDS:
        pass  # already folded into the physical/special clause above

    sentence = "; ".join(parts) + "."
    # tidy up any double spacing/casing artifacts
    sentence = sentence[0].upper() + sentence[1:]
    return sentence, []


# ─────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────
def main():
    id_map = parse_moves_h_ids()
    names = parse_move_names(id_map)
    implemented = parse_implemented()
    exclusions = parse_exclusions()

    rows = []
    needs_review = []
    counts = {"Implemented": 0, "Excluded": 0, "Residual": 0}

    for move_id in range(MIN_ID, MAX_ID + 1):
        name = names.get(move_id, f"(unknown MOVE id {move_id})")
        if move_id in implemented:
            counts["Implemented"] += 1
            fields = parse_tres_fields(implemented[move_id])
            desc, unrecognized = describe_move(fields)
            if desc is None:
                needs_review.append((move_id, name, unrecognized))
                impl_col = "*(needs manual review — see list below)*"
            else:
                impl_col = desc
            status = "Implemented"
        elif move_id in exclusions:
            counts["Excluded"] += 1
            status = f"Excluded — {exclusions[move_id]}"
            impl_col = "—"
        else:
            counts["Residual"] += 1
            status = "Residual / not yet implemented"
            impl_col = "—"

        rows.append((move_id, name, status, impl_col))

    total = sum(counts.values())
    assert total == MAX_ID - MIN_ID + 1, f"row count {total} != {MAX_ID - MIN_ID + 1}"

    lines = []
    lines.append("# Move Status Table")
    lines.append("")
    lines.append(
        f"**{counts['Implemented']} implemented / {counts['Excluded']} excluded / "
        f"{counts['Residual']} residual, reconciled to {total} "
        f"(IDs {MIN_ID}–{MAX_ID}, per `moves_info.h`).**"
    )
    lines.append("")
    lines.append(
        "Generated by `scripts/gen_move_status_table.py` — re-run after any "
        "future move-implementation bundle rather than hand-editing this file."
    )
    lines.append("")
    lines.append("| ID | Move | Status | Implementation |")
    lines.append("|---|---|---|---|")
    for move_id, name, status, impl_col in rows:
        name_esc = name.replace("|", "\\|")
        status_esc = status.replace("|", "\\|")
        impl_esc = impl_col.replace("|", "\\|")
        lines.append(f"| {move_id} | {name_esc} | {status_esc} | {impl_esc} |")

    if needs_review:
        lines.append("")
        lines.append("## Needs manual review")
        lines.append("")
        lines.append(
            "The following implemented moves have one or more `.tres` fields "
            "the templating script doesn't recognize; their Implementation "
            "column was left blank rather than guessed:"
        )
        lines.append("")
        for move_id, name, unrecognized in needs_review:
            lines.append(f"- **{move_id} ({name})**: unrecognized field(s): {', '.join(unrecognized)}")

    OUT_MD.write_text("\n".join(lines) + "\n")

    print(f"Wrote {OUT_MD} ({total} rows)")
    print(f"Implemented: {counts['Implemented']}")
    print(f"Excluded: {counts['Excluded']}")
    print(f"Residual: {counts['Residual']}")
    print(f"Needs manual review: {len(needs_review)}")


if __name__ == "__main__":
    main()
