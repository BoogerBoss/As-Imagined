#!/usr/bin/env python3
"""
[M19-pipeline-fix] Corrects two confirmed extraction bugs in data/moves.json's
secondary-effect fields, both re-derived directly from
reference/pokeemerald_expansion/src/data/moves_info.h's additionalEffects
struct (see docs/decisions.md's [M19-pipeline-fix] entry for the full source
citations and root-cause analysis).

Usage (from project root):
    python3 scripts/gen_fix_stat_change_extraction.py

Bug 1 (STAT_FIXES, 88 moves): stat_change_stat/stat_change_amount/
stat_change_self were only ever populated when a move's PRIMARY .effect is
itself EFFECT_STAT_CHANGE (Growl, Swords Dance, ...). Moves whose stat
change is a SECONDARY effect attached to a different primary effect (most
commonly EFFECT_HIT — Mud-Slap, Icy Wind, Rock Tomb, Overheat, ...) were
silently left at the -1/0/false defaults, even when secondary_chance was
already correctly extracted alongside them. Root cause: a wrong-conditional-
branch bug — the (missing) extractor gated stat_change_* extraction on the
move's own primary effect type instead of scanning additionalEffects[]
generically for MOVE_EFFECT_STAT_PLUS/MOVE_EFFECT_STAT_MINUS regardless of
the primary effect.

Bug 2 (CHANCE_FIXES, 12 moves): secondary_chance was only ever populated
from a PLAIN NUMERIC .chance literal. Moves whose .chance is a ternary
expression (e.g. Acid's `B_UPDATED_MOVE_DATA >= GEN_2 ? 10 : 33`) were
silently defaulted to secondary_chance=0 — indistinguishable from a
genuinely guaranteed (0%-roll) effect. A distinct root cause from Bug 1
(ternary-value resolution, not branch selection), affecting some of the
same moves (Acid/Bubble Beam/Aurora Beam/Psychic/Constrict/Bubble) plus 6
that have no stat-change involvement at all (Poison Sting/Bite/Thunder/
Sludge/Fire Blast/Poison Fang — all status-infliction secondary effects).
Every ternary resolved by assuming this project's own GEN_LATEST config
default (matching [M15]'s own documented convention) — i.e. every
`>= GEN_N` condition is TRUE.

Excluded, NOT fixed here (schema limitation, not an extraction bug): 41
moves (Growth, Curse, Ancient Power, Calm Mind, Shell Smash, ...) whose
additionalEffects entry sets MULTIPLE stat fields at once (e.g. Ancient
Power raises all 5 non-HP stats by 1). MoveData.stat_change_stat is a
single int — this shape cannot be represented without a schema change,
which is out of this pipeline-fix's scope. Also excluded: Low Kick, whose
additionalEffects (a flinch chance) lives ONLY in the pre-GEN_3 #else
branch of a #if B_UPDATED_MOVE_DATA >= GEN_3 block — under this project's
GEN_LATEST default, Low Kick's real EFFECT_LOW_KICK has no additionalEffects
at all, so its existing 0/-1 defaults are already correct.

Idempotent: reapplies the same values if rerun, so reruns are safe.
"""

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOVES_JSON = os.path.join(ROOT, "data", "moves.json")

