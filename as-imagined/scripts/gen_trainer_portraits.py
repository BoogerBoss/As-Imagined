#!/usr/bin/env python3
"""
[M23.11 Phase 3] Copies trainer front-pic portrait art (the same sprite the
reference engine reuses for its in-battle "Mugshot" transition effect --
see the module docstring correction below) for all 93 trainer_pic entries
from the read-only reference clone into a project-owned, git-tracked asset
directory.

Usage (from project root):
    python3 scripts/gen_trainer_portraits.py

Why this exists: same rationale as gen_pokemon_sprites.py -- reference/
pokeemerald_expansion/ is .gitignore'd and not directly usable by
production code, so this performs a one-time (re-runnable, idempotent)
copy of just the files this project actually needs into
res://assets/sprites/trainers/portraits/, which IS committed.

[Mugshot correction, found during this session's own Step 0] "Mugshot" is
NOT a separate small portrait asset -- confirmed via direct source read
(src/data/graphics/trainers.h's own TRAINER_FRONT_PIC macro comment: "The
last three parameters control the X and Y coordinates and rotation of the
MUGSHOT on the screen"). The reference engine's gym-leader mugshot
transition literally reuses each trainer's own front-pic sprite (with a
per-trainer coordinate/rotation offset for the slide-in animation), not a
dedicated portrait asset. So there is only ONE portrait asset type to pull
here -- the 64x64 front_pics sprite -- not two.

Mapping approach (a three-file join, not a guessed name transform, mirroring
gen_weight_data.py/gen_pokemon_sprites.py's own precedent of parsing source
directly rather than trusting a filename convention blind):
  1. data/trainer_pics/*.tres's own `pic_name` field (e.g. "Leader Brawly",
     "Swimmer M") -- the exact same human string trainers.party's own
     "Pic:" field carries.
  2. Reproduce tools/trainerproc/main.c's own `fprint_constant(f,
     "TRAINER_PIC", trainer->pic)` transform (uppercase alnum, non-alnum
     collapsed to a single underscore -- the identical transform
     gen_trainer_data.py already reproduces for the Class: field) to get
     the real TRAINER_PIC_XXX constant name trainerproc itself would emit.
  3. src/data/graphics/trainers.h's own `gTrainerPicInfo[]` designated-
     initializer array: [TRAINER_PIC_XXX] = { .frontPic =
     TRAINER_FRONT_PIC(gTrainerFrontPic_YYY, ...) } gives TRAINER_PIC_XXX
     -> gTrainerFrontPic_YYY.
  4. The same file's own `const u32 gTrainerFrontPic_YYY[] =
     INCGFX_U32("graphics/trainers/front_pics/FILENAME.png", ...)`
     declaration gives gTrainerFrontPic_YYY -> the real, authoritative
     filename.

Confirmed via direct inspection before writing this script (not assumed):
all 93 resolved files are UNIFORMLY 64x64, indexed-palette ("P" mode) PNGs
with a `transparency` chunk tagging palette index 0 as transparent (the
same palette-index-0-transparent convention gen_pokemon_sprites.py's own
GBA-style sprites use) -- confirmed via direct pixel/palette inspection
that the transparent index is actually used at the sprite's corners. No
per-entry overrides were needed (unlike the Pokémon sprite pull's Unown/
Castform exceptions) -- every one of the 93 is a plain flat copy.

Naming convention (mirrors assets/sprites/pokemon/'s own
"<zero-padded-id>_<slug>.png" scheme exactly, so TrainerPicRegistry's own
lazy directory-scan-and-cache lookup -- see sprite_registry.gd's own
precedent -- can key purely off the leading numeric prefix): output
filename is f"{pic_id:04d}_{source_stem}.png", where source_stem is the
source's own front_pics/<source_stem>.png filename stem verbatim (already
snake_case, e.g. "leader_brawly", "aroma_lady") -- not re-slugified from
pic_name, so it stays directly traceable back to the exact source file.

Idempotent: re-running overwrites the destination files with a fresh copy.
"""

import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "reference", "pokeemerald_expansion")
TRAINERS_GFX_H = os.path.join(REF, "src", "data", "graphics", "trainers.h")
TRAINER_PICS_DIR = os.path.join(ROOT, "data", "trainer_pics")
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "trainers", "portraits")


def normalize_to_constant(name: str) -> str:
    """Reproduces tools/trainerproc/main.c's own fprint_constant() transform
    for the TRAINER_PIC prefix: uppercase alnum, everything else collapses
    to underscores (apostrophes just drop in the real tool, but no trainer
    pic name in this roster contains one, so that nuance doesn't matter
    here)."""
    conv = re.sub(r"[^A-Za-z0-9]", "_", name.upper()).strip("_")
    conv = re.sub(r"_+", "_", conv)
    return "TRAINER_PIC_" + conv


def build_pic_to_file_map():
    with open(TRAINERS_GFX_H, encoding="utf-8") as f:
        content = f.read()

    frontpic_to_file = {}
    for m in re.finditer(r'const u32 (gTrainerFrontPic_\w+)\[\]\s*=\s*INCGFX_U32\("([^"]+)"', content):
        frontpic_to_file[m.group(1)] = m.group(2)

    start = content.index("const struct TrainerPicInfo gTrainerPicInfo[TRAINER_PIC_COUNT] =")
    end = content.index("\n};", start)
    body = content[start:end]

    pic_to_frontpic = {}
    for m in re.finditer(r"\[(TRAINER_PIC_\w+)\]\s*=\s*\{(.*?)\n\s*\},", body, re.DOTALL):
        fm = re.search(r"TRAINER_FRONT_PIC\((gTrainerFrontPic_\w+)", m.group(2))
        if fm:
            pic_to_frontpic[m.group(1)] = fm.group(1)

    pic_to_file = {}
    for pic_const, frontpic_sym in pic_to_frontpic.items():
        rel = frontpic_to_file.get(frontpic_sym)
        if rel:
            pic_to_file[pic_const] = rel
    return pic_to_file


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    pic_to_file = build_pic_to_file_map()

    copied = 0
    unresolved = []
    for fn in sorted(os.listdir(TRAINER_PICS_DIR)):
        if not fn.endswith(".tres"):
            continue
        idm = re.search(r"_(\d+)\.tres$", fn)
        pic_id = int(idm.group(1))
        text = open(os.path.join(TRAINER_PICS_DIR, fn), encoding="utf-8").read()
        name_m = re.search(r'pic_name = "(.*)"', text)
        pic_name = name_m.group(1)

        const = normalize_to_constant(pic_name)
        rel_path = pic_to_file.get(const)
        if not rel_path:
            unresolved.append((pic_id, pic_name, const))
            continue

        src_path = os.path.join(REF, rel_path)
        if not os.path.exists(src_path):
            unresolved.append((pic_id, pic_name, const + " (file missing: " + rel_path + ")"))
            continue

        source_stem = os.path.splitext(os.path.basename(rel_path))[0]
        dst_name = f"{pic_id:04d}_{source_stem}.png"
        dst_path = os.path.join(OUT_DIR, dst_name)
        shutil.copyfile(src_path, dst_path)
        copied += 1

    print(f"trainer portraits: {copied} copied, {len(unresolved)} unresolved")
    for pic_id, pic_name, const in unresolved:
        print(f"  UNRESOLVED [{pic_id}] {pic_name!r} -> {const}")


if __name__ == "__main__":
    main()
