#!/usr/bin/env python3
"""
Copies front/back/icon sprites (classic GBA art style) for all 386
in-scope species from the read-only reference clone into a project-owned,
git-tracked asset directory.

Usage (from project root):
    python3 scripts/gen_pokemon_sprites.py

Why this exists: reference/pokeemerald_expansion/ is .gitignore'd ("large,
and not ours to version") and Godot's own .gdignore keeps the editor from
importing it directly -- so nothing in this project can reference sprite
paths under reference/ directly without silently breaking for anyone
without that exact local clone present. This script performs a one-time
(re-runnable, idempotent) copy of just the files this project actually
needs into res://assets/sprites/pokemon/, which IS committed.

[Switched modern-style -> GBA-style] The original pull used the modern
art style; switched to GBA style after a real screenshot check (M23.11
Phase 4a) found the modern-style PNGs have NO alpha transparency at all
(confirmed via direct pixel inspection -- every sprite renders as a solid
colored rectangle, not a silhouette). GBA-style sprites were independently
confirmed transparent (palette index 0 tagged transparent) during this
project's very first sprite-format investigation.

Mapping approach (matches [M19-pre1]'s gen_weight_data.py precedent --
parses source directly since no rerunnable extractor for this exists in
this repo): a two-file join, not a guessed name transform. A naive
lowercase of the species' display/identifier name is NOT safe (e.g.
identifier "NidoranF" -> real directory slug "nidoran_f", not "nidoranf"),
so the real directory slug is read directly from the literal path string
in source, never reconstructed:

  1. include/constants/pokedex.h's NationalDexOrder enum -> ordinal dex
     number per NATIONAL_DEX_X constant (identical logic to
     gen_weight_data.py's build_dex_ordinal_map).
  2. src/data/pokemon/species_info/gen_{1,2,3}_families.h -> each species
     block's .natDexNum resolves to a dex number, and its
     .frontPic = gMonFrontPic_<Identifier> line gives the C identifier
     used for that species' sprite data.
  3. src/data/graphics/pokemon.h -> the identifier's own
     `const u32 gMonFrontPic_<Identifier>[] = INCGFX_U32("graphics/
     pokemon/<slug>/anim_front.png", ...)` declaration gives the literal,
     authoritative directory slug. Deliberately still anchored to the
     non-GBA-style #if branch's own path string here -- this step only
     resolves the DIRECTORY (style-independent, both anim_front.png and
     anim_front_gba.png live in the same per-species folder), not which
     literal file within it gets copied (that's ASSET_KINDS, below).

GBA_FILENAME_OVERRIDES handles the (species, kind) pairs where a plain
"swap the filename" doesn't hold -- confirmed by a full coverage check
against all 386 already-pulled species before switching styles, not
assumed:
  - Unown (#201): has NO _gba variant of ANYTHING (no anim_front_gba.png,
    back_gba.png, or icon_gba.png) -- only plain, style-agnostic
    front.png/back.png/icon.png (its real per-letter-form art lives in
    subdirectories out of this project's scope; the base slug's own files
    are apparently shared across both style toggles).
  - Castform (#351): has a GBA-style front, but named "front_gba.png" --
    no "anim_" prefix, and confirmed via direct pixel inspection to be a
    single 64x64 frame, not the usual 2-frame 64x128 sheet every other
    species has (Castform's real in-game animation is weather-form-linked
    rather than the standard idle-bob). This needs no special handling on
    the SpriteRegistry/consumer side -- slicing a Rect2(0,0,64,64) region
    out of an already-64x64 source correctly returns the whole image.

Unown (#201) is ALSO hardcoded for slug resolution (slug "unown") --
its species block uses the UNOWN_MISC_INFO macro instead of a plain
struct literal, the same extractor blind spot gen_weight_data.py already
documents for every other field.

Idempotent: re-running overwrites the destination files with a fresh copy
from source, so reruns (e.g. after a `git pull` inside the reference
clone, or a future style change) are safe.
"""

import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "..", "reference", "pokeemerald_expansion")
POKEDEX_H = os.path.join(REF, "include", "constants", "pokedex.h")
FAMILY_FILES = [
    os.path.join(REF, "src", "data", "pokemon", "species_info", f"gen_{n}_families.h")
    for n in (1, 2, 3)
]
GRAPHICS_H = os.path.join(REF, "src", "data", "graphics", "pokemon.h")
SPRITE_SRC_DIR = os.path.join(REF, "graphics", "pokemon")

DEST_DIR = os.path.join(ROOT, "assets", "sprites", "pokemon")
ASSET_KINDS = {
    "front": "anim_front_gba.png",
    "back": "back_gba.png",
    "icon": "icon_gba.png",
}

UNOWN_DEX = 201
UNOWN_SLUG = "unown"
CASTFORM_DEX = 351

# (dex, kind) -> filename override, for species where the default
# ASSET_KINDS filename doesn't exist under GBA style -- see the module
# doc comment above for the full explanation of each entry.
GBA_FILENAME_OVERRIDES = {
    (UNOWN_DEX, "front"): "front.png",
    (UNOWN_DEX, "back"): "back.png",
    (UNOWN_DEX, "icon"): "icon.png",
    (CASTFORM_DEX, "front"): "front_gba.png",
}

