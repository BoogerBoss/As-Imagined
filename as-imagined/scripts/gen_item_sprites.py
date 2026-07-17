#!/usr/bin/env python3
"""
Copies item icon sprites from the read-only reference clone into a
project-owned, git-tracked asset directory, keyed to ItemData.item_id.

Usage (from project root):
    python3 scripts/gen_item_sprites.py

Scope: only the items this project's own ItemData/ItemRegistry actually
models (real data/items/item_NNNN.tres files on disk, 160 as of this
script's writing -- NOT the full ~919-item reference roster, which
includes many key items/battle-irrelevant items this project has no data
for at all). The set is read directly from data/items/ at run time, so
this script self-updates as future M18+/M25 sessions add more items --
no hardcoded ID list to maintain here.

Mapping approach (same "join literal source strings, never guess a name
transform" discipline as gen_pokemon_sprites.py) -- a real correction to
this project's own prior scoping note: reference/pokeemerald_expansion/
src/data/item_icon_table.h, previously assumed to be a direct ITEM_X ->
icon-path table, is actually EMPTY in this checkout (confirmed by
inspection, not assumed). The real mapping lives inline in
src/data/items.h's own per-item struct blocks instead -- the same
"identifier declared inline in the main data table" shape
species_info.h uses for Pokémon (.frontPic there, .iconPic here). Three
files, joined:

  1. include/constants/items.h's `enum Item` -> ITEM_X identifier to
     numeric ID (unlike species' NATIONAL_DEX_X ordinals, every ITEM_X
     here has an explicit `= N` literal -- no ordinal-counting needed).
  2. src/data/items.h's `[ITEM_X] = { ..., .iconPic = gItemIcon_<Name>,
     ... }` block -> ITEM_X identifier to icon identifier.
  3. src/data/graphics/items.h's `const u32 gItemIcon_<Name>[] =
     INCGFX_U32("graphics/items/icons/<file>.png", ...)` declaration ->
     icon identifier to the literal, authoritative icon filename (never
     reconstructed from the identifier's own PascalCase spelling).

Idempotent: re-running overwrites the destination files with a fresh copy
from source, so reruns are safe.
"""

import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "..", "reference", "pokeemerald_expansion")
ITEMS_CONST_H = os.path.join(REF, "include", "constants", "items.h")
ITEMS_H = os.path.join(REF, "src", "data", "items.h")
GRAPHICS_H = os.path.join(REF, "src", "data", "graphics", "items.h")
ICON_SRC_DIR = os.path.join(REF, "graphics", "items", "icons")

REAL_ITEMS_DIR = os.path.join(ROOT, "data", "items")
DEST_DIR = os.path.join(ROOT, "assets", "sprites", "items")


def build_real_item_ids():
    """The authoritative scope: every item this project's own ItemData
    actually models, read directly from data/items/*.tres -- not the
    reference tree's full roster."""
    ids = []
    for filename in os.listdir(REAL_ITEMS_DIR):
        m = re.match(r"item_(\d+)\.tres", filename)
        if m:
            ids.append(int(m.group(1)))
    return sorted(ids)


