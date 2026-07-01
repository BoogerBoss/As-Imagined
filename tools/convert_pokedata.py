#!/usr/bin/env python3
"""
M15 Data Pipeline: convert_pokedata.py

Extracts JSON files from the pokeemerald_expansion reference source:
  pokemon.json       — all 386 Gen III Pokémon (Dex #1–386), now includes growth_rate
  moves.json         — all moves in the expansion
  learnsets.json     — level-up learnsets per Pokémon
  items.json         — items with id, name, price, pocket, hold_effect, hold_effect_param, description
  evolutions.json    — per-dex evolution lists (method, condition, target_dex)
  tmhm_map.json      — TM01–TM50 / HM01–HM08 → move_id, move_name
  exp_curves.json    — pre-computed EXP tables for all 6 growth curves, levels 0–100

Output: as-imagined/data/*.json

Sources:
  include/constants/species.h       — SPECIES_* enum
  include/constants/pokedex.h       — NATIONAL_DEX_* enum
  include/constants/abilities.h     — ABILITY_* enum
  include/constants/moves.h         — MOVE_* enum
  include/constants/battle_move_effects.h — EFFECT_* enum
  include/constants/pokemon.h       — TYPE_*, EGG_GROUP_*, GROWTH_* enums
  include/constants/items.h         — ITEM_* enum (numeric IDs)
  include/constants/hold_effects.h  — HOLD_EFFECT_* enum
  include/constants/tms_hms.h       — FOREACH_TM / FOREACH_HM lists
  src/data/pokemon/species_info/gen_{1,2,3}_families.h
  src/data/moves_info.h
  src/data/items.h                  — gItemsInfo[] struct array
  src/data/pokemon/level_up_learnsets/gen_{1,2,3}.h
  src/data/pokemon/experience_tables.h — formulas verified; computed in Python
"""

import json
import os
import re
import sys

REF  = os.path.join(os.path.dirname(__file__), "..", "reference", "pokeemerald_expansion")
OUT  = os.path.join(os.path.dirname(__file__), "..", "as-imagined", "data")

GEN_LATEST = 9  # all B_/P_/C_ config flags resolve to GEN_LATEST

# ── Type IDs (from include/constants/pokemon.h enum) ──────────────────────────
TYPE_IDS = {
    "TYPE_NONE": 0, "TYPE_NORMAL": 1, "TYPE_FIGHTING": 2, "TYPE_FLYING": 3,
    "TYPE_POISON": 4, "TYPE_GROUND": 5, "TYPE_ROCK": 6, "TYPE_BUG": 7,
    "TYPE_GHOST": 8, "TYPE_STEEL": 9, "TYPE_MYSTERY": 10, "TYPE_FIRE": 11,
    "TYPE_WATER": 12, "TYPE_GRASS": 13, "TYPE_ELECTRIC": 14,
    "TYPE_PSYCHIC": 15, "TYPE_ICE": 16, "TYPE_DRAGON": 17,
    "TYPE_DARK": 18, "TYPE_FAIRY": 19, "TYPE_STELLAR": 20,
}

EGG_GROUP_IDS = {
    "EGG_GROUP_NONE": 0, "EGG_GROUP_MONSTER": 1, "EGG_GROUP_WATER_1": 2,
    "EGG_GROUP_BUG": 3, "EGG_GROUP_FLYING": 4, "EGG_GROUP_FIELD": 5,
    "EGG_GROUP_FAIRY": 6, "EGG_GROUP_GRASS": 7, "EGG_GROUP_HUMAN_LIKE": 8,
    "EGG_GROUP_WATER_3": 9, "EGG_GROUP_MINERAL": 10, "EGG_GROUP_AMORPHOUS": 11,
    "EGG_GROUP_WATER_2": 12, "EGG_GROUP_DITTO": 13, "EGG_GROUP_DRAGON": 14,
    "EGG_GROUP_NO_EGGS_DISCOVERED": 15,
}

CATEGORY_IDS = {
    "DAMAGE_CATEGORY_PHYSICAL": 0,
    "DAMAGE_CATEGORY_SPECIAL":  1,
    "DAMAGE_CATEGORY_STATUS":   2,
    "DAMAGE_CATEGORY_NONE":     2,
}

# MoveData SE_* constants (from move_data.gd / gen_moves.py)
MOVE_EFFECT_TO_SE = {
    "MOVE_EFFECT_NONE":               0,
    "MOVE_EFFECT_SLEEP":              4,
    "MOVE_EFFECT_POISON":             2,   # plain poison → map to SE_FREEZE slot; note in loader
    "MOVE_EFFECT_BURN":               1,
    "MOVE_EFFECT_FREEZE":             2,
    "MOVE_EFFECT_FREEZE_OR_FROSTBITE": 2,
    "MOVE_EFFECT_FROSTBITE":          2,
    "MOVE_EFFECT_PARALYSIS":          3,
    "MOVE_EFFECT_TOXIC":              5,
    "MOVE_EFFECT_CONFUSION":          6,
    "MOVE_EFFECT_FLINCH":             7,
    "MOVE_EFFECT_TRI_ATTACK":         0,   # complex; skip
}

# Semi-invulnerable state mapping (state name → SEMI_INV_* constant in MoveData)
SEMI_INV_STATES = {
    "STATE_UNDERGROUND": 1,
    "STATE_ON_AIR":      2,
    "STATE_UNDERWATER":  3,
}

# Effects that imply two_turn=True
TWO_TURN_EFFECTS = {
    "EFFECT_TWO_TURNS_ATTACK",
    "EFFECT_SEMI_INVULNERABLE",
    "EFFECT_SOLAR_BEAM",
    "EFFECT_SKY_DROP",
}

# Effects that set special MoveData flags
EFFECT_FLAG_MAP = {
    "EFFECT_SUBSTITUTE":  "creates_substitute",
    "EFFECT_PROTECT":     "is_protect",
    "EFFECT_BATON_PASS":  "is_baton_pass",
    "EFFECT_METRONOME":   "is_metronome",
    "EFFECT_BIDE":        "is_bide",
    "EFFECT_DESTINY_BOND": "destiny_bond",
    "EFFECT_DISABLE":     "is_disable",
    "EFFECT_ENCORE":      "is_encore",
    "EFFECT_ROAR":        "is_roar",
    "EFFECT_HELPING_HAND": "is_helping_hand",
    "EFFECT_FOLLOW_ME":   "is_follow_me",
    "EFFECT_COUNTER":     "counter",
    "EFFECT_MIRROR_COAT": "mirror_coat",
    "EFFECT_REFLECT_DAMAGE": None,   # resolved by category
    "EFFECT_LEVEL_DAMAGE": "level_damage",
    "EFFECT_FIXED_HP_DAMAGE": None,  # fixed_damage comes from argument
    "EFFECT_RECOIL":      None,      # recoil_percent from argument
    "EFFECT_ABSORB":      None,      # drain_percent from argument
    "EFFECT_DREAM_EATER": None,
}

# Ban flags from move_data.gd BAN_* constants
BAN_FLAGS = {
    "gravityBanned":      1 << 0,
    "mirrorMoveBanned":   1 << 1,
    "meFirstBanned":      1 << 2,
    "mimicBanned":        1 << 3,
    "metronomeBanned":    1 << 4,
    "copycatBanned":      1 << 5,
    "assistBanned":       1 << 6,
    "sleepTalkBanned":    1 << 7,
    "instructBanned":     1 << 8,
    "encoreBanned":       1 << 9,
    "parentalBondBanned": 1 << 10,
    "skyBattleBanned":    1 << 11,
    "sketchBanned":       1 << 12,
    "dampBanned":         1 << 13,
}

# Stat field name in additionalEffects → STAGE_* index in MoveData/BattlePokemon
STAT_FIELD_TO_INDEX = {
    "attack":   0,
    "defense":  1,
    "spAtk":    2,
    "spDef":    3,
    "speed":    4,
    "accuracy": 5,
    "evasion":  6,
}

