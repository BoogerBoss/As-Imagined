#!/usr/bin/env python3
r"""[M36A] Battle-anim metadata extractor: C tables -> tags/templates/frames JSON.

Scope of record: docs/m26_f1_recon.md (M36A = Phase A2). Three outputs under
data/battle_anims/, all consumed by the M36B runtime:

  tags.json      - gBattleAnimTable (src/data/battle_anim.h): ANIM_TAG name ->
                   {index, gfx file, palette file, VRAM size}, with the
                   B_NEW_* ternaries resolved the way this config builds them
                   (every B_NEW_* flag is FALSE -> the `:` branch), the
                   hand-written ANIM_TAG_SAP_DRIP_2 literal entry handled
                   (its PALETTE registers under ANIM_TAG_SAP_DRIP - a real
                   upstream asymmetry, preserved as palette_tag), and the two
                   explicit NULL entries (UNAVAILABLE_1/2) kept as null rows
                   so index arithmetic stays exact.
  templates.json - every `struct SpriteTemplate` across src/battle_anim*.c:
                   tile/palette tags (resolved ints + names), OAM shape
                   decoded from the gOamData_* NAME (the 72 shared OAM defs
                   encode affine mode / obj mode / WxH in the symbol name -
                   verified uniform at authoring time), anims/affineAnims
                   table symbol, callback symbol.
  frames.json    - every ANIMCMD/AFFINEANIMCMD sequence and their pointer
                   tables. ANIMCMD_FRAME's first arg is a TILE offset into
                   the sheet, not a frame ordinal (step 16 for a 32x32
                   sprite); stored verbatim, the runtime divides by the
                   sprite's tiles-per-frame. Optional named flags
                   (.hFlip/.vFlip) become booleans.

Symbol->file binding comes from src/graphics.c's INCGFX lines. Composite
sheets (ice_cube/ice_crystals/mud_sand/flower/spark) are referenced there as
prebuilt `.4bpp` paths; those are recorded with kind="composite" plus their
numbered part-PNG list (from graphics_file_rules.mk's documented recipe) so
the A3 asset pull can assemble them.

Constant resolution reuses gen_battle_anim_scripts' resolver (same headers,
same semantics) rather than duplicating it.

Idempotent; overwrites unconditionally; prints per-file counts.
"""

import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_path import REF, PROJECT, assert_inside_project
from gen_battle_anim_scripts import (
    ConstResolver, load_defines, eval_expr, split_args, CONST_HEADERS,
    _DEFINE_RE)

DATA_BATTLE_ANIM_H = os.path.join(REF, "src", "data", "battle_anim.h")
GRAPHICS_C = os.path.join(REF, "src", "graphics.c")
ANIM_C_GLOB = os.path.join(REF, "src", "battle_anim*.c")

OUT_DIR = assert_inside_project(
    os.path.join(PROJECT, "data", "battle_anims"), "battle_anims data dir")

# The five build-time composite sheets: graphics_file_rules.mk assembles
# these .4bpp files by concatenating numbered part PNGs (part count verified
# on disk by A3). Everything else INCGFX references is a direct .png/.pal.
COMPOSITES = {
    "graphics/battle_anims/sprites/ice_cube.4bpp": 4,
    "graphics/battle_anims/sprites/ice_crystals.4bpp": 5,
    "graphics/battle_anims/sprites/mud_sand.4bpp": 2,
    "graphics/battle_anims/sprites/flower.4bpp": 2,
    "graphics/battle_anims/sprites/spark.4bpp": 2,
}


def file_scoped_resolver(base_defines, text):
    """The battle_anim_*.c files define tuning constants inline
    (#define WOOD_HAMMER_SCALE_STEP 5 ...) that their own frame data then
    uses. Each file gets a resolver seeded with base headers + its own
    defines."""
    defs = dict(base_defines)
    for line in text.splitlines():
        m = _DEFINE_RE.match(line.split("//")[0])
        if m and "(" not in m.group(1):
            expr = re.sub(r"/\*.*?\*/", " ", m.group(2)).strip()
            defs.setdefault(m.group(1), expr)
    return ConstResolver(defs)