def build_id_by_identifier():
    # Two-pass resolution: most entries are plain `ITEM_X = N` literals, but
    # some (e.g. `ITEM_CHERI_BERRY = FIRST_BERRY_INDEX`, a real item in this
    # project's scope) alias ANOTHER identifier instead of a literal --
    # confirmed via a full grep that every such alias in this file is
    # single-level (never a chain of aliases), so one resolution pass over
    # the not-yet-resolved entries is sufficient. The bulk of the other
    # aliases here are deprecated pre-Gen-VI/VII/VIII old item names
    # (ITEM_ENERGYPOWDER = ITEM_ENERGY_POWDER, etc.) -- irrelevant to this
    # project's own item IDs, which were assigned using the canonical
    # modern identifiers, but resolved here anyway since it costs nothing.
    with open(ITEMS_CONST_H, encoding="utf-8") as f:
        content = f.read()
    enum_m = re.search(r"enum(?:\s+__attribute__\(\(packed\)\))?\s+Item\s*\{(.*?)\n\};", content, re.DOTALL)
    body = enum_m.group(1)

    # The lookup dict must also hold non-ITEM_-prefixed marker constants
    # (FIRST_BERRY_INDEX, FIRST_MAIL_INDEX, ...) since aliases resolve
    # against THOSE, not just other ITEM_X names -- caught via a first
    # attempt that only captured ITEM_-prefixed identifiers, which left
    # FIRST_BERRY_INDEX itself unresolvable and broke ITEM_CHERI_BERRY's
    # own alias chain.
    all_by_identifier = {}
    unresolved = []
    for m in re.finditer(r"(\w+)\s*=\s*(\w+)", body):
        identifier, value = m.group(1), m.group(2)
        if value.isdigit():
            all_by_identifier[identifier] = int(value)
        else:
            unresolved.append((identifier, value))

    for identifier, alias_target in unresolved:
        if alias_target in all_by_identifier:
            all_by_identifier[identifier] = all_by_identifier[alias_target]

    return {k: v for k, v in all_by_identifier.items() if k.startswith("ITEM_")}


def build_icon_identifier_by_item_id(id_by_identifier):
    with open(ITEMS_H, encoding="utf-8") as f:
        content = f.read()
    block_starts = [m.start() for m in re.finditer(r"\n    \[ITEM_\w+\]\s*=\s*\n    \{", content)]
    icon_identifier_by_id = {}
    for i, start in enumerate(block_starts):
        end = block_starts[i + 1] if i + 1 < len(block_starts) else len(content)
        block = content[start:end]
        item_m = re.match(r"\n    \[(ITEM_\w+)\]", block)
        icon_m = re.search(r"\.iconPic\s*=\s*gItemIcon_(\w+)", block)
        if not item_m or not icon_m:
            continue
        item_id = id_by_identifier.get(item_m.group(1))
        if item_id is None:
            continue
        icon_identifier_by_id[item_id] = icon_m.group(1)
    return icon_identifier_by_id


def build_filename_by_icon_identifier():
    with open(GRAPHICS_H, encoding="utf-8") as f:
        content = f.read()
    pairs = re.findall(
        r'const u32 gItemIcon_(\w+)\[\]\s*=\s*INCGFX_U32\("graphics/items/icons/([\w.\-]+)\.png"',
        content,
    )
    filename_by_identifier = {}
    for identifier, filename in pairs:
        if identifier not in filename_by_identifier:
            filename_by_identifier[identifier] = filename
    return filename_by_identifier


def main():
    real_item_ids = build_real_item_ids()
    id_by_identifier = build_id_by_identifier()
    icon_identifier_by_id = build_icon_identifier_by_item_id(id_by_identifier)
    filename_by_icon_identifier = build_filename_by_icon_identifier()

    missing = []
    resolved = {}
    for item_id in real_item_ids:
        icon_identifier = icon_identifier_by_id.get(item_id)
        filename = filename_by_icon_identifier.get(icon_identifier) if icon_identifier else None
        if filename is None:
            missing.append(item_id)
            continue
        resolved[item_id] = filename

    if missing:
        raise SystemExit(f"ERROR: could not resolve an icon filename for item IDs: {missing}")

    os.makedirs(DEST_DIR, exist_ok=True)

    copied = 0
    missing_files = []
    for item_id, filename in resolved.items():
        src = os.path.join(ICON_SRC_DIR, filename + ".png")
        if not os.path.isfile(src):
            missing_files.append(src)
            continue
        dst = os.path.join(DEST_DIR, "%04d_%s.png" % (item_id, filename))
        shutil.copyfile(src, dst)
        copied += 1

    if missing_files:
        raise SystemExit(
            "ERROR: %d expected source icon files were missing:\n%s"
            % (len(missing_files), "\n".join(missing_files[:20]))
        )

    print(f"item icons: {copied} files copied ({len(real_item_ids)} real item IDs in scope, "
          f"{len(resolved)} resolved) into {os.path.relpath(DEST_DIR, ROOT)}")


if __name__ == "__main__":
    main()