# [M23.11 Phase 4a] dex 0 is not a real species -- it's the fallback used
# by SpriteRegistry whenever a BattlePokemon's species has no resolvable
# dex number (e.g. battle_screen.gd's own hardcoded fixture teams, built
# via plain PokemonSpecies.new() rather than PokemonFactory, never set
# national_dex_num, leaving it at its default 0). graphics/pokemon/
# question_mark/circled/ is the reference engine's own classic "unknown
# Pokémon" silhouette -- same anim_front.png/back.png shape as every real
# species, no special slicing/format handling needed. Icon deliberately
# NOT pulled here (no icon.png exists in this specific subdirectory, and
# SpriteRegistry itself doesn't build get_icon() as of Phase 4a either --
# nothing consumes it yet).
UNKNOWN_DEX = 0
UNKNOWN_SLUG = "unknown"
UNKNOWN_SRC_SLUG = "question_mark/circled"


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


def build_identifier_by_dex(dex_ordinal):
    dex_to_identifier = {}
    for path in FAMILY_FILES:
        with open(path, encoding="utf-8") as f:
            content = f.read()
        block_starts = [m.start() for m in re.finditer(r"\n    \[SPECIES_\w+\]\s*=\s*\n    \{", content)]
        for i, start in enumerate(block_starts):
            end = block_starts[i + 1] if i + 1 < len(block_starts) else len(content)
            block = content[start:end]
            ndm = re.search(r"\.natDexNum\s*=\s*(NATIONAL_DEX_\w+)", block)
            fpm = re.search(r"\.frontPic\s*=\s*gMonFrontPic_(\w+)", block)
            if not ndm or not fpm:
                continue
            dex = dex_ordinal.get(ndm.group(1))
            if dex is None or not (1 <= dex <= 386):
                continue
            if dex not in dex_to_identifier:
                dex_to_identifier[dex] = fpm.group(1)
    return dex_to_identifier


def build_slug_by_identifier():
    with open(GRAPHICS_H, encoding="utf-8") as f:
        content = f.read()
    # Non-GBA-style branch specifically (modern art style) -- the literal
    # path string IS the authoritative directory slug, never reconstructed
    # from the identifier's own PascalCase spelling.
    pairs = re.findall(
        r'const u32 gMonFrontPic_(\w+)\[\]\s*=\s*INCGFX_U32\("graphics/pokemon/([\w./]+)/anim_front\.png"',
        content,
    )
    slug_by_identifier = {}
    for identifier, slug in pairs:
        if identifier not in slug_by_identifier:
            slug_by_identifier[identifier] = slug
    return slug_by_identifier


def main():
    dex_ordinal = build_dex_ordinal_map()
    dex_to_identifier = build_identifier_by_dex(dex_ordinal)
    slug_by_identifier = build_slug_by_identifier()

    dex_to_slug = {UNOWN_DEX: UNOWN_SLUG}
    for dex, identifier in dex_to_identifier.items():
        slug = slug_by_identifier.get(identifier)
        if slug is not None:
            dex_to_slug[dex] = slug

    missing = sorted(set(range(1, 387)) - set(dex_to_slug.keys()))
    if missing:
        raise SystemExit(f"ERROR: could not resolve a sprite directory for dex numbers: {missing}")

    for kind in ASSET_KINDS:
        os.makedirs(os.path.join(DEST_DIR, kind), exist_ok=True)

    copied = 0
    missing_files = []
    for dex in range(1, 387):
        slug = dex_to_slug[dex]
        for kind, default_filename in ASSET_KINDS.items():
            filename = GBA_FILENAME_OVERRIDES.get((dex, kind), default_filename)
            src = os.path.join(SPRITE_SRC_DIR, slug, filename)
            if not os.path.isfile(src):
                missing_files.append(src)
                continue
            dst = os.path.join(DEST_DIR, kind, "%04d_%s.png" % (dex, slug))
            shutil.copyfile(src, dst)
            copied += 1

    # dex 0 fallback -- front + back only (see UNKNOWN_* constants' own
    # comment above for why icon is excluded). question_mark/circled/ has
    # real _gba variants for both (confirmed by inspection), no override
    # needed here.
    for kind in ("front", "back"):
        filename = ASSET_KINDS[kind]
        src = os.path.join(SPRITE_SRC_DIR, UNKNOWN_SRC_SLUG, filename)
        if not os.path.isfile(src):
            missing_files.append(src)
            continue
        dst = os.path.join(DEST_DIR, kind, "%04d_%s.png" % (UNKNOWN_DEX, UNKNOWN_SLUG))
        shutil.copyfile(src, dst)
        copied += 1

    if missing_files:
        raise SystemExit(
            "ERROR: %d expected source sprite files were missing:\n%s"
            % (len(missing_files), "\n".join(missing_files[:20]))
        )

    print(f"pokemon sprites: {copied} files copied ({len(dex_to_slug)} dex numbers resolved, "
          f"{len(ASSET_KINDS)} asset kinds each, plus the dex-0 unknown fallback front+back) "
          f"into {os.path.relpath(DEST_DIR, ROOT)}")


if __name__ == "__main__":
    main()