def strip_comments(text):
    text = re.sub(r"//[^\n]*", "", text)
    return re.sub(r"/\*.*?\*/", " ", text, flags=re.S)


def parse_incgfx_symbols():
    """src/graphics.c: symbol -> source asset path (INCGFX_U16/U32)."""
    paths = {}
    pat = re.compile(
        r"const\s+u(?:16|32)\s+(\w+)\[\]\s*=\s*INCGFX_U(?:16|32)\(\s*"
        r'"([^"]+)"')
    with open(GRAPHICS_C) as f:
        for line in f:
            m = pat.search(line)
            if m:
                # #if branches bind the same symbol twice (substitute_gba etc.)
                # -- first binding wins, matching the FALSE-config branch order
                # is NOT guaranteed by line order, but no gBattleAnimTable
                # symbol is #if-gated (verified: the gated pairs are
                # substitute/monster_doll, referenced by code not the table).
                paths.setdefault(m.group(1), m.group(2))
    return paths


def resolve_ternary(expr, resolver):
    """Resolve `COND == TRUE ? a : b` table entries; plain symbol passes
    through. All B_NEW_* flags are FALSE in this config (verified by
    resolving the condition rather than assuming)."""
    expr = expr.strip()
    m = re.match(r"^(.*?)\?(.*?):(.*)$", expr, flags=re.S)
    if not m:
        return expr
    cond = bool(eval_expr(m.group(1), resolver))
    return (m.group(2) if cond else m.group(3)).strip()


def parse_tag_table(resolver, sym_paths):
    with open(DATA_BATTLE_ANIM_H) as f:
        text = strip_comments(f.read())

    tags = {}
    # Entries are one per line; iterating lines keeps the multi-line
    # `#define BATTLE_ANIMATION(...)` definition itself out of the match.
    pat = re.compile(r"^\s*BATTLE_ANIMATION\((.+)\),\s*$")
    for line in text.splitlines():
        m = pat.match(line)
        if not m:
            continue
        args = split_args(m.group(1))
        assert len(args) == 4, args
        tag_name, gfx_expr, size_expr, pal_expr = (a.strip() for a in args)
        gfx_sym = resolve_ternary(gfx_expr, resolver)
        pal_sym = resolve_ternary(pal_expr, resolver)
        index = resolver.value(tag_name) - resolver.value("ANIM_SPRITES_START")
        entry = {
            "index": index,
            "size": eval_expr(size_expr, resolver),
            "gfx_symbol": None if gfx_sym == "NULL" else gfx_sym,
            "palette_symbol": None if pal_sym == "NULL" else pal_sym,
            "palette_tag": tag_name,
        }
        for key, sym in (("gfx", entry["gfx_symbol"]),
                         ("palette", entry["palette_symbol"])):
            if sym is None:
                entry[key] = None
            else:
                if sym not in sym_paths:
                    raise SystemExit("no INCGFX binding for %s" % sym)
                entry[key] = sym_paths[sym]
        tags[tag_name] = entry

    # The one hand-written entry: [GET_TRUE_SPRITE_INDEX(ANIM_TAG_SAP_DRIP_2)]
    # = { .pic = {gBattleAnimSpriteGfx_SapDrip, 0x1000, ANIM_TAG_SAP_DRIP_2},
    #     .palette = {gBattleAnimSpritePal_SapDrip2, ANIM_TAG_SAP_DRIP} }.
    hm = re.search(
        r"\[GET_TRUE_SPRITE_INDEX\((\w+)\)\]\s*=\s*\{\s*"
        r"\.pic\s*=\s*\{(\w+),\s*([\w:x]+),\s*(\w+)\},\s*"
        r"\.palette\s*=\s*\{(\w+),\s*(\w+)\},?\s*\}", text)
    if hm:
        tag_name = hm.group(1)
        gfx_sym, pal_sym = hm.group(2), hm.group(5)
        tags[tag_name] = {
            "index": resolver.value(tag_name)
            - resolver.value("ANIM_SPRITES_START"),
            "size": eval_expr(hm.group(3), resolver),
            "gfx_symbol": gfx_sym, "gfx": sym_paths[gfx_sym],
            "palette_symbol": pal_sym, "palette": sym_paths[pal_sym],
            "palette_tag": hm.group(6),
        }
    return tags