# ── New constants ─────────────────────────────────────────────────────────────

# Bag pocket enum (include/constants/item.h)
POCKET_NAMES = {
    "POCKET_ITEMS":     "items",
    "POCKET_POKE_BALLS": "poke_balls",
    "POCKET_TM_HM":     "tm_hm",
    "POCKET_BERRIES":   "berries",
    "POCKET_KEY_ITEMS": "key_items",
    "POCKET_DUMMY":     "dummy",
    "POCKETS_COUNT":    "dummy",
}

# Growth rate name strings
# Source: include/constants/pokemon.h enum (values 0–5)
GROWTH_RATE_NAMES = {
    "GROWTH_MEDIUM_FAST": "MediumFast",
    "GROWTH_ERRATIC":      "Erratic",
    "GROWTH_FLUCTUATING":  "Fluctuating",
    "GROWTH_MEDIUM_SLOW":  "MediumSlow",
    "GROWTH_FAST":         "Fast",
    "GROWTH_SLOW":         "Slow",
}

# Evolution method name strings
EVO_METHOD_NAMES = {
    "EVO_LEVEL":            "level_up",
    "EVO_TRADE":            "trade",
    "EVO_ITEM":             "item",
    "EVO_LEVEL_BATTLE_ONLY": "level_up_battle",
    "EVO_BATTLE_END":       "battle_end",
    "EVO_SPIN":             "spin",
    "EVO_SCRIPT_TRIGGER":   "script",
}

# TM01–TM50 move name suffixes (from include/constants/tms_hms.h :: FOREACH_TM)
TM_MOVES = [
    'FOCUS_PUNCH', 'DRAGON_CLAW', 'WATER_PULSE', 'CALM_MIND', 'ROAR',
    'TOXIC', 'HAIL', 'BULK_UP', 'BULLET_SEED', 'HIDDEN_POWER',
    'SUNNY_DAY', 'TAUNT', 'ICE_BEAM', 'BLIZZARD', 'HYPER_BEAM',
    'LIGHT_SCREEN', 'PROTECT', 'RAIN_DANCE', 'GIGA_DRAIN', 'SAFEGUARD',
    'FRUSTRATION', 'SOLAR_BEAM', 'IRON_TAIL', 'THUNDERBOLT', 'THUNDER',
    'EARTHQUAKE', 'RETURN', 'DIG', 'PSYCHIC', 'SHADOW_BALL',
    'BRICK_BREAK', 'DOUBLE_TEAM', 'REFLECT', 'SHOCK_WAVE', 'FLAMETHROWER',
    'SLUDGE_BOMB', 'SANDSTORM', 'FIRE_BLAST', 'ROCK_TOMB', 'AERIAL_ACE',
    'TORMENT', 'FACADE', 'SECRET_POWER', 'REST', 'ATTRACT',
    'THIEF', 'STEEL_WING', 'SKILL_SWAP', 'SNATCH', 'OVERHEAT',
]

# HM01–HM08 move name suffixes (from include/constants/tms_hms.h :: FOREACH_HM)
HM_MOVES = ['CUT', 'FLY', 'SURF', 'STRENGTH', 'FLASH', 'ROCK_SMASH', 'WATERFALL', 'DIVE']


# ── Utility functions ─────────────────────────────────────────────────────────

def _read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def _eval_gen_cond(cond_text):
    """
    Evaluate a preprocessor condition involving GEN comparisons.
    Assumes all B_/P_/C_/I_ config flags == GEN_LATEST == 9.
    Returns True or False.
    """
    text = cond_text.strip()
    # Replace GEN_N constants with their numeric values
    for n in range(9, 0, -1):
        text = text.replace(f"GEN_{n}", str(n))
    text = text.replace("GEN_LATEST", str(GEN_LATEST))
    # Replace all config flags (B_xxx, P_xxx, C_xxx, I_xxx) with GEN_LATEST
    text = re.sub(r'\b[BPCI]_[A-Z_0-9]+\b', str(GEN_LATEST), text)
    # Replace remaining identifier words with 1 (truthy) — P_FAMILY_xxx etc.
    text = re.sub(r'\b[A-Z_][A-Z_0-9]*\b', "1", text)
    # Replace C logical operators
    text = text.replace("&&", " and ").replace("||", " or ").replace("!", " not ")
    try:
        return bool(eval(text))  # noqa: S307 — trusted internal data only
    except Exception:
        return True  # default: include


def preprocess(text):
    """
    Strip #if/#elif/#else/#endif blocks in C text, keeping only the
    GEN_LATEST-applicable code.  Does NOT handle nested #if inside macro
    bodies or complex conditional expressions involving defined().
    """
    lines = text.split("\n")
    out = []
    # Stack: list of booleans. True = current block is active.
    stack = [True]      # outer level is always active
    taken = [True]      # whether any branch at this level was taken

    for line in lines:
        stripped = line.strip()

        m_if = re.match(r"^#\s*if\b(.+)", stripped)
        m_elif = re.match(r"^#\s*elif\b(.+)", stripped)
        m_else = re.match(r"^#\s*else\b", stripped)
        m_endif = re.match(r"^#\s*endif\b", stripped)
        m_ifdef = re.match(r"^#\s*ifdef\b\s+(\S+)", stripped)
        m_ifndef = re.match(r"^#\s*ifndef\b\s+(\S+)", stripped)

        if m_if:
            cond = _eval_gen_cond(m_if.group(1)) and stack[-1]
            stack.append(cond)
            taken.append(cond)
        elif m_ifdef:
            # #ifdef GUARD_xxx — treat as True (include guards, family guards)
            cond = stack[-1]  # assume True when parent active
            stack.append(cond)
            taken.append(cond)
        elif m_ifndef:
            # #ifndef GUARD_xxx — treat as False (include guard body suppressed)
            # Actually for inclusion guards we want to include the body,
            # so treat #ifndef as True for content purposes
            cond = stack[-1]
            stack.append(cond)
            taken.append(cond)
        elif m_elif:
            # If a previous branch was taken, disable this one
            if taken[-1]:
                stack[-1] = False
            else:
                cond = _eval_gen_cond(m_elif.group(1)) and stack[-2]
                stack[-1] = cond
                if cond:
                    taken[-1] = True
        elif m_else:
            # Activate #else only if no previous branch was taken
            stack[-1] = (not taken[-1]) and stack[-2]
        elif m_endif:
            if len(stack) > 1:
                stack.pop()
                taken.pop()
        else:
            if stack[-1]:
                out.append(line)

    return "\n".join(out)


def parse_c_enum(text):
    """
    Parse all enum values in a C source file/header.
    Returns a dict: name -> int value.
    Handles sequential auto-increment and explicit `= N` assignments.
    Also handles aliases like `FOO = BAR,`.
    """
    values = {}
    # Find enum bodies
    for enum_body in re.finditer(r'enum\b[^{]*\{([^}]*)\}', text, re.DOTALL):
        body = enum_body.group(1)
        # Remove comments
        body = re.sub(r'//[^\n]*', '', body)
        body = re.sub(r'/\*.*?\*/', '', body, flags=re.DOTALL)
        counter = 0
        for entry in re.findall(r'([A-Z_][A-Z0-9_]*)\s*(?:=\s*([^,\n]+))?\s*,?', body):
            name, val_expr = entry
            if not name:
                continue
            if val_expr:
                val_expr = val_expr.strip()
                # Try plain int (hex or decimal)
                try:
                    counter = int(val_expr, 0)
                except ValueError:
                    # May be a reference to another name
                    counter = values.get(val_expr, counter)
            values[name] = counter
            counter += 1
    return values


