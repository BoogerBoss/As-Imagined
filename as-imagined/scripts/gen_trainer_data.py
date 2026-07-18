#!/usr/bin/env python3
"""
[M24a] Trainer Data Pipeline converter.

Two independent source parsers, each producing its own .tres output set:

  1. gTrainerClasses[] (src/battle_main.c, a plain C designated-initializer
     array, cross-referenced against include/constants/trainers.h's own
     `enum TrainerClassID` for stable index-based IDs) -> TrainerClassData
     .tres files under data/trainer_classes/.

  2. trainers.party (src/data/trainers.party, a Showdown-export-style text
     format processed by tools/trainerproc) -> TrainerData .tres files
     under data/trainers/ (one per real trainer) plus TrainerPicData .tres
     files under data/trainer_pics/ (one per distinct portrait, a
     deliberately SEPARATE id space -- see docs/m24_recon.md section 1.4:
     855 trainers share only ~93 distinct Pic values).

Scope (see docs/m24_recon.md section 6 for full reasoning, all resolved
with Rob before this converter was written):
  - TRAINER_NONE is excluded -- it is a blank sentinel entry (empty Name,
    used as "no real trainer" filler), not a real battlable trainer.
  - overrideTrainer / "Copy Pool" is NOT modeled -- confirmed via direct
    grep that zero of the real trainers use it; it is a Trainer-Pools-only
    mechanism and Trainer Pools are excluded from M24 entirely (deferred to
    M34, section 6.1).
  - AI flags are narrowed to just the small set of atomic flags actually
    used across the whole roster (confirmed via grep: only 6 distinct
    combinations exist -- Basic Trainer / Check Bad Move / Try To Faint /
    Force Setup First Turn / Risky, in various ORs), not the full 34-flag
    AI_FLAG_* bitmask engine (deferred to M34, section 6.2).
  - Rematch group/tier fields are NOT populated from source in M24 --
    TrainerData carries the static fields but this converter always leaves
    them at their "no rematch" default (rematch progression is deferred to
    M34 pending M33's save-state infrastructure, section 6.5).
  - Starting Status / Multi Party fields are not modeled at all (near-zero
    real usage, dormant-field precedent already established elsewhere in
    this project's data pipeline).

Name resolution (species/move/item/ability) is done by scanning this
project's OWN already-generated data (data/pokemon.json, data/moves/*.tres,
data/items/*.tres, data/abilities/*.tres) rather than re-deriving from
source constants directly -- keeps this converter's output guaranteed
consistent with whatever subset of moves/items/abilities this project has
actually implemented (717/934 moves, etc.) rather than assuming 1:1
coverage with the reference engine.

Usage (from project root):
    python3 scripts/gen_trainer_data.py
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "reference", "pokeemerald_expansion")
DATA = os.path.join(ROOT, "data")

TRAINERS_PARTY = os.path.join(REF, "src", "data", "trainers.party")
BATTLE_MAIN_C = os.path.join(REF, "src", "battle_main.c")
TRAINERS_H = os.path.join(REF, "include", "constants", "trainers.h")

OUT_TRAINERS = os.path.join(DATA, "trainers")
OUT_TRAINER_CLASSES = os.path.join(DATA, "trainer_classes")
OUT_TRAINER_PICS = os.path.join(DATA, "trainer_pics")

NATURES = [
    "HARDY", "LONELY", "BRAVE", "ADAMANT", "NAUGHTY",
    "BOLD", "DOCILE", "RELAXED", "IMPISH", "LAX",
    "TIMID", "HASTY", "SERIOUS", "JOLLY", "NAIVE",
    "MODEST", "MILD", "QUIET", "BASHFUL", "RASH",
    "CALM", "GENTLE", "SASSY", "CAREFUL", "QUIRKY",
]

STAT_LABELS = {"HP": 0, "ATK": 1, "DEF": 2, "SPA": 3, "SPD": 4, "SPE": 5}

# Narrow AI-flag bitmask -- see docs/m24_recon.md section 6.2. Only the
# atomic flags that actually appear (alone or combined) across all 855
# source trainers are represented; NOT the full 34-flag engine.
AI_CHECK_BAD_MOVE = 1
AI_TRY_TO_FAINT = 2
AI_CHECK_VIABILITY = 4
AI_FORCE_SETUP_FIRST_TURN = 8
AI_RISKY = 16
AI_TOKEN_MAP = {
    "CHECKBADMOVE": AI_CHECK_BAD_MOVE,
    "TRYTOFAINT": AI_TRY_TO_FAINT,
    "FORCESETUPFIRSTTURN": AI_FORCE_SETUP_FIRST_TURN,
    "RISKY": AI_RISKY,
    # "Basic Trainer" is itself a composite alias in source
    # (AI_FLAG_BASIC_TRAINER = CHECK_BAD_MOVE | TRY_TO_FAINT | CHECK_VIABILITY).
    "BASICTRAINER": AI_CHECK_BAD_MOVE | AI_TRY_TO_FAINT | AI_CHECK_VIABILITY,
}


def normalize(s: str) -> str:
    """Matches tools/trainerproc/main.c's own fprint_constant() transform:
    uppercase alnum only, apostrophes dropped, everything else collapses
    (since we don't need underscore placeholders for name-matching)."""
    return re.sub(r"[^A-Z0-9]", "", s.upper())


def clean_token(raw: str, prefix: str) -> str:
    s = raw.strip()
    up = s.upper()
    if up.startswith(prefix):
        s = s[len(prefix):]
    return normalize(s)


# ---------------------------------------------------------------------------
# Name-resolution maps, built from this project's OWN existing data pipeline
# ---------------------------------------------------------------------------

def load_species_map():
    with open(os.path.join(DATA, "pokemon.json"), encoding="utf-8") as f:
        species = json.load(f)
    m = {}
    for sp in species:
        m[normalize(sp["name"])] = sp["dex"]
    return m


def load_tres_name_map(subdir: str, name_field: str):
    """Scans data/<subdir>/*_NNNN.tres, mapping normalize(name_field's
    string value) -> id (from the filename's own zero-padded number, the
    same path-convention every Registry in this project already uses)."""
    m = {}
    dirpath = os.path.join(DATA, subdir)
    name_pat = re.compile(rf'^{re.escape(name_field)}\s*=\s*"(.*)"\s*$', re.M)
    for fn in sorted(os.listdir(dirpath)):
        if not fn.endswith(".tres"):
            continue
        idm = re.search(r"_(\d+)\.tres$", fn)
        if not idm:
            continue
        fid = int(idm.group(1))
        text = open(os.path.join(dirpath, fn), encoding="utf-8").read()
        namem = name_pat.search(text)
        if namem:
            m[normalize(namem.group(1))] = fid
    return m


def load_learnsets():
    with open(os.path.join(DATA, "learnsets.json"), encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# Parser 1: gTrainerClasses[] -> TrainerClassData
# ---------------------------------------------------------------------------

def split_top_level(s: str):
    """Splits a designated-initializer's inner content on top-level commas,
    ignoring commas inside "..." strings or (...) parens (needed for the
    _("...") name macro and the B_X >= GEN_Y ? A : B ternary ball exprs)."""
    parts = []
    depth = 0
    cur = ""
    in_str = False
    for ch in s:
        if ch == '"':
            in_str = not in_str
            cur += ch
        elif in_str:
            cur += ch
        elif ch == "(":
            depth += 1
            cur += ch
        elif ch == ")":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


def parse_trainer_class_enum():
    """Returns an ordered list of TRAINER_CLASS_* names, index == real
    gTrainerClasses[] array index (a plain sequential C enum, confirmed via
    direct read -- no explicit = N assignments anywhere in the block)."""
    with open(TRAINERS_H, encoding="utf-8") as f:
        content = f.read()
    m = re.search(r"enum TrainerClassID\s*\{(.*?)\n\};", content, re.DOTALL)
    names = []
    for line in m.group(1).split("\n"):
        line = line.strip()
        if not line:
            continue
        lm = re.match(r"(TRAINER_CLASS_\w+)\s*,?", line)
        if lm:
            names.append(lm.group(1))
    return names


def parse_trainer_classes_array():
    """Returns {TRAINER_CLASS_XXX: (display_name, money, ball_name)}."""
    with open(BATTLE_MAIN_C, encoding="utf-8") as f:
        content = f.read()
    start = content.index("const struct TrainerClass gTrainerClasses[TRAINER_CLASS_COUNT] =")
    end = content.index("\n};", start)
    body = content[start:end]

    entries = {}
    for m in re.finditer(r"\[(TRAINER_CLASS_\w+)\]\s*=\s*\{(.*?)\}", body):
        key = m.group(1)
        inner = m.group(2)
        fields = split_top_level(inner)
        display_name = ""
        money = 0
        ball_name = "Poke"
        if fields:
            nm = re.search(r'_\("(.*)"\)', fields[0])
            if nm:
                display_name = nm.group(1).replace("{PKMN}", "Pkmn")
        if len(fields) > 1 and fields[1].strip().isdigit():
            money = int(fields[1].strip())
        if len(fields) > 2:
            ball_expr = fields[2].strip()
            if "?" in ball_expr:
                # Ternary gated on a B_* config flag -- this project's
                # standing convention (established across M17/M18/M19) is
                # to resolve GEN-gated ternaries at this project's real
                # GEN_LATEST config, which is confirmed (via direct read
                # of include/config/battle.h) to make
                # B_TRAINER_CLASS_POKE_BALLS >= GEN_8 evaluate TRUE here --
                # so the true (first) branch is always the correct pick.
                true_branch = ball_expr.split("?", 1)[1].split(":", 1)[0].strip()
                ball_expr = true_branch
            bm = re.match(r"BALL_(\w+)", ball_expr)
            if bm:
                ball_name = bm.group(1).replace("_", " ").title().replace(" ", "")
        entries[key] = (display_name, money, ball_name)
    return entries


def render_trainer_class_tres(class_id, class_key, display_name, money, ball_name):
    lines = []
    lines.append('[gd_resource type="Resource" script_class="TrainerClassData" load_steps=2 format=3]')
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://scripts/data/trainer_class_data.gd" id="1"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1")')
    lines.append(f"trainer_class_id = {class_id}")
    if display_name:
        lines.append(f'class_name_text = "{escape_tres_string(display_name)}"')
    if money:
        lines.append(f"money = {money}")
    if ball_name and ball_name != "Poke":
        lines.append(f'ball_name = "{ball_name}"')
    lines.append("")
    return "\n".join(lines)


def escape_tres_string(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def emit_trainer_classes():
    os.makedirs(OUT_TRAINER_CLASSES, exist_ok=True)
    enum_order = parse_trainer_class_enum()
    array_entries = parse_trainer_classes_array()

    class_id_by_key = {}
    count = 0
    for idx, key in enumerate(enum_order):
        display_name, money, ball_name = array_entries.get(key, ("", 0, "Poke"))
        class_id_by_key[key] = idx
        text = render_trainer_class_tres(idx, key, display_name, money, ball_name)
        out_path = os.path.join(OUT_TRAINER_CLASSES, f"trainer_class_{idx:04d}.tres")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(text)
        count += 1
    return class_id_by_key, count


# ---------------------------------------------------------------------------
# Parser 2: trainers.party -> TrainerData + TrainerPicData
# ---------------------------------------------------------------------------

def strip_comments(text: str) -> str:
    # Plain C block comments only -- confirmed via the file's own header
    # doc that "//" is NOT a valid comment marker here, so we must not
    # treat it as one.
    return re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)


def parse_trainers_party():
    with open(TRAINERS_PARTY, encoding="utf-8") as f:
        raw = f.read()
    text = strip_comments(raw)

    # Split on trainer headers, keeping the key.
    blocks = re.split(r"^=== (TRAINER_\w+) ===\s*$", text, flags=re.M)
    # blocks[0] is leading junk before the first header; then alternating
    # (key, body) pairs.
    trainers = []
    for i in range(1, len(blocks), 2):
        key = blocks[i]
        body = blocks[i + 1]
        if key == "TRAINER_NONE":
            continue  # sentinel/blank entry, not a real trainer -- see module docstring
        trainers.append((key, body))
    return trainers


def group_by_blank_lines(body: str):
    groups = []
    cur = []
    for line in body.split("\n"):
        if line.strip() == "":
            if cur:
                groups.append(cur)
                cur = []
        else:
            cur.append(line)
    if cur:
        groups.append(cur)
    return groups


def parse_field_lines(lines):
    fields = {}
    for line in lines:
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields


def parse_headline(line: str):
    """Parses a Pokemon's Showdown-export-style headline:
    'Species', 'Nickname (Species)', 'Species (M)', 'Nickname (Species) (F) @ Item', etc."""
    item = None
    if " @ " in line:
        line, item = line.rsplit(" @ ", 1)
        item = item.strip()
    line = line.strip()
    gender = None
    gm = re.search(r"\s*\(([MF])\)\s*$", line)
    if gm:
        gender = gm.group(1)
        line = line[: gm.start()].strip()
    sm = re.match(r"^(.*?)\s*\(([^()]+)\)\s*$", line)
    if sm and sm.group(1).strip():
        nickname = sm.group(1).strip()
        species = sm.group(2).strip()
    else:
        nickname = ""
        species = line.strip()
    return species, nickname, gender, item


def parse_ivs_evs(value: str, default_val: int):
    arr = [default_val] * 6
    for token in value.split("/"):
        token = token.strip()
        m = re.match(r"(\d+)\s+(\w+)", token)
        if not m:
            continue
        n = int(m.group(1))
        label = m.group(2).upper()
        idx = STAT_LABELS.get(label)
        if idx is not None:
            arr[idx] = n
    return arr


def resolve_ai_flags(value: str) -> int:
    flags = 0
    for token in value.split("/"):
        key = normalize(token)
        flags |= AI_TOKEN_MAP.get(key, 0)
    return flags


def compute_fallback_moveset(dex: int, level: int, learnsets: dict) -> list:
    """Reproduces GiveBoxMonInitialMoveset (pokemon.c): walk the species'
    level-up learnset from level 1 upward, keeping only the last 4 moves
    learned at or before `level` (a 4-slot FIFO)."""
    entry = learnsets.get(str(dex))
    if not entry:
        return []
    fifo = []
    for lm in entry["moves"]:
        if lm["level"] > level:
            break
        fifo.append(lm["move_id"])
        if len(fifo) > 4:
            fifo.pop(0)
    return fifo


class NameResolver:
    def __init__(self):
        self.species_map = load_species_map()
        self.move_map = load_tres_name_map("moves", "move_name")
        self.item_map = load_tres_name_map("items", "item_name")
        self.ability_map = load_tres_name_map("abilities", "ability_name")
        self.learnsets = load_learnsets()
        self.unresolved = []

    def species(self, raw):
        key = clean_token(raw, "SPECIES_")
        dex = self.species_map.get(key)
        if dex is None:
            self.unresolved.append(("species", raw))
        return dex

    def move(self, raw):
        key = clean_token(raw, "MOVE_")
        mid = self.move_map.get(key)
        if mid is None:
            self.unresolved.append(("move", raw))
        return mid

    def item(self, raw):
        key = clean_token(raw, "ITEM_")
        iid = self.item_map.get(key)
        if iid is None:
            self.unresolved.append(("item", raw))
        return iid

    def ability(self, raw):
        key = clean_token(raw, "ABILITY_")
        aid = self.ability_map.get(key)
        if aid is None:
            self.unresolved.append(("ability", raw))
        return aid


def parse_pokemon_block(lines, resolver: NameResolver):
    headline = lines[0]
    species_raw, nickname, gender_letter, item_raw = parse_headline(headline)
    dex = resolver.species(species_raw)

    level = 100
    ability_id = 0
    nature = 0
    ivs = [31] * 6
    evs = [0] * 6
    friendship = 0
    is_shiny = False
    ball_name = "Poke"
    move_ids = []

    for line in lines[1:]:
        if line.startswith("- "):
            move_raw = line[2:].strip()
            mid = resolver.move(move_raw)
            if mid is not None:
                move_ids.append(mid)
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if key == "Level":
            level = int(value)
        elif key == "Ability":
            aid = resolver.ability(value)
            if aid is not None:
                ability_id = aid
        elif key == "IVs":
            ivs = parse_ivs_evs(value, 31)
        elif key == "EVs":
            evs = parse_ivs_evs(value, 0)
        elif key == "Ball":
            ball_name = value
        elif key == "Happiness":
            friendship = int(value)
        elif key == "Nature":
            nkey = clean_token(value, "NATURE_")
            if nkey in NATURES:
                nature = NATURES.index(nkey)
        elif key == "Shiny":
            is_shiny = value.strip().lower() == "yes"
        # Dynamax Level / Gigantamax / Tera Type -- deliberately not
        # modeled (0 real uses across the whole roster, confirmed via
        # direct grep; also already-excluded mechanics for this project).

    held_item_id = resolver.item(item_raw) if item_raw else 0
    gender = -1
    if gender_letter == "M":
        gender = 0  # BattlePokemon.GENDER_MALE
    elif gender_letter == "F":
        gender = 1  # BattlePokemon.GENDER_FEMALE

    if not move_ids and dex is not None:
        move_ids = compute_fallback_moveset(dex, level, resolver.learnsets)

    return {
        "species_dex": dex if dex is not None else 0,
        "level": level,
        "nickname": nickname,
        "move_ids": move_ids,
        "held_item_id": held_item_id or 0,
        "ability_id": ability_id,
        "nature": nature,
        "ivs": ivs,
        "evs": evs,
        "friendship": friendship,
        "gender": gender,
        "is_shiny": is_shiny,
        "ball_name": ball_name,
    }


def parse_trainer(key, body, resolver: NameResolver, class_id_by_key):
    groups = group_by_blank_lines(body)
    if not groups:
        return None
    fields = parse_field_lines(groups[0])

    trainer_name = fields.get("Name", "")
    class_raw = fields.get("Class", "")
    class_key = "TRAINER_CLASS_" + normalize(class_raw) if class_raw else None
    # normalize() strips spaces/punctuation the same way fprint_constant
    # does, but class_key here needs underscores re-inserted the way the
    # real constant name has them -- since class_id_by_key is itself keyed
    # by the real TRAINER_CLASS_XXX (with underscores) we instead rebuild
    # the lookup key the same way fprint_constant would (spaces -> _).
    class_const = None
    if class_raw:
        conv = re.sub(r"[^A-Za-z0-9]", "_", class_raw.upper()).strip("_")
        conv = re.sub(r"_+", "_", conv)
        class_const = "TRAINER_CLASS_" + conv
    trainer_class_id = class_id_by_key.get(class_const, 0)

    pic_raw = fields.get("Pic", "")

    gender = -1
    g = fields.get("Gender", "")
    if g.strip().lower() == "male":
        gender = 0
    elif g.strip().lower() == "female":
        gender = 1

    is_doubles = fields.get("Double Battle", "No").strip().lower() == "yes"
    ai_flags = resolve_ai_flags(fields.get("AI", ""))
    mugshot_color = fields.get("Mugshot", "")

    battle_items = []
    items_raw = fields.get("Items", "")
    if items_raw:
        for tok in items_raw.split("/"):
            tok = tok.strip()
            if not tok:
                continue
            iid = resolver.item(tok)
            if iid is not None:
                battle_items.append(iid)

    party = [parse_pokemon_block(g, resolver) for g in groups[1:]]

    return {
        "trainer_key": key,
        "trainer_name": trainer_name,
        "trainer_class_id": trainer_class_id,
        "pic_raw": pic_raw,
        "gender": gender,
        "is_doubles": is_doubles,
        "ai_flags": ai_flags,
        "mugshot_color": mugshot_color,
        "battle_items": battle_items,
        "party": party,
    }


# ---------------------------------------------------------------------------
# .tres rendering
# ---------------------------------------------------------------------------

def render_int_array(vals):
    return "Array[int]([" + ", ".join(str(v) for v in vals) + "])"


def render_party_mon_sub_resource(sub_id: str, mon: dict) -> str:
    lines = [f'[sub_resource type="Resource" id="{sub_id}"]']
    lines.append('script = ExtResource("2")')
    lines.append(f"species_dex = {mon['species_dex']}")
    if mon["level"] != 100:
        lines.append(f"level = {mon['level']}")
    if mon["nickname"]:
        lines.append(f'nickname = "{escape_tres_string(mon["nickname"])}"')
    if mon["move_ids"]:
        lines.append(f"move_ids = {render_int_array(mon['move_ids'])}")
    if mon["held_item_id"]:
        lines.append(f"held_item_id = {mon['held_item_id']}")
    if mon["ability_id"]:
        lines.append(f"ability_id = {mon['ability_id']}")
    if mon["nature"]:
        lines.append(f"nature = {mon['nature']}")
    if mon["ivs"] != [31] * 6:
        lines.append(f"ivs = {render_int_array(mon['ivs'])}")
    if mon["evs"] != [0] * 6:
        lines.append(f"evs = {render_int_array(mon['evs'])}")
    if mon["friendship"]:
        lines.append(f"friendship = {mon['friendship']}")
    if mon["gender"] != -1:
        lines.append(f"gender = {mon['gender']}")
    if mon["is_shiny"]:
        lines.append("is_shiny = true")
    if mon["ball_name"] and mon["ball_name"] != "Poke":
        lines.append(f'ball_name = "{escape_tres_string(mon["ball_name"])}"')
    return "\n".join(lines)


def render_trainer_tres(trainer_id: int, t: dict, pic_id_by_name: dict) -> str:
    n = len(t["party"])
    load_steps = 2 + n + 1  # main script + party-mon script + N sub-resources
    lines = []
    lines.append(f'[gd_resource type="Resource" script_class="TrainerData" load_steps={load_steps} format=3]')
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://scripts/data/trainer_data.gd" id="1"]')
    lines.append('[ext_resource type="Script" path="res://scripts/data/trainer_party_mon.gd" id="2"]')
    lines.append("")

    sub_ids = []
    for i, mon in enumerate(t["party"]):
        sub_id = f"PartyMon_{i}"
        sub_ids.append(sub_id)
        lines.append(render_party_mon_sub_resource(sub_id, mon))
        lines.append("")

    lines.append("[resource]")
    lines.append('script = ExtResource("1")')
    lines.append(f"trainer_id = {trainer_id}")
    lines.append(f'trainer_key = "{t["trainer_key"]}"')
    if t["trainer_name"]:
        lines.append(f'trainer_name = "{escape_tres_string(t["trainer_name"])}"')
    if t["trainer_class_id"]:
        lines.append(f"trainer_class_id = {t['trainer_class_id']}")
    pic_id = pic_id_by_name.get(t["pic_raw"], 0)
    if pic_id:
        lines.append(f"trainer_pic_id = {pic_id}")
    if t["gender"] != -1:
        lines.append(f"gender = {t['gender']}")
    if t["is_doubles"]:
        lines.append("is_doubles = true")
    if t["ai_flags"]:
        lines.append(f"ai_flags = {t['ai_flags']}")
    if t["battle_items"]:
        lines.append(f"battle_items = {render_int_array(t['battle_items'])}")
    if t["mugshot_color"]:
        lines.append(f'mugshot_color = "{escape_tres_string(t["mugshot_color"])}"')
    if sub_ids:
        refs = ", ".join(f'SubResource("{sid}")' for sid in sub_ids)
        lines.append(f"party = Array[Resource]([{refs}])")
    lines.append("")
    return "\n".join(lines)


def render_trainer_pic_tres(pic_id: int, pic_name: str) -> str:
    lines = []
    lines.append('[gd_resource type="Resource" script_class="TrainerPicData" load_steps=2 format=3]')
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://scripts/data/trainer_pic_data.gd" id="1"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1")')
    lines.append(f"pic_id = {pic_id}")
    lines.append(f'pic_name = "{escape_tres_string(pic_name)}"')
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    os.makedirs(OUT_TRAINERS, exist_ok=True)
    os.makedirs(OUT_TRAINER_CLASSES, exist_ok=True)
    os.makedirs(OUT_TRAINER_PICS, exist_ok=True)

    class_id_by_key, class_count = emit_trainer_classes()

    resolver = NameResolver()
    raw_trainers = parse_trainers_party()

    parsed = [parse_trainer(key, body, resolver, class_id_by_key) for key, body in raw_trainers]

    # Stable IDs: sorted-alphabetical index of the trainer_key strings (per
    # docs/m24_recon.md's own recommendation) -- NOT raw file order.
    parsed.sort(key=lambda t: t["trainer_key"])

    # Trainer-pic IDs: a SEPARATE id space, likewise sorted-alphabetical by
    # the distinct Pic string itself.
    distinct_pics = sorted({t["pic_raw"] for t in parsed if t["pic_raw"]})
    pic_id_by_name = {name: idx for idx, name in enumerate(distinct_pics)}
    for idx, name in enumerate(distinct_pics):
        text = render_trainer_pic_tres(idx, name)
        out_path = os.path.join(OUT_TRAINER_PICS, f"trainer_pic_{idx:04d}.tres")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(text)

    for trainer_id, t in enumerate(parsed):
        text = render_trainer_tres(trainer_id, t, pic_id_by_name)
        out_path = os.path.join(OUT_TRAINERS, f"trainer_{trainer_id:04d}.tres")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(text)

    print(f"trainer classes: {class_count} emitted")
    print(f"trainer pics: {len(distinct_pics)} distinct emitted")
    print(f"trainers: {len(parsed)} emitted")
    if resolver.unresolved:
        print(f"UNRESOLVED NAMES: {len(resolver.unresolved)}")
        seen = set()
        for kind, raw in resolver.unresolved:
            k = (kind, raw)
            if k in seen:
                continue
            seen.add(k)
            print(f"  [{kind}] {raw!r}")
        if len(seen) > 40:
            print(f"  ... ({len(seen)} distinct unresolved total)")


if __name__ == "__main__":
    main()