_OAM_NAME_RE = re.compile(
    r"gOamData_(Affine\w+?)_(Obj\w+?)_(\d+)x(\d+)$")


def decode_oam_name(name):
    m = _OAM_NAME_RE.match(name)
    if not m:
        return {"raw": name}
    return {"affine": m.group(1), "obj": m.group(2),
            "width": int(m.group(3)), "height": int(m.group(4))}


_INDEXED_REF_RE = re.compile(r"^(\w+)\s*\[\s*(\d+)\s*\]$")


def split_indexed_ref(symbol):
    """`&gAnims_PoisonProjectile[1]` -> ("gAnims_PoisonProjectile", 1).

    Several templates deliberately point PART-WAY into a shared anim table,
    so that sprite's anim 0 is the table's entry N (Acid's droplet reuses
    the poison-projectile table from index 1). Dropping the offset would
    silently play the wrong frames, so it is preserved as an explicit
    offset the runtime adds to its anim number."""
    if symbol is None:
        return None, 0
    m = _INDEXED_REF_RE.match(symbol)
    if m:
        return m.group(1), int(m.group(2))
    return symbol, 0


def resolve_frame_key(symbol, ref_file, table):
    """Resolve a frame-table symbol to its file-qualified key.

    Same-file wins (the file-scoped statics), but several tables are
    NON-STATIC globals defined in one translation unit and referenced from
    another -- e.g. gSolarBeamBigOrbAnimTable lives in battle_anim_effects_1.c
    yet battle_anim_new.c's templates point at it. Falls back to a unique
    cross-file match and refuses to guess when ambiguous."""
    if symbol is None:
        return None
    local = "%s::%s" % (ref_file, symbol)
    if local in table:
        return local
    hits = [k for k in table if k.endswith("::" + symbol)]
    if len(hits) == 1:
        return hits[0]
    if not hits:
        return local  # dangling; the suite reports it rather than hiding it
    raise SystemExit("ambiguous cross-file frame table %s referenced from %s: "
                     "%s" % (symbol, ref_file, hits))


def parse_templates(base_defines, anim_tables, affine_tables):
    templates = {}
    field_pat = re.compile(r"\.(\w+)\s*=\s*([^,}]+)")
    tmpl_pat = re.compile(
        r"const\s+struct\s+SpriteTemplate\s+(\w+)\s*=\s*\{(.*?)\};",
        flags=re.S)
    for path in sorted(glob.glob(ANIM_C_GLOB)):
        raw = open(path).read()
        resolver = file_scoped_resolver(base_defines, raw)
        text = strip_comments(raw)
        for m in tmpl_pat.finditer(text):
            name, body = m.group(1), m.group(2)
            fields = {fm.group(1): fm.group(2).strip()
                      for fm in field_pat.finditer(body)}
            def tag_field(key):
                raw = fields.get(key, "0").strip()
                try:
                    val = eval_expr(raw, resolver)
                except Exception:
                    return {"name": raw, "value": None}
                return {"name": raw if not raw.isdigit() else None,
                        "value": val}
            def sym_field(key):
                raw = fields.get(key, "NULL").strip()
                return None if raw in ("NULL", "0") else raw

            oam_raw = fields.get("oam", "").lstrip("&").strip()
            anim_sym, anim_off = split_indexed_ref(
                None if sym_field("anims") is None
                else sym_field("anims").lstrip("&"))
            affine_sym, affine_off = split_indexed_ref(
                None if sym_field("affineAnims") is None
                else sym_field("affineAnims").lstrip("&"))
            templates[name] = {
                "file": os.path.basename(path),
                "tile_tag": tag_field("tileTag"),
                "palette_tag": tag_field("paletteTag"),
                "oam": decode_oam_name(oam_raw),
                "oam_symbol": oam_raw,
                "anims": sym_field("anims"),
                "anims_key": resolve_frame_key(
                    anim_sym, os.path.basename(path), anim_tables),
                "anims_offset": anim_off,
                "images": sym_field("images"),
                "affine_anims": sym_field("affineAnims"),
                "affine_anims_key": resolve_frame_key(
                    affine_sym, os.path.basename(path), affine_tables),
                "affine_anims_offset": affine_off,
                "callback": sym_field("callback"),
            }
    return templates