def _resolve_ternary(expr):
    """
    Evaluate simple ternary expressions like:
      'B_UPDATED_MOVE_DATA >= GEN_4 ? 90 : 70'
    Returns the resolved string value, or the original expr if not a ternary.
    """
    expr = expr.strip()
    # Match  CONDITION ? TRUE_VAL : FALSE_VAL
    m = re.match(r'^(.+?)\s*\?\s*(.+?)\s*:\s*(.+)$', expr, re.DOTALL)
    if not m:
        return expr
    cond_text = m.group(1).strip()
    true_val  = m.group(2).strip()
    false_val = m.group(3).strip()

    # Evaluate the condition
    cond = cond_text
    for n in range(9, 0, -1):
        cond = cond.replace(f"GEN_{n}", str(n))
    cond = cond.replace("GEN_LATEST", str(GEN_LATEST))
    cond = re.sub(r'\b[BPCI]_[A-Z_0-9]+\b', str(GEN_LATEST), cond)
    cond = re.sub(r'\b[A-Z_][A-Z_0-9]*\b', "1", cond)
    cond = cond.replace("&&", " and ").replace("||", " or ").replace("!", " not ")
    try:
        result = bool(eval(cond))  # noqa: S307
    except Exception:
        result = True

    chosen = true_val if result else false_val
    # Recursively resolve nested ternaries
    return _resolve_ternary(chosen)


def _parse_int(expr, enum_map=None):
    """
    Parse an expression to an int. Handles:
    - Plain integers (decimal or hex)
    - Named constants from enum_map
    - Simple ternary expressions
    - PERCENT_FEMALE(n) macro
    - Arithmetic like N + 1
    """
    if expr is None:
        return None
    expr = str(expr).strip()

    # Resolve ternaries first
    resolved = _resolve_ternary(expr)

    # Try plain int
    try:
        return int(resolved, 0)
    except (ValueError, TypeError):
        pass

    # PERCENT_FEMALE(n) macro
    m = re.match(r'PERCENT_FEMALE\s*\(\s*([0-9.]+)\s*\)', resolved)
    if m:
        pct = float(m.group(1))
        return min(254, int((pct * 255) / 100))

    # Named constant
    if enum_map and resolved in enum_map:
        return enum_map[resolved]

    # MON_GENDERLESS / MON_MALE / MON_FEMALE
    if resolved == "MON_GENDERLESS":
        return 255
    if resolved == "MON_MALE":
        return 0
    if resolved == "MON_FEMALE":
        return 254

    # STANDARD_FRIENDSHIP
    if "STANDARD_FRIENDSHIP" in resolved:
        return 50  # GEN_8+ value

    # Simple arithmetic after resolving names
    if enum_map:
        for name, val in enum_map.items():
            resolved = re.sub(r'\b' + re.escape(name) + r'\b', str(val), resolved)
    # Apply gen-constant substitution so that expressions like
    # "B_UPDATED_MOVE_DATA >= GEN_3" evaluate correctly (→ int(True) = 1).
    for n in range(9, 0, -1):
        resolved = resolved.replace(f"GEN_{n}", str(n))
    resolved = resolved.replace("GEN_LATEST", str(GEN_LATEST))
    resolved = re.sub(r'\b[BPCI]_[A-Z_0-9]+\b', str(GEN_LATEST), resolved)
    resolved = resolved.replace("&&", " and ").replace("||", " or ")
    try:
        return int(eval(resolved))  # noqa: S307
    except Exception:
        return None


def _strip_comments(text):
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    return text


def extract_struct_blocks(text, label_re):
    """
    Find all [LABEL] = { ... } blocks where LABEL matches label_re.
    Returns list of (label_str, block_content_str).
    """
    blocks = []
    pattern = re.compile(r'\[\s*(' + label_re + r')\s*\]\s*=\s*\{')
    for match in pattern.finditer(text):
        label = match.group(1)
        start = match.end()
        depth = 1
        i = start
        while i < len(text) and depth > 0:
            c = text[i]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            i += 1
        content = text[start:i - 1]
        blocks.append((label, content))
    return blocks


def _field_value(content, field_name):
    """
    Extract the raw value string for a field like `.field_name = VALUE`.
    Handles nested parentheses and braces (e.g. MON_TYPES(A, B), {A, B, C}).
    Returns the raw string or None.
    """
    pattern = re.compile(r'\.' + re.escape(field_name) + r'\s*=\s*')
    m = pattern.search(content)
    if not m:
        return None
    start = m.end()
    i = start
    paren = 0
    brace = 0
    while i < len(content):
        c = content[i]
        if c == '(':
            paren += 1
        elif c == ')':
            paren -= 1
            if paren < 0:
                break  # unmatched closing paren — stop here
        elif c == '{':
            brace += 1
        elif c == '}':
            brace -= 1
            if brace < 0:
                break  # unmatched closing brace — stop here
        elif c in (',', '\n') and paren == 0 and brace == 0:
            break
        i += 1
    return content[start:i].strip().rstrip(',').strip()


def _field_bool(content, field_name):
    """Extract a boolean flag (TRUE/FALSE or B_xxx >= GEN_Y style)."""
    raw = _field_value(content, field_name)
    if raw is None:
        return False
    raw = _resolve_ternary(raw)
    return raw.strip().upper() in ("TRUE", "1")


def _field_int(content, field_name, enum_map=None, default=0):
    raw = _field_value(content, field_name)
    if raw is None:
        return default
    v = _parse_int(raw, enum_map)
    return v if v is not None else default


# ── New utility helpers ───────────────────────────────────────────────────────

def _join_string_literals(text):
    """Extract and join all C string literals from a text block."""
    parts = re.findall(r'"([^"]*)"', text)
    return ''.join(parts)


def _extract_named_strings(text):
    """
    Pre-scan C source for named u8 string arrays:
      static const u8 sXxxDesc[] = _("..." "...");
      const u8 gXxxName[]        = _("...");
    Returns dict: {var_name: joined_string_content}
    """
    named = {}
    for m in re.finditer(
        r'(?:static\s+)?const\s+u8\s+(\w+)\s*\[\s*\]\s*=\s*_?\s*\(([^;]+)\)\s*;',
        text, re.DOTALL
    ):
        var_name = m.group(1)
        raw_content = m.group(2)
        named[var_name] = _join_string_literals(raw_content)
    return named


def _extract_item_string(raw, named_strings):
    """
    Resolve an item name or description field value to a plain string.
    Handles: ITEM_NAME("..."), COMPOUND_STRING("..."), sXxxDesc, "..." bare.
    """
    if raw is None:
        return ""
    raw = raw.strip()

    # ITEM_NAME("...")
    m = re.match(r'ITEM_NAME\s*\(\s*"([^"]+)"\s*\)', raw)
    if m:
        return m.group(1)

    # COMPOUND_STRING(...)
    if raw.startswith('COMPOUND_STRING'):
        return _join_string_literals(raw)

    # Named reference (e.g., sFullHealDesc, gQuestionMarksItemName)
    if raw in named_strings:
        return named_strings[raw]

    # Bare quoted string
    m = re.match(r'"([^"]*)"', raw)
    if m:
        return m.group(1)

    return raw


# ── Species parsing ───────────────────────────────────────────────────────────

