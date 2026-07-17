#!/usr/bin/env python3
"""
Copies front/back/icon sprites (modern art style, not the classic-GBA
variant) for all 386 in-scope species from the read-only reference clone
into a project-owned, git-tracked asset directory.

Usage (from project root):
    python3 scripts/gen_pokemon_sprites.py

Why this exists: reference/pokeemerald_expansion/ is .gitignore'd ("large,
and not ours to version") and Godot's own .gdignore keeps the editor from
importing it directly -- so nothing in this project can reference sprite
paths under reference/ directly without silently breaking for anyone
without that exact local clone present. This script performs a one-time
(re-runnable, idempotent) copy of just the files this project actually
needs into res://assets/sprites/pokemon/, which IS committed.

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
     pokemon/<slug>/anim_front.png", ...)` declaration (the non-GBA-style
     #if branch specifically, matching this project's "modern style"
     choice) gives the literal, authoritative directory slug.

Unown (#201) is hardcoded (slug "unown") -- its species block uses the
UNOWN_MISC_INFO macro instead of a plain struct literal, the same
extractor blind spot gen_weight_data.py already documents for every other
field.

Idempotent: re-running overwrites the destination files with a fresh copy
from source, so reruns (e.g. after a `git pull` inside the reference
clone) are safe.
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
    "front": "anim_front.png",
    "back": "back.png",
    "icon": "icon.png",
}

UNOWN_DEX = 201
UNOWN_SLUG = "unown"
# Unown's base directory has a plain front.png, not an animated
# anim_front.png -- it uses per-letter-form subdirectories (a/b/c/...) for
# the actual playable forms, out of scope here (only the base slug is
# pulled, matching every other species' single-entry treatment).
UNOWN_FRONT_FILENAME = "front.png"


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
        for kind, filename in ASSET_KINDS.items():
            if dex == UNOWN_DEX and kind == "front":
                filename = UNOWN_FRONT_FILENAME
            src = os.path.join(SPRITE_SRC_DIR, slug, filename)
            if not os.path.isfile(src):
                missing_files.append(src)
                continue
            dst = os.path.join(DEST_DIR, kind, "%04d_%s.png" % (dex, slug))
            shutil.copyfile(src, dst)
            copied += 1

    if missing_files:
        raise SystemExit(
            "ERROR: %d expected source sprite files were missing:\n%s"
            % (len(missing_files), "\n".join(missing_files[:20]))
        )

    print(f"pokemon sprites: {copied} files copied ({len(dex_to_slug)} dex numbers resolved, "
          f"{len(ASSET_KINDS)} asset kinds each) into {os.path.relpath(DEST_DIR, ROOT)}")


if __name__ == "__main__":
    main()
