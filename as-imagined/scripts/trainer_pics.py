"""Portrait stems — the ONE place the `Pic:` → source-filename resolution lives.

**Rule B** (see docs/overworld_scope.md): a portrait is referenced by UPSTREAM's
own `graphics/trainers/front_pics/<stem>.png` filename stem, copied **verbatim**:

    Pic: "Leader Roxanne"  ->  leader_roxanne
    Pic: "RS Brendan"      ->  brendan_rs      <- NOT rs_brendan
    Pic: "Bug Catcher Frlg"->  bug_catcher_frlg

We never add, strip, or re-case anything. The stem's entire value is direct
traceability to the exact source file, so a "tidier" derived slug would destroy
the only property it has. `brendan_rs`/`may_rs` are the visible proof: a naive
`lower().replace(" ","_")` produces `rs_brendan`, which is not a real file.

**Deliberately the opposite of Rule A** (trainer keys), which ARE our
identifiers and so carry an origin suffix we add ourselves. The asymmetry is a
decision, not an inconsistency: the two identifiers have different owners.
Rule B's `_frlg` suffixes exist only because upstream wrote them.

Resolution chain, reproduced from source rather than guessed:

    Pic: "Leader Roxanne"
      -> TRAINER_PIC_LEADER_ROXANNE            (trainerproc's own fprint_constant)
      -> gTrainerPicInfo[...] = { .frontPic = TRAINER_FRONT_PIC(gTrainerFrontPic_LeaderRoxanne, ...) }
      -> INCGFX_U32("graphics/trainers/front_pics/leader_roxanne.png", ...)
      -> "leader_roxanne"

Imported by BOTH gen_trainer_data.py (to populate TrainerData.pic_stem) and
gen_trainer_portraits.py (to name the pulled PNGs). Duplicating it would let the
two drift, and a drift means a trainer pointing at a portrait that isn't theirs.
"""

import os
import re

from ref_path import REF

TRAINERS_GFX_H = os.path.join(REF, "src", "data", "graphics", "trainers.h")
FRONT_PICS_DIR = os.path.join(REF, "graphics", "trainers", "front_pics")

_pic_to_file = None


def normalize_to_constant(name):
    """Reproduces tools/trainerproc/main.c's own fprint_constant() transform for
    the TRAINER_PIC prefix: uppercase alnum, everything else collapses to
    underscores."""
    conv = re.sub(r"[^A-Za-z0-9]", "_", name.upper()).strip("_")
    conv = re.sub(r"_+", "_", conv)
    return "TRAINER_PIC_" + conv


def _build_pic_to_file():
    global _pic_to_file
    if _pic_to_file is not None:
        return _pic_to_file

    with open(TRAINERS_GFX_H, encoding="utf-8") as f:
        content = f.read()

    frontpic_to_file = {}
    for m in re.finditer(
            r'const u32 (gTrainerFrontPic_\w+)\[\]\s*=\s*INCGFX_U32\("([^"]+)"', content):
        frontpic_to_file[m.group(1)] = m.group(2)

    start = content.index(
        "const struct TrainerPicInfo gTrainerPicInfo[TRAINER_PIC_COUNT] =")
    end = content.index("\n};", start)
    body = content[start:end]

    out = {}
    for m in re.finditer(r"\[(TRAINER_PIC_\w+)\]\s*=\s*\{(.*?)\n\s*\},", body, re.DOTALL):
        fm = re.search(r"TRAINER_FRONT_PIC\((gTrainerFrontPic_\w+)", m.group(2))
        if fm:
            rel = frontpic_to_file.get(fm.group(1))
            if rel:
                out[m.group(1)] = rel
    _pic_to_file = out
    return out


def stem_for_pic_name(pic_name):
    """Upstream's front_pics stem for a roster `Pic:` value, or "" if unresolved.

    Returns "" rather than raising: a `Pic:` naming art this reference tree does
    not ship is a real, reportable data gap, and the caller decides whether that
    is fatal.
    """
    if not pic_name:
        return ""
    rel = _build_pic_to_file().get(normalize_to_constant(pic_name))
    if not rel:
        return ""
    return os.path.splitext(os.path.basename(rel))[0]


def all_stems():
    """Every stem this reference tree defines — used to assert uniqueness."""
    return sorted(
        os.path.splitext(os.path.basename(p))[0] for p in _build_pic_to_file().values())