def parse_species_info(gen_files, species_ids, nat_dex_ids, ability_ids):
    """
    Parse gen_1/2/3_families.h files and return a list of species dicts.
    Filters to National Dex #1–386, deduplicates by dex number (first wins).
    """
    results = {}  # nat_dex_num -> species dict

    for filepath in gen_files:
        raw = _read(filepath)
        text = preprocess(raw)
        text = _strip_comments(text)

        # Also collect local #define macros (e.g. CHARIZARD_SP_ATK)
        local_defs = {}
        for m in re.finditer(r'#\s*define\s+([A-Z_][A-Z0-9_]*)\s+\(([^)]+)\)', raw):
            name, expr = m.group(1), m.group(2)
            val = _parse_int(expr, {**local_defs, **ability_ids, **nat_dex_ids})
            if val is not None:
                local_defs[name] = val

        combined_enum = {**species_ids, **nat_dex_ids, **ability_ids, **local_defs}

        blocks = extract_struct_blocks(text, r'SPECIES_\w+')
        for label, content in blocks:
            # Determine natDexNum
            nat_raw = _field_value(content, 'natDexNum')
            if nat_raw is None:
                continue
            nat_raw = nat_raw.strip()
            # Could be NATIONAL_DEX_BULBASAUR or a number
            nat_num = nat_dex_ids.get(nat_raw)
            if nat_num is None:
                nat_num = _parse_int(nat_raw, combined_enum)
            if nat_num is None or not (1 <= nat_num <= 386):
                continue

            # Only keep first entry per dex number (base form)
            if nat_num in results:
                continue

            species = {"dex": nat_num}

            # Species name
            name_raw = _field_value(content, 'speciesName')
            if name_raw:
                m = re.search(r'_\(\s*"([^"]+)"\s*\)', name_raw)
                if m:
                    species["name"] = m.group(1)
                else:
                    species["name"] = name_raw.strip('"').strip()
            else:
                species["name"] = label.replace("SPECIES_", "").replace("_", " ").title()

            # Base stats
            species["base_hp"]    = _field_int(content, 'baseHP',        combined_enum)
            species["base_atk"]   = _field_int(content, 'baseAttack',    combined_enum)
            species["base_def"]   = _field_int(content, 'baseDefense',   combined_enum)
            species["base_spa"]   = _field_int(content, 'baseSpAttack',  combined_enum)
            species["base_spd"]   = _field_int(content, 'baseSpDefense', combined_enum)
            species["base_spe"]   = _field_int(content, 'baseSpeed',     combined_enum)

            # Types — MON_TYPES(TYPE_X) or MON_TYPES(TYPE_X, TYPE_Y)
            types_raw = _field_value(content, 'types')
            if types_raw:
                inner = re.sub(r'^MON_TYPES\s*\(', '', types_raw).rstrip(')')
                type_tokens = [t.strip() for t in inner.split(',')]
                type1 = TYPE_IDS.get(type_tokens[0], 0)
                type2 = TYPE_IDS.get(type_tokens[1], type1) if len(type_tokens) > 1 else type1
                species["types"] = [type1, type2]
            else:
                species["types"] = [0, 0]

            # Catch rate
            species["catch_rate"] = _field_int(content, 'catchRate', combined_enum, 255)

            # Base friendship
            friend_raw = _field_value(content, 'friendship')
            if friend_raw and 'STANDARD_FRIENDSHIP' in friend_raw:
                species["base_friendship"] = 50
            else:
                species["base_friendship"] = _field_int(content, 'friendship', combined_enum, 70)

            # Gender ratio (genderRatio field in source)
            gender_raw = _field_value(content, 'genderRatio')
            if gender_raw is None:
                species["gender_ratio"] = 127  # 50/50
            else:
                gval = _parse_int(gender_raw, combined_enum)
                species["gender_ratio"] = gval if gval is not None else 127

            # Egg groups — MON_EGG_GROUPS(EGG_GROUP_X) or MON_EGG_GROUPS(EGG_GROUP_X, EGG_GROUP_Y)
            egg_raw = _field_value(content, 'eggGroups')
            if egg_raw:
                inner = re.sub(r'^MON_EGG_GROUPS\s*\(', '', egg_raw).rstrip(')')
                eg_tokens = [t.strip() for t in inner.split(',')]
                eg1 = EGG_GROUP_IDS.get(eg_tokens[0], 0)
                eg2 = EGG_GROUP_IDS.get(eg_tokens[1], eg1) if len(eg_tokens) > 1 else eg1
                species["egg_groups"] = [eg1, eg2]
            else:
                species["egg_groups"] = [0, 0]

            # Abilities — .abilities = { ABILITY_X, ABILITY_Y, ABILITY_Z }
            abilities_raw = _field_value(content, 'abilities')
            if abilities_raw:
                inner = abilities_raw.strip().strip('{}')
                ab_tokens = [t.strip() for t in inner.split(',')]
                ability_list = []
                for tok in ab_tokens[:3]:
                    tok = tok.strip()
                    aid = ability_ids.get(tok, _parse_int(tok) or 0)
                    ability_list.append(aid)
                while len(ability_list) < 3:
                    ability_list.append(0)
                species["ability1"]  = ability_list[0]
                species["ability2"]  = ability_list[1]
                species["ability_h"] = ability_list[2]
            else:
                species["ability1"]  = 0
                species["ability2"]  = 0
                species["ability_h"] = 0

            # Held items (common and rare wild held items)
            item_common = _field_value(content, 'itemCommon')
            item_rare   = _field_value(content, 'itemRare')
            species["item_common"] = item_common.strip() if item_common else None
            species["item_rare"]   = item_rare.strip()   if item_rare   else None

            # Growth rate (M15 Task 4a addition)
            # Source: include/constants/pokemon.h enum GROWTH_MEDIUM_FAST=0 ... GROWTH_SLOW=5
            growth_raw = _field_value(content, 'growthRate')
            species["growth_rate"] = GROWTH_RATE_NAMES.get(growth_raw, "MediumFast") if growth_raw else "MediumFast"

            # Learnset variable name (for linking with learnsets)
            ls_raw = _field_value(content, 'levelUpLearnset')
            species["_learnset_var"] = ls_raw.strip() if ls_raw else None

            results[nat_num] = species

    # ── Fallback: Unown (#201) uses a UNOWN_MISC_INFO macro so block parser misses it.
    # Stats are constant across all forms; sourced from gen_2_families.h macro body.
    if 201 not in results:
        results[201] = {
            "dex": 201,
            "name": "Unown",
            "base_hp":  48, "base_atk": 72, "base_def": 48,
            "base_spa": 72, "base_spd": 48, "base_spe": 48,
            "types": [TYPE_IDS["TYPE_PSYCHIC"], TYPE_IDS["TYPE_PSYCHIC"]],
            "catch_rate": 225,
            "base_friendship": 50,
            "gender_ratio": 255,   # MON_GENDERLESS
            "egg_groups": [EGG_GROUP_IDS["EGG_GROUP_NO_EGGS_DISCOVERED"],
                           EGG_GROUP_IDS["EGG_GROUP_NO_EGGS_DISCOVERED"]],
            "ability1":  ability_ids.get("ABILITY_LEVITATE", 26),
            "ability2":  0,
            "ability_h": 0,
            "item_common": None,
            "item_rare":   None,
            "growth_rate": "MediumFast",  # Unown: GROWTH_MEDIUM_FAST
            "_learnset_var": "sUnownLevelUpLearnset",
        }

    return [results[k] for k in sorted(results)]


# ── Moves parsing ─────────────────────────────────────────────────────────────