def _cmd_args(text):
    return [a.strip() for a in split_args(text)]


def parse_frame_data(base_defines):
    anims, anim_tables = {}, {}
    affine, affine_tables = {}, {}

    seq_pat = re.compile(
        r"const\s+union\s+AnimCmd\s+(\w+)\[\]\s*=\s*\{(.*?)\};", flags=re.S)
    tab_pat = re.compile(
        r"const\s+union\s+AnimCmd\s*\*\s*const\s+(\w+)\[\]\s*=\s*\{(.*?)\};",
        flags=re.S)
    aseq_pat = re.compile(
        r"const\s+union\s+AffineAnimCmd\s+(\w+)\[\]\s*=\s*\{(.*?)\};",
        flags=re.S)
    atab_pat = re.compile(
        r"const\s+union\s+AffineAnimCmd\s*\*\s*const\s+(\w+)\[\]\s*=\s*"
        r"\{(.*?)\};", flags=re.S)
    def parse_animcmd_body(body, resolver):
        seq = []
        # Entries are comma-separated at depth 0; split_args handles nested
        # parens (e.g. ANIMCMD_FRAME((16 * 16), 6)).
        for entry in split_args(body):
            em = re.match(r"^(\w+)\s*(?:\((.*)\))?$", entry.strip(),
                          flags=re.S)
            if not em:
                continue
            kind, argtext = em.group(1), em.group(2) or ""
            args = _cmd_args(argtext) if argtext.strip() else []
            if kind == "ANIMCMD_FRAME":
                ent = {"tile": eval_expr(args[0], resolver),
                       "duration": eval_expr(args[1], resolver)}
                for extra in args[2:]:
                    fm = re.match(r"\.(\w+)\s*=\s*(.+)", extra)
                    if fm:
                        ent[fm.group(1)] = bool(eval_expr(fm.group(2),
                                                          resolver))
                seq.append(ent)
            elif kind == "ANIMCMD_JUMP":
                seq.append({"jump": eval_expr(args[0], resolver)})
            elif kind == "ANIMCMD_LOOP":
                seq.append({"loop": eval_expr(args[0], resolver)})
            elif kind == "ANIMCMD_END":
                seq.append("end")
            elif kind == "AFFINEANIMCMD_FRAME":
                seq.append({"xscale": eval_expr(args[0], resolver),
                            "yscale": eval_expr(args[1], resolver),
                            "rot": eval_expr(args[2], resolver),
                            "duration": eval_expr(args[3], resolver)})
            elif kind == "AFFINEANIMCMD_JUMP":
                seq.append({"jump": eval_expr(args[0], resolver)})
            elif kind == "AFFINEANIMCMD_LOOP":
                seq.append({"loop": eval_expr(args[0], resolver)})
            elif kind in ("AFFINEANIMCMD_END", "AFFINEANIMCMD_END_ALT"):
                # ⚠️ **[M36F] `END_ALT` IS THE SAME OPCODE AS `END`, AND
                # DROPPING IT COST 10 SEQUENCES THEIR TERMINATOR.**
                # `AFFINEANIMCMD_END_ALT(_val)` expands to
                # `{.end = {.type = AFFINEANIMCMDTYPE_END, .val = _val}}`
                # (`include/sprite.h:134`) — the SAME 0x7FFF type `END` uses,
                # dispatched to the same `AffineAnimCmd_end`. The `.val`
                # payload is READ NOWHERE in the entire reference (grep:
                # 0 hits for `.end.val`), and all 10 battle-anim uses pass
                # the same literal 1, so it carries no behaviour to model.
                # Emitting a plain "end" is the faithful port, not a
                # flattening.
                seq.append("end")
            else:
                # ⚠️ **NO SILENT DROPS. THIS `else` IS THE POINT OF THE FIX,
                # NOT THE BRANCH ABOVE IT.**
                # This chain had no fallthrough, so an unrecognised macro
                # produced NOTHING and said NOTHING — which is exactly how
                # `END_ALT` removed a terminator from 10 sequences without a
                # single warning, and how any future upstream macro would do
                # the same. Same kill-the-bug-class discipline as
                # `gen_trainer_data`'s `AI_TOKEN_MAP` `SystemExit` (which
                # replaced a `.get(key, 0)` that had silently zeroed
                # `CHECKVIABILITY` on 80 trainers) and `normalize()`'s
                # collision assert. Fail the build and name the macro.
                raise SystemExit(
                    "gen_battle_anim_meta: unrecognised animation command "
                    "macro %r in a sequence body -- refusing to emit a "
                    "silently-truncated corpus. Add a branch above, or add "
                    "it to IGNORED_CMD_MACROS if it genuinely carries no "
                    "runtime meaning." % kind)
        return seq

    for path in sorted(glob.glob(ANIM_C_GLOB)):
        raw = open(path).read()
        resolver = file_scoped_resolver(base_defines, raw)
        text = strip_comments(raw)
        base = os.path.basename(path)
        # File-qualified keys: `sAnimCmdAnimatedSpark2` and
        # `sSpriteAffineAnim_DoNothing` are each defined as file-scoped
        # statics in TWO different translation units — distinct objects that
        # a flat symbol dict would silently collapse. Templates carry their
        # own file, so the runtime resolves "<file>::<symbol>" exactly.
        for m in seq_pat.finditer(text):
            anims["%s::%s" % (base, m.group(1))] = parse_animcmd_body(
                m.group(2), resolver)
        for m in aseq_pat.finditer(text):
            affine["%s::%s" % (base, m.group(1))] = parse_animcmd_body(
                m.group(2), resolver)
        for m in tab_pat.finditer(text):
            anim_tables["%s::%s" % (base, m.group(1))] = [
                (base, e.strip().lstrip("&")) for e in split_args(m.group(2))]
        for m in atab_pat.finditer(text):
            affine_tables["%s::%s" % (base, m.group(1))] = [
                (base, e.strip().lstrip("&")) for e in split_args(m.group(2))]
    for table, seqs in ((anim_tables, anims), (affine_tables, affine)):
        for key, entries in table.items():
            table[key] = [resolve_frame_key(sym, ref_file, seqs)
                          for ref_file, sym in entries]
    return anims, anim_tables, affine, affine_tables