# move_id: (stat_change_stat, stat_change_amount, stat_change_self)
# STAGE_* index order: ATK=0, DEF=1, SPATK=2, SPDEF=3, SPEED=4, ACCURACY=5, EVASION=6
STAT_FIXES = {
    51: (3, -1, False),    # Acid
    61: (4, -1, False),    # Bubble Beam
    62: (0, -1, False),    # Aurora Beam
    94: (3, -1, False),    # Psychic
    130: (1, 1, True),     # Skull Bash
    132: (4, -1, False),   # Constrict
    145: (4, -1, False),   # Bubble
    189: (5, -1, False),   # Mud-Slap
    190: (5, -1, False),   # Octazooka
    196: (4, -1, False),   # Icy Wind
    211: (1, 1, True),     # Steel Wing
    229: (4, 1, True),     # Rapid Spin
    231: (1, -1, False),   # Iron Tail
    232: (0, 1, True),     # Metal Claw
    242: (1, -1, False),   # Crunch
    247: (3, -1, False),   # Shadow Ball
    249: (1, -1, False),   # Rock Smash
    295: (3, -1, False),   # Luster Purge
    296: (2, -1, False),   # Mist Ball
    306: (1, -1, False),   # Crush Claw
    309: (0, 1, True),     # Meteor Mash
    315: (2, -2, True),    # Overheat
    317: (4, -1, False),   # Rock Tomb
    330: (5, -1, False),   # Muddy Water
    341: (4, -1, False),   # Mud Shot
    354: (2, -2, True),    # Psycho Boost
    359: (4, -1, True),    # Hammer Arm
    405: (3, -1, False),   # Bug Buzz
    411: (3, -1, False),   # Focus Blast
    412: (3, -1, False),   # Energy Ball
    414: (3, -1, False),   # Earth Power
    426: (5, -1, False),   # Mud Bomb
    429: (5, -1, False),   # Mirror Shot
    430: (3, -1, False),   # Flash Cannon
    434: (2, -2, True),    # Draco Meteor
    437: (2, -2, True),    # Leaf Storm
    451: (2, 1, True),     # Charge Beam
    465: (3, -2, False),   # Seed Flare
    488: (4, 1, True),     # Flame Charge
    490: (4, -1, False),   # Low Sweep
    491: (3, -2, False),   # Acid Spray
    522: (2, -1, False),   # Struggle Bug
    523: (4, -1, False),   # Bulldoze
    527: (4, -1, False),   # Electroweb
    534: (1, -1, False),   # Razor Shell
    536: (5, -1, False),   # Leaf Tornado
    539: (5, -1, False),   # Night Daze
    549: (4, -1, False),   # Glaciate
    552: (2, 1, True),     # Fiery Dance
    555: (2, -1, False),   # Snarl
    583: (0, -1, False),   # Play Rough
    585: (2, -1, False),   # Moonblast
    591: (1, 2, True),     # Diamond Storm
    595: (2, -1, False),   # Mystical Fire
    612: (0, 1, True),     # Power-Up Punch
    628: (4, -1, True),    # Ice Hammer
    642: (0, -1, False),   # Lunge
    643: (1, -1, False),   # Fire Lash
    651: (0, -1, False),   # Trop Kick
    654: (1, -1, True),    # Clanging Scales
    659: (2, -2, True),    # Fleur Cannon
    662: (1, -1, False),   # Shadow Bone
    664: (1, -1, False),   # Liquidation
    676: (6, 1, True),     # Zippy Zap
    706: (4, -1, False),   # Drum Beating
    711: (4, 1, True),     # Aura Wheel
    712: (0, -1, False),   # Breaking Swipe
    715: (3, -1, False),   # Apple Acid
    716: (1, -1, False),   # Grav Apple
    717: (2, -1, False),   # Spirit Break
    728: (2, 1, True),     # Meteor Beam
    734: (2, -1, False),   # Skitter Smack
    751: (1, -1, False),   # Thunderous Kick
    756: (1, 1, True),     # Psyshield Bash
    759: (0, -1, False),   # Springtide Storm
    760: (2, 1, True),     # Mystical Power
    768: (4, 1, True),     # Esper Wing
    769: (0, -1, False),   # Bitter Malice
    771: (1, -1, False),   # Triple Arrows
    774: (4, -1, False),   # Bleakwind Storm
    783: (3, -2, False),   # Lumina Crash
    787: (4, -2, True),    # Spin Out
    799: (2, 1, True),     # Torch Song
    800: (4, 1, True),     # Aqua Step
    810: (4, -1, False),   # Pounce
    811: (4, 1, True),     # Trailblaze
    812: (0, -1, False),   # Chilling Water
    833: (2, 1, True),     # Electro Shot
}

# move_id: corrected secondary_chance
CHANCE_FIXES = {
    40: 30,   # Poison Sting
    44: 30,   # Bite
    51: 10,   # Acid
    61: 10,   # Bubble Beam
    62: 10,   # Aurora Beam
    87: 30,   # Thunder
    94: 10,   # Psychic
    124: 30,  # Sludge
    126: 10,  # Fire Blast
    132: 10,  # Constrict
    145: 10,  # Bubble
    305: 50,  # Poison Fang
}


def main():
    with open(MOVES_JSON, encoding="utf-8") as f:
        moves = json.load(f)

    stat_changed = 0
    chance_changed = 0
    for entry in moves:
        mid = entry["id"]
        if mid in STAT_FIXES:
            stat, amount, self_flag = STAT_FIXES[mid]
            if (entry.get("stat_change_stat") != stat
                    or entry.get("stat_change_amount") != amount
                    or entry.get("stat_change_self") != self_flag):
                entry["stat_change_stat"] = stat
                entry["stat_change_amount"] = amount
                entry["stat_change_self"] = self_flag
                stat_changed += 1
        if mid in CHANCE_FIXES:
            chance = CHANCE_FIXES[mid]
            if entry.get("secondary_chance") != chance:
                entry["secondary_chance"] = chance
                chance_changed += 1

    with open(MOVES_JSON, "w", encoding="utf-8") as f:
        json.dump(moves, f, indent=2)
        f.write("\n")

    print(f"stat_change_stat/amount/self: {stat_changed} entries updated "
          f"({len(STAT_FIXES) - stat_changed} already correct)")
    print(f"secondary_chance: {chance_changed} entries updated "
          f"({len(CHANCE_FIXES) - chance_changed} already correct)")


if __name__ == "__main__":
    main()