def parse_moves_info(filepath, move_ids, effect_ids):
    """
    Parse src/data/moves_info.h and return a list of move dicts.
    """
    raw = _read(filepath)
    text = preprocess(raw)
    text = _strip_comments(text)

    moves = []
    blocks = extract_struct_blocks(text, r'MOVE_\w+')

    # Build a reverse-lookup: EFFECT_NAME -> numeric ID
    effect_name_to_id = {v: k for k, v in effect_ids.items()}  # actually it's name->int
    # effect_ids is already name->int

    for label, content in blocks:
        # Skip aliases (they share the same block content as their canonical form)
        move_id = move_ids.get(label)
        if move_id is None:
            # Try without the canonical suffix (e.g. MOVE_DOUBLESLAP alias)
            continue

        move = {"id": move_id, "name": ""}

        # Name
        name_raw = _field_value(content, 'name')
        if name_raw:
            m = re.search(r'COMPOUND_STRING\s*\(\s*"([^"]+)"\s*\)', name_raw)
            if m:
                move["name"] = m.group(1)

        # Effect
        effect_raw = _field_value(content, 'effect')
        effect_name = effect_raw.strip() if effect_raw else "EFFECT_HIT"
        move["effect"] = effect_ids.get(effect_name, 0)
        move["effect_name"] = effect_name

        # Type
        type_raw = _field_value(content, 'type')
        type_resolved = _resolve_ternary(type_raw or "TYPE_NORMAL")
        move["type"] = TYPE_IDS.get(type_resolved.strip(), 1)

        # Category
        cat_raw = _field_value(content, 'category')
        cat_resolved = _resolve_ternary(cat_raw or "DAMAGE_CATEGORY_STATUS")
        move["category"] = CATEGORY_IDS.get(cat_resolved.strip(), 0)

        # Numeric fields
        move["power"]    = _field_int(content, 'power',    default=0)
        move["accuracy"] = _field_int(content, 'accuracy', default=100)
        move["pp"]       = _field_int(content, 'pp',       default=5)
        move["priority"] = _field_int(content, 'priority', default=0)

        # Target
        target_raw = _field_value(content, 'target')
        target_name = _resolve_ternary(target_raw or "TARGET_SELECTED").strip()
        # Map target name to int
        TARGET_MAP = {
            "TARGET_NONE": 0, "TARGET_SELECTED": 1, "TARGET_SMART": 2,
            "TARGET_DEPENDS": 3, "TARGET_OPPONENT": 4, "TARGET_RANDOM": 5,
            "TARGET_BOTH": 6, "TARGET_USER": 7, "TARGET_ALLY": 8,
            "TARGET_USER_AND_ALLY": 9, "TARGET_USER_OR_ALLY": 10,
            "TARGET_FOES_AND_ALLY": 11, "TARGET_FIELD": 12,
            "TARGET_OPPONENTS_FIELD": 13, "TARGET_ALL_BATTLERS": 14,
        }
        move["target"] = TARGET_MAP.get(target_name, 1)

        # Critical hit stage
        move["critical_hit_stage"] = _field_int(content, 'criticalHitStage', default=0)
        move["always_critical_hit"] = _field_bool(content, 'alwaysCriticalHit')

        # Boolean move flags
        move["makes_contact"]      = _field_bool(content, 'makesContact')
        move["punching_move"]      = _field_bool(content, 'punchingMove')
        move["biting_move"]        = _field_bool(content, 'bitingMove')
        move["sound_move"]         = _field_bool(content, 'soundMove')
        move["ballistic_move"]     = _field_bool(content, 'ballisticMove')
        move["powder_move"]        = _field_bool(content, 'powderMove')
        move["dance_move"]         = _field_bool(content, 'danceMove')
        move["slicing_move"]       = _field_bool(content, 'slicingMove')
        move["healing_move"]       = _field_bool(content, 'healingMove')
        move["ignores_protect"]    = _field_bool(content, 'ignoresProtect')
        move["ignores_substitute"] = _field_bool(content, 'ignoresSubstitute')
        move["thaws_user"]         = _field_bool(content, 'thawsUser')

        # Bypass flags (semi-invulnerable targets)
        move["damages_underground"] = _field_bool(content, 'damagesUnderground')
        move["damages_airborne"]    = _field_bool(content, 'damagesAirborne')
        move["damages_underwater"]  = _field_bool(content, 'damagesUnderwater')

        # Ban flags bitmask
        ban = 0
        for flag_name, bit in BAN_FLAGS.items():
            if _field_bool(content, flag_name):
                ban |= bit
        move["ban_flags"] = ban

        # Two-turn / semi-invulnerable
        two_turn = effect_name in TWO_TURN_EFFECTS
        move["two_turn"] = two_turn

        semi_inv = 0
        if two_turn:
            # Look for .argument.twoTurnAttack = { .status = STATE_xxx }
            m = re.search(r'argument\.twoTurnAttack\s*=\s*\{[^}]*\.status\s*=\s*(\w+)', content)
            if m:
                semi_inv = SEMI_INV_STATES.get(m.group(1), 0)
        move["semi_inv_state"] = semi_inv

        # Recoil / drain / fixed damage from .argument field
        move["recoil_percent"] = 0
        move["drain_percent"]  = 0
        move["fixed_damage"]   = 0
        move["level_damage"]   = False

        arg_raw = _field_value(content, 'argument')
        if arg_raw:
            # .argument = { .recoilPercentage = 25 }
            m = re.search(r'recoilPercentage\s*=\s*(\d+)', arg_raw)
            if m:
                move["recoil_percent"] = int(m.group(1))
            # .argument = { .absorbPercentage = 50 }
            m = re.search(r'absorbPercentage\s*=\s*(\d+)', arg_raw)
            if m:
                move["drain_percent"] = int(m.group(1))
            # .argument = { .fixedDamage = 40 }
            m = re.search(r'fixedDamage\s*=\s*(\d+)', arg_raw)
            if m:
                move["fixed_damage"] = int(m.group(1))

        if effect_name == "EFFECT_LEVEL_DAMAGE":
            move["level_damage"] = True

        # Special effect flags
        for eff, flag in EFFECT_FLAG_MAP.items():
            if effect_name == eff and flag:
                move[flag] = True

        # EFFECT_REFLECT_DAMAGE: category determines counter vs mirror_coat
        if effect_name == "EFFECT_REFLECT_DAMAGE":
            if move["category"] == 0:  # PHYSICAL
                move["counter"] = True
            else:
                move["mirror_coat"] = True

        # is_spread: TARGET_BOTH or TARGET_FOES_AND_ALLY
        move["is_spread"] = target_name in ("TARGET_BOTH", "TARGET_FOES_AND_ALLY")

        # stat_change_self: TARGET_USER or TARGET_USER_AND_ALLY
        move["stat_change_self"] = target_name in ("TARGET_USER", "TARGET_USER_AND_ALLY")

        # Secondary effect from additionalEffects
        move["secondary_effect"] = 0
        move["secondary_chance"] = 0
        move["stat_change_stat"]   = -1
        move["stat_change_amount"] = 0

        # Find additionalEffects block — use brace-aware extraction
        ae_raw = _field_value(content, 'additionalEffects')
        # ae_raw is like  ADDITIONAL_EFFECTS({ .moveEffect = X, .chance = Y })
        ae_m_wrap = re.match(r'ADDITIONAL_EFFECTS\s*\((.+)\)$', ae_raw or '', re.DOTALL) if ae_raw else None
        ae_m = ae_m_wrap
        if ae_m:
            ae_content = ae_m.group(1) if ae_m_wrap else ae_m.group(1)
            # Find first {…} sub-block (first effect entry)
            sub_m = re.search(r'\{([^}]*)\}', ae_content)
            if sub_m:
                sub = sub_m.group(1)
                # moveEffect
                me_m = re.search(r'\.moveEffect\s*=\s*(\w+)', sub)
                if me_m:
                    me_name = me_m.group(1)
                    if me_name in MOVE_EFFECT_TO_SE:
                        move["secondary_effect"] = MOVE_EFFECT_TO_SE[me_name]
                    elif me_name == "STAT_CHANGE_EFFECT_PLUS":
                        # Stat change: parse which stat and how much
                        for stat_field, stat_idx in STAT_FIELD_TO_INDEX.items():
                            sm = re.search(r'\.' + stat_field + r'\s*=\s*([^,\n]+)', sub)
                            if sm:
                                val = _parse_int(sm.group(1))
                                if val and val > 0:
                                    move["stat_change_stat"]   = stat_idx
                                    move["stat_change_amount"] = val
                                    break
                    elif me_name == "STAT_CHANGE_EFFECT_MINUS":
                        for stat_field, stat_idx in STAT_FIELD_TO_INDEX.items():
                            sm = re.search(r'\.' + stat_field + r'\s*=\s*([^,\n]+)', sub)
                            if sm:
                                val = _parse_int(sm.group(1))
                                if val and val > 0:
                                    move["stat_change_stat"]   = stat_idx
                                    move["stat_change_amount"] = -val
                                    break
                # chance
                ch_m = re.search(r'\.chance\s*=\s*(\d+)', sub)
                if ch_m:
                    move["secondary_chance"] = int(ch_m.group(1))

        # Deduplicate: skip if we already have a move with this ID from an earlier block
        # (some moves have aliases like MOVE_THUNDERPUNCH = MOVE_THUNDER_PUNCH at same ID)
        moves.append(move)

    # Deduplicate by move_id: keep first occurrence
    seen = {}
    deduped = []
    for m in moves:
        if m["id"] not in seen:
            seen[m["id"]] = True
            deduped.append(m)

    return sorted(deduped, key=lambda x: x["id"])