def main():
    base_defines = load_defines(CONST_HEADERS)
    resolver = ConstResolver(base_defines)
    sym_paths = parse_incgfx_symbols()

    tags = parse_tag_table(resolver, sym_paths)
    # mark composites
    for entry in tags.values():
        if entry["gfx"] in COMPOSITES:
            entry["gfx_kind"] = "composite"
            entry["gfx_parts"] = COMPOSITES[entry["gfx"]]

    anims, anim_tables, affine, affine_tables = parse_frame_data(base_defines)
    templates = parse_templates(base_defines, anim_tables, affine_tables)

    meta = {"generated_by": "scripts/gen_battle_anim_meta.py [M36A]"}
    outputs = {
        "tags.json": {"meta": dict(meta, count=len(tags)), "tags": tags},
        "templates.json": {"meta": dict(meta, count=len(templates)),
                           "templates": templates},
        "frames.json": {"meta": dict(meta, anims=len(anims),
                                     anim_tables=len(anim_tables),
                                     affine=len(affine),
                                     affine_tables=len(affine_tables)),
                        "anims": anims, "anim_tables": anim_tables,
                        "affine": affine, "affine_tables": affine_tables},
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    for fname, payload in outputs.items():
        path = os.path.join(OUT_DIR, fname)
        with open(path, "w") as f:
            json.dump(payload, f, separators=(",", ":"), sort_keys=True)
        print("wrote %s (%d KB)" % (os.path.relpath(path, PROJECT),
                                    os.path.getsize(path) // 1024))
    print("tags: %d (recon: 411 macro + 1 literal = 412 populated)"
          % len(tags))
    print("templates: %d (recon: ~1,112-1,149)" % len(templates))
    print("anim seqs: %d  anim tables: %d  affine seqs: %d  affine tables: %d"
          % (len(anims), len(anim_tables), len(affine), len(affine_tables)))


if __name__ == "__main__":
    main()
