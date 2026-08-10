#!/usr/bin/env python3
"""Pull each roster species' cry from the reference tree.

[M27R 7c] Cries are the simplest half of the audio work and the one with real
assets: standalone per-species `.wav` files needing no synthesis, unlike move
SFX and BGM, which the reference ships only as compiled tracker songs.

⚠️ **FROM THE REFERENCE, NOT THE VENDORED ESSENTIALS PACK.** Both carry cries —
Essentials has 654 as `ABRA.wav`, the reference 1,161 as `abra.wav` — and the
reference's are the authentic GBA rips: measured 8-bit mono 10512 Hz, which is
DirectSound's own format. This project's standing rule is to pull real
reference assets, and here that is also the better-sounding answer.

⚠️ **SELECTIVE, unlike `[M27D D1]`'s sprite pull.** That one took all 449
because the whole set was 0.5 MB; the full cry set is **20 MB**, so only the
386 species this project actually implements are copied. If the roster grows,
re-run — the work list is derived from `pokemon.json`, not a hand-kept list.
"""
import json, os, re, shutil, sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(os.path.dirname(PROJECT), "reference", "pokeemerald_expansion",
                   "sound", "direct_sound_samples", "cries")
OUT = os.path.join(PROJECT, "assets", "audio", "cries")


def stem(name):
    """Species name -> reference cry filename stem.

    ⚠️ The gendered Nidoran are the trap, and they are the SAME one
    `[M27B Step 4]` paid for: `pokemon.json` spells them `Nidoran♀`/`Nidoran♂`,
    and a normaliser that strips non-alphanumerics collapses BOTH to `nidoran`,
    silently giving one of them the other's cry. The sign is mapped BEFORE
    anything else is stripped. Verified: all 386 resolve on this rule alone.
    """
    n = name.replace("♀", "_f").replace("♂", "_m")
    n = n.lower().replace("'", "").replace(".", "").replace(":", "")
    return re.sub(r"[^a-z0-9]+", "_", n).strip("_")


def main():
    if not os.path.isdir(REF):
        print("gen_cries: no reference cries at %s" % REF, file=sys.stderr)
        return 1
    mons = json.load(open(os.path.join(PROJECT, "data", "pokemon.json"),
                          encoding="utf-8"))
    src = mons["pokemon"] if isinstance(mons, dict) and "pokemon" in mons else mons
    rows = list(src.values()) if isinstance(src, dict) else src

    os.makedirs(OUT, exist_ok=True)
    copied, missing = 0, []
    for r in rows:
        name = r.get("name") or r.get("species_name") or ""
        # ⚠️ The key is `dex`. An earlier draft guessed
        # `national_dex_num`/`id`, copied ZERO files and still printed a
        # success line — which is why the count is asserted below rather
        # than trusted.
        dex = int(r.get("dex") or 0)
        if not name or dex <= 0:
            continue
        srcf = os.path.join(REF, stem(name) + ".wav")
        if not os.path.exists(srcf):
            missing.append((dex, name, stem(name)))
            continue
        shutil.copyfile(srcf, os.path.join(OUT, "cry_%04d.wav" % dex))
        copied += 1

    # ⚠️ FAIL THE BUILD on an unresolved species rather than shipping a silent
    # Pokemon. A missing cry is inaudible, so nothing downstream would report it.
    if missing:
        print("gen_cries: %d species have no cry:" % len(missing), file=sys.stderr)
        for m in missing[:20]:
            print("   dex %-4d %-16s -> %s.wav" % m, file=sys.stderr)
        return 1
    # ⚠️ AND A NONZERO FLOOR. The first run of this script copied nothing and
    # reported "gen_cries: 0 cries -> ..." as though that were fine, because a
    # wrong key made every row skip. A generator that can succeed at doing
    # nothing is not a generator.
    if copied == 0:
        print("gen_cries: copied NOTHING — check pokemon.json's keys",
              file=sys.stderr)
        return 1
    print("gen_cries: %d cries -> %s" % (copied, os.path.relpath(OUT, PROJECT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