# ── Learnset parsing ──────────────────────────────────────────────────────────

def parse_learnsets(gen_files, move_ids):
    """
    Parse level_up_learnsets/gen_{1,2,3}.h files.
    Returns a dict: learnset_var_name -> list of {level, move_id, move_name}
    """
    learnsets = {}
    for filepath in gen_files:
        raw = _read(filepath)
        text = preprocess(raw)
        text = _strip_comments(text)

        # Find all static const struct LevelUpMove sXxxLevelUpLearnset[] = { ... }
        for arr_m in re.finditer(
            r'(?:static\s+)?const\s+struct\s+LevelUpMove\s+(s\w+LevelUpLearnset)\s*\[\s*\]\s*=\s*\{([^;]*?)\};',
            text, re.DOTALL
        ):
            var_name = arr_m.group(1)
            body = arr_m.group(2)
            entries = []
            for entry in re.finditer(
                r'LEVEL_UP_MOVE\s*\(\s*(\d+)\s*,\s*(MOVE_\w+)\s*\)',
                body
            ):
                level   = int(entry.group(1))
                mv_name = entry.group(2)
                mv_id   = move_ids.get(mv_name)
                if mv_id is not None:
                    entries.append({"level": level, "move_id": mv_id, "move_name": mv_name})
            learnsets[var_name] = entries

    return learnsets


# ── Items parsing ─────────────────────────────────────────────────────────────

def parse_items(filepath, item_ids, hold_effect_ids):
    """
    Parse src/data/items.h and return a list of item dicts.
    Source: src/data/items.h :: gItemsInfo[] struct array.
    Fields extracted: id, name, price, pocket, hold_effect, hold_effect_param, description.
    """
    raw = _read(filepath)

    # Pre-scan raw text for named string arrays (descriptions + item names)
    # These appear as:  static const u8 sXxxDesc[] = _("...");
    # or:               const u8 gXxxItemName[]    = _("...");
    named_strings = _extract_named_strings(raw)

    # Preprocess to resolve #if blocks
    text = preprocess(raw)
    text = _strip_comments(text)

    items = []
    seen_ids = set()

    blocks = extract_struct_blocks(text, r'ITEM_\w+')
    for label, content in blocks:
        item_id = item_ids.get(label)
        if item_id is None:
            continue
        if item_id in seen_ids:
            continue
        seen_ids.add(item_id)

        item = {"id": item_id}

        # Name
        name_raw = _field_value(content, 'name')
        item["name"] = _extract_item_string(name_raw, named_strings)

        # Price
        item["price"] = _field_int(content, 'price', default=0)

        # Pocket
        pocket_raw = _field_value(content, 'pocket')
        if pocket_raw:
            pocket_resolved = _resolve_ternary(pocket_raw.strip())
            item["pocket"] = POCKET_NAMES.get(pocket_resolved.strip(), "items")
        else:
            item["pocket"] = "items"

        # Hold effect (numeric ID from HOLD_EFFECT_* enum)
        he_raw = _field_value(content, 'holdEffect')
        if he_raw:
            he_name = _resolve_ternary(he_raw.strip())
            item["hold_effect"] = hold_effect_ids.get(he_name.strip(), 0)
        else:
            item["hold_effect"] = 0

        # Hold effect parameter
        item["hold_effect_param"] = _field_int(content, 'holdEffectParam', default=0)

        # Description
        desc_raw = _field_value(content, 'description')
        item["description"] = _extract_item_string(desc_raw, named_strings)

        items.append(item)

    return sorted(items, key=lambda x: x["id"])


# ── Evolution parsing ─────────────────────────────────────────────────────────

def _split_evo_tuples(content):
    """
    Split the content inside EVOLUTION(...) into individual {}-tuples.
    Returns list of tuple content strings (without outer braces).
    """
    tuples = []
    i = 0
    while i < len(content):
        if content[i] == '{':
            depth = 1
            j = i + 1
            while j < len(content) and depth > 0:
                if content[j] == '{':
                    depth += 1
                elif content[j] == '}':
                    depth -= 1
                j += 1
            tuples.append(content[i+1:j-1])  # content inside {}
            i = j
        else:
            i += 1
    return tuples


def _split_at_depth_zero(text, sep=','):
    """Split text by sep only at paren/brace depth 0."""
    tokens = []
    current = []
    depth = 0
    for ch in text:
        if ch in '({':
            depth += 1
            current.append(ch)
        elif ch in ')}':
            depth -= 1
            current.append(ch)
        elif ch == sep and depth == 0:
            tokens.append(''.join(current).strip())
            current = []
        else:
            current.append(ch)
    if current:
        tokens.append(''.join(current).strip())
    return tokens


def _parse_evo_tuple(tuple_str, nat_dex_ids):
    """
    Parse one evolution tuple like:
      EVO_LEVEL, 16, SPECIES_IVYSAUR
      EVO_ITEM, ITEM_THUNDER_STONE, SPECIES_RAICHU, CONDITIONS({IF_REGION, ...})
    Returns a dict or None (if out-of-scope or EVO_NONE).
    """
    tokens = _split_at_depth_zero(tuple_str, ',')
    if len(tokens) < 3:
        return None

    method_name = tokens[0].strip()
    cond_raw    = tokens[1].strip()
    target_name = tokens[2].strip()

    if method_name in ('EVO_NONE', 'EVO_SPLIT_FROM_EVO'):
        return None

    method = EVO_METHOD_NAMES.get(method_name, method_name.lower())

    # Condition: level (int) for level_up methods, item name string otherwise
    if method in ('level_up', 'level_up_battle', 'battle_end', 'spin'):
        cond = _parse_int(cond_raw) or 0
    else:
        cond = cond_raw if cond_raw else None

    # Resolve target SPECIES_X → National Dex number
    target_dex = None
    if target_name.startswith('SPECIES_'):
        suffix = target_name[len('SPECIES_'):]
        nat_key = f'NATIONAL_DEX_{suffix}'
        target_dex = nat_dex_ids.get(nat_key)

    # Only include targets with dex numbers 1–386
    if target_dex is None or not (1 <= target_dex <= 386):
        return None

    evo = {
        "method":     method,
        "condition":  cond,
        "target_dex": target_dex,
    }

    # Collect optional condition flags from CONDITIONS({IF_X, ...})
    conditions = []
    for extra in tokens[3:]:
        if 'CONDITIONS' in extra:
            conditions.extend(re.findall(r'\bIF_[A-Z_]+\b', extra))
    if conditions:
        evo["conditions"] = conditions

    return evo


def parse_evolutions(gen_files, nat_dex_ids):
    """
    Extract evolutions from gen_{1,2,3}_families.h.
    Returns dict: {str(nat_dex_num): [evo_dict, ...]}.
    """
    results = {}  # nat_dex_int -> evo_list

    for filepath in gen_files:
        raw = _read(filepath)
        text = preprocess(raw)
        text = _strip_comments(text)

        blocks = extract_struct_blocks(text, r'SPECIES_\w+')
        for label, content in blocks:
            # Resolve nat dex number (same logic as parse_species_info)
            nat_raw = _field_value(content, 'natDexNum')
            if nat_raw is None:
                continue
            nat_num = nat_dex_ids.get(nat_raw)
            if nat_num is None:
                nat_num = _parse_int(nat_raw, nat_dex_ids)
            if nat_num is None or not (1 <= nat_num <= 386):
                continue

            if nat_num in results:
                continue  # base form only

            evo_raw = _field_value(content, 'evolutions')
            if not evo_raw:
                results[nat_num] = []
                continue

            # Strip EVOLUTION() wrapper
            evo_inner_m = re.match(r'EVOLUTION\s*\((.+)\)\s*$', evo_raw.strip(), re.DOTALL)
            if not evo_inner_m:
                results[nat_num] = []
                continue

            evo_content = evo_inner_m.group(1)
            evo_list = []
            for tuple_str in _split_evo_tuples(evo_content):
                evo = _parse_evo_tuple(tuple_str, nat_dex_ids)
                if evo:
                    evo_list.append(evo)

            results[nat_num] = evo_list

    # Unown (#201) has no evolutions
    if 201 not in results:
        results[201] = []

    return {str(k): v for k, v in sorted(results.items())}


# ── TM/HM map ─────────────────────────────────────────────────────────────────

def build_tmhm_map(move_ids, moves):
    """
    Build a TM/HM number → move mapping.
    Source: include/constants/tms_hms.h FOREACH_TM / FOREACH_HM lists.
    Keys: "1"–"50" for TM01–TM50, "51"–"58" for HM01–HM08.
    """
    move_id_to_display = {m["id"]: m["name"] for m in moves}
    result = {}

    for i, mv_suffix in enumerate(TM_MOVES, 1):
        mv_const = "MOVE_" + mv_suffix
        mv_id    = move_ids.get(mv_const, 0)
        result[str(i)] = {
            "tm_name":   f"TM{i:02d}",
            "move_name": mv_const,
            "move_id":   mv_id,
            "name":      move_id_to_display.get(mv_id, ""),
        }

    for i, mv_suffix in enumerate(HM_MOVES, 1):
        num      = 50 + i
        mv_const = "MOVE_" + mv_suffix
        mv_id    = move_ids.get(mv_const, 0)
        result[str(num)] = {
            "tm_name":   f"HM{i:02d}",
            "move_name": mv_const,
            "move_id":   mv_id,
            "name":      move_id_to_display.get(mv_id, ""),
        }

    return result


# ── EXP curves ────────────────────────────────────────────────────────────────

def compute_exp_curves():
    """
    Compute EXP required per level (1–100) for each of the 6 growth curves.
    Formulas from: src/data/pokemon/experience_tables.h
    Uses C-style integer division (Python //) throughout, matching the source.

    Growth curve enum order (include/constants/pokemon.h):
      GROWTH_MEDIUM_FAST=0, GROWTH_ERRATIC=1, GROWTH_FLUCTUATING=2,
      GROWTH_MEDIUM_SLOW=3, GROWTH_FAST=4, GROWTH_SLOW=5

    Returns dict keyed by curve name string, each value is a list of 101 ints
    (index 0 = level 0 = 0, index 1 = level 1 = 1, index n = EXP to reach level n).
    """
    def exp_medium_fast(n):
        return n ** 3

    def exp_erratic(n):
        if n <= 50:
            return (100 - n) * n ** 3 // 50
        elif n <= 68:
            return (150 - n) * n ** 3 // 100
        elif n <= 98:
            return ((1911 - 10 * n) // 3) * n ** 3 // 500
        else:
            return (160 - n) * n ** 3 // 100

    def exp_fluctuating(n):
        if n <= 15:
            return ((n + 1) // 3 + 24) * n ** 3 // 50
        elif n <= 36:
            return (n + 14) * n ** 3 // 50
        else:
            return (n // 2 + 32) * n ** 3 // 50

    def exp_medium_slow(n):
        return 6 * n ** 3 // 5 - 15 * n ** 2 + 100 * n - 140

    def exp_fast(n):
        return 4 * n ** 3 // 5

    def exp_slow(n):
        return 5 * n ** 3 // 4

    def _build(formula):
        table = [0, 1]  # levels 0 and 1 are always 0 and 1
        for n in range(2, 101):
            table.append(formula(n))
        return table

    return {
        "MediumFast":  _build(exp_medium_fast),
        "Erratic":     _build(exp_erratic),
        "Fluctuating": _build(exp_fluctuating),
        "MediumSlow":  _build(exp_medium_slow),
        "Fast":        _build(exp_fast),
        "Slow":        _build(exp_slow),
    }


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    os.makedirs(OUT, exist_ok=True)

    print("Parsing enums...")

    # Species IDs
    species_ids = parse_c_enum(_read(os.path.join(REF, "include/constants/species.h")))
    print(f"  {len(species_ids)} species constants")

    # National Dex IDs (enum is 1-indexed: NONE=0, BULBASAUR=1 ...)
    nat_dex_ids = parse_c_enum(_read(os.path.join(REF, "include/constants/pokedex.h")))
    print(f"  {len(nat_dex_ids)} national dex constants")

    # Ability IDs
    ability_ids = parse_c_enum(_read(os.path.join(REF, "include/constants/abilities.h")))
    print(f"  {len(ability_ids)} ability constants")

    # Move IDs
    move_ids = parse_c_enum(_read(os.path.join(REF, "include/constants/moves.h")))
    print(f"  {len(move_ids)} move constants")

    # Effect IDs
    effect_ids = parse_c_enum(_read(os.path.join(REF, "include/constants/battle_move_effects.h")))
    print(f"  {len(effect_ids)} battle move effect constants")

    # Item IDs (from include/constants/items.h)
    item_ids = parse_c_enum(_read(os.path.join(REF, "include/constants/items.h")))
    print(f"  {len(item_ids)} item constants")

    # Hold Effect IDs
    hold_effect_ids = parse_c_enum(_read(os.path.join(REF, "include/constants/hold_effects.h")))
    print(f"  {len(hold_effect_ids)} hold effect constants")

    # ── Pokémon ───────────────────────────────────────────────────────────────
    print("\nParsing species info...")
    species_files = [
        os.path.join(REF, "src/data/pokemon/species_info/gen_1_families.h"),
        os.path.join(REF, "src/data/pokemon/species_info/gen_2_families.h"),
        os.path.join(REF, "src/data/pokemon/species_info/gen_3_families.h"),
    ]
    pokemon = parse_species_info(species_files, species_ids, nat_dex_ids, ability_ids)
    print(f"  {len(pokemon)} Pokémon extracted (target: 386)")
    found_dex = {p["dex"] for p in pokemon}
    missing = [n for n in range(1, 387) if n not in found_dex]
    if missing:
        print(f"  Missing dex numbers: {missing}")

    # ── Moves ─────────────────────────────────────────────────────────────────
    print("\nParsing moves info...")
    moves = parse_moves_info(
        os.path.join(REF, "src/data/moves_info.h"),
        move_ids, effect_ids
    )
    print(f"  {len(moves)} moves extracted")

    # ── Learnsets ─────────────────────────────────────────────────────────────
    print("\nParsing learnsets...")
    learnset_files = [
        os.path.join(REF, "src/data/pokemon/level_up_learnsets/gen_1.h"),
        os.path.join(REF, "src/data/pokemon/level_up_learnsets/gen_2.h"),
        os.path.join(REF, "src/data/pokemon/level_up_learnsets/gen_3.h"),
    ]
    learnset_map = parse_learnsets(learnset_files, move_ids)
    print(f"  {len(learnset_map)} learnset arrays parsed")

    # ── Items ─────────────────────────────────────────────────────────────────
    print("\nParsing items...")
    items = parse_items(
        os.path.join(REF, "src/data/items.h"),
        item_ids, hold_effect_ids
    )
    print(f"  {len(items)} items extracted")

    # ── Evolutions ────────────────────────────────────────────────────────────
    print("\nParsing evolutions...")
    evolutions = parse_evolutions(species_files, nat_dex_ids)
    evo_count = sum(len(v) for v in evolutions.values())
    print(f"  {len(evolutions)} species with evolution data, {evo_count} total evolution entries")

    # ── TM/HM map ─────────────────────────────────────────────────────────────
    print("\nBuilding TM/HM map...")
    tmhm_map = build_tmhm_map(move_ids, moves)
    print(f"  {len(tmhm_map)} TM/HM entries (50 TMs + 8 HMs)")

    # ── EXP curves ────────────────────────────────────────────────────────────
    print("\nComputing EXP curves...")
    exp_curves = compute_exp_curves()
    print(f"  {len(exp_curves)} growth curves computed (levels 0–100 each)")
    # Spot-check: MediumSlow level 100 = 1059860
    ms_100 = exp_curves["MediumSlow"][100]
    assert ms_100 == 1059860, f"MediumSlow[100] = {ms_100}, expected 1059860"
    print(f"  MediumSlow[100] = {ms_100} ✓")

    # ── Build learnsets.json ──────────────────────────────────────────────────
    learnsets_out = {}
    for pkmn in pokemon:
        ls_var = pkmn.get("_learnset_var")
        dex = str(pkmn["dex"])
        if ls_var and ls_var in learnset_map:
            learnsets_out[dex] = learnset_map[ls_var]
        else:
            learnsets_out[dex] = []

    # Strip internal fields before writing
    for pkmn in pokemon:
        pkmn.pop("_learnset_var", None)

    # ── Write JSON ────────────────────────────────────────────────────────────
    pokemon_path    = os.path.join(OUT, "pokemon.json")
    moves_path      = os.path.join(OUT, "moves.json")
    learnsets_path  = os.path.join(OUT, "learnsets.json")
    items_path      = os.path.join(OUT, "items.json")
    evolutions_path = os.path.join(OUT, "evolutions.json")
    tmhm_path       = os.path.join(OUT, "tmhm_map.json")
    exp_path        = os.path.join(OUT, "exp_curves.json")

    with open(pokemon_path, "w", encoding="utf-8") as f:
        json.dump(pokemon, f, indent=2, ensure_ascii=False)
    print(f"\nWrote {pokemon_path} ({len(pokemon)} entries)")

    with open(moves_path, "w", encoding="utf-8") as f:
        json.dump(moves, f, indent=2, ensure_ascii=False)
    print(f"Wrote {moves_path} ({len(moves)} entries)")

    with open(learnsets_path, "w", encoding="utf-8") as f:
        json.dump(learnsets_out, f, indent=2, ensure_ascii=False)
    print(f"Wrote {learnsets_path} ({len(learnsets_out)} entries)")

    with open(items_path, "w", encoding="utf-8") as f:
        json.dump(items, f, indent=2, ensure_ascii=False)
    print(f"Wrote {items_path} ({len(items)} entries)")

    with open(evolutions_path, "w", encoding="utf-8") as f:
        json.dump(evolutions, f, indent=2, ensure_ascii=False)
    print(f"Wrote {evolutions_path} ({len(evolutions)} species)")

    with open(tmhm_path, "w", encoding="utf-8") as f:
        json.dump(tmhm_map, f, indent=2, ensure_ascii=False)
    print(f"Wrote {tmhm_path} ({len(tmhm_map)} entries)")

    with open(exp_path, "w", encoding="utf-8") as f:
        json.dump(exp_curves, f, indent=2, ensure_ascii=False)
    print(f"Wrote {exp_path} ({len(exp_curves)} curves)")

    # ── Spot-checks ───────────────────────────────────────────────────────────
    print("\n── Spot-check ──────────────────────────────────────────")
    spot_dex = {1: "Bulbasaur", 6: "Charizard", 150: "Mewtwo", 384: "Rayquaza"}

    pokemon_by_dex = {p["dex"]: p for p in pokemon}
    for dex, expected_name in spot_dex.items():
        pkmn = pokemon_by_dex.get(dex)
        if pkmn:
            ls = learnsets_out.get(str(dex), [])
            print(f"\n#{dex} {pkmn['name']} (expected: {expected_name})")
            print(f"  Types:      {pkmn['types']}")
            print(f"  Stats:      HP={pkmn['base_hp']} Atk={pkmn['base_atk']} Def={pkmn['base_def']}"
                  f" SpA={pkmn['base_spa']} SpD={pkmn['base_spd']} Spe={pkmn['base_spe']}")
            print(f"  GrowthRate: {pkmn['growth_rate']}")
            print(f"  Learnset:   {len(ls)} moves, first={ls[0] if ls else 'none'}")
        else:
            print(f"\n#{dex} {expected_name}: NOT FOUND")

    # Evolution spot-check
    print("\nEvolution spot-checks:")
    for dex, name in [(1, "Bulbasaur"), (133, "Eevee"), (25, "Pikachu"), (64, "Kadabra")]:
        evos = evolutions.get(str(dex), [])
        print(f"  #{dex} {name}: {len(evos)} evolution(s)")
        for e in evos:
            print(f"    → #{e['target_dex']} via {e['method']} (cond={e['condition']})"
                  + (f" conditions={e.get('conditions')}" if 'conditions' in e else ""))

    # TM/HM spot-check
    print("\nTM/HM spot-checks:")
    for num, expected_name in [(1, "TM01/MOVE_FOCUS_PUNCH"), (6, "TM06/MOVE_TOXIC"),
                                (19, "TM19/MOVE_GIGA_DRAIN"), (51, "HM01/MOVE_CUT")]:
        entry = tmhm_map.get(str(num))
        if entry:
            print(f"  [{num}] {entry['tm_name']}: {entry['move_name']} (id={entry['move_id']})"
                  f" name={entry['name']!r}")
        else:
            print(f"  [{num}]: NOT FOUND")

    # Item spot-check
    print("\nItem spot-checks:")
    items_by_id = {i["id"]: i for i in items}
    for iid, iname in [(28, "Potion"), (1, "Poke Ball"), (53, "Berry Juice")]:
        item = items_by_id.get(iid)
        if item:
            print(f"  [{iid}] {item['name']!r} pocket={item['pocket']}"
                  f" price={item['price']} hold={item['hold_effect']}")
        else:
            print(f"  [{iid}] {iname}: NOT FOUND")

    # EXP spot-checks
    print("\nEXP curve spot-checks:")
    print(f"  MediumSlow[100] = {exp_curves['MediumSlow'][100]} (expected 1059860)")
    print(f"  MediumFast[100] = {exp_curves['MediumFast'][100]} (expected 1000000)")
    print(f"  Fast[100]       = {exp_curves['Fast'][100]}       (expected 800000)")
    print(f"  Slow[100]       = {exp_curves['Slow'][100]}       (expected 1250000)")

    # Move spot-check
    move_by_id = {m["id"]: m for m in moves}
    print("\nMove spot-checks:")
    for mid, mname in [(1, "Pound"), (57, "Surf"), (89, "Earthquake"), (264, "Focus Punch")]:
        mv = move_by_id.get(mid)
        if mv:
            print(f"  [{mid}] {mv['name']}: type={mv['type']} cat={mv['category']} "
                  f"pow={mv['power']} acc={mv['accuracy']} pp={mv['pp']}")
        else:
            print(f"  [{mid}] {mname}: NOT FOUND")

    print("\nDone.")


if __name__ == "__main__":
    main()
