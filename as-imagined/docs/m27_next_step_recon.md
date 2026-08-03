# M27 next-step recon — what the vertical slice still lacks

Written 2026-08-03. **Recon only — no code written, no assets pulled.**

Scoping pass requested after `[M27I I4]` closed. Measures what the Pewter-Gym slice can
and cannot do today, then compares the three candidate next steps with sizing and a
recommendation.

Reference: pokeemerald-expansion, HEAD `74e40e03…`.

---

## 0. TL;DR

1. **Recommendation: M27H (wild encounters), then I5.** M27H is the last genuinely
   *unproven* seam in the slice, its data is already imported with **perfect coverage of
   the corridor (7 of 7 outdoor maps)**, and 1,223 grass cells are currently inert. I5 is
   bigger, already has two thorough recons, and its highest-value half (item use) depends
   on a screen those recons scope for battle rather than field.
2. **The overworld→battle seam is only half-proven.** `[M27D D5]` proved the *trainer*
   path. A wild battle is a different shape — no trainer, no prize money, catching, and
   fleeing — and `ItemManager.attempt_catch` plus the `catch_attempted` signal have
   existed since M22 and **have never run outside a test**.
3. **Two factual corrections to existing docs**, both found by measurement (§4).
4. **Six decisions for Rob** in §5.

---

## 1. What the slice can do today

Measured against the 32 baked corridor maps, not assumed:

| | |
|---|---|
| Walk, warp, stitch | ✅ M27A–C |
| NPCs, signs, trainers spotting you | ✅ M27D |
| Talk, dialogue, scripts | ✅ M27F Stages 1–4 |
| Trainer battle, round trip, Brock's full chain | ✅ M27D D5 / M27F Stage 2 |
| Lose → whiteout, money loss | ✅ M27O O2/O3 |
| Field poison | ✅ M27O O4 |
| Heal at a Pokécentre | ✅ M27F Stage 4 |
| See your bag | ✅ M27I I4 |
| **Wild encounters** | ❌ 1,223 grass cells, all inert |
| **See your party** | ❌ |
| **Use an item** | ❌ (bag is read-only) |
| **Save** | ❌ M27L |

---

## 2. Option A — M27H, wild encounters

### 2.1 The data is already there, and the corridor coverage is perfect

`data/wild_encounters.json` is the **raw reference dump** (1.0 MB, 388 encounter entries
across 240 maps) — never processed into a per-map lookup the way every other data file
was. So H starts with a small pipeline task, the same shape as
`gen_heal_locations.py`/`gen_std_strings.py`.

**7 of the 32 baked maps carry a land encounter table — and they are exactly the 7
outdoor ones**: Pallet Town, Viridian City, Viridian Forest, Route 1, Route 2, Route 3,
Route 22. Nothing in the slice is missing data.

Corridor grass: **1,223 cells, all `MB_TALL_GRASS` (id 2)**. `MB_LONG_GRASS`,
`MB_SHORT_GRASS` and the ash/cycling variants appear **zero** times — so the trigger has
one behaviour to recognise, not six.

Sample table shape (Viridian Forest): `encounter_rate: 14`, 12 mon slots with
`min_level`/`max_level`/`species`. The 12-slot rate table
(`20,20,10,10,10,10,5,5,4,4,1,1`) is carried in the file's own header.

### 2.2 What exists on the battle side, and what does not

**Exists and has never run in the field**: `ItemManager.attempt_catch` and the
`catch_attempted` signal (M22 Phase 2). `battle_screen_shared` already has real
"wild/fixture battle — no trainer to bring back" branches, so a trainer-less battle is a
supported shape rather than a new one.

**Does not exist**: any encounter trigger, an encounter-rate roll, a wild-party builder,
a `Run` action wired to real flee odds (M25b shipped Run as a deliberate "end battle now"
placeholder), or the catch UI (**M26B7**, scoped in `docs/m26_b7_recon.md`, not built).

### 2.3 Proposed sub-phases

- **H1 — encounter data pipeline.** `gen_wild_encounters.py` → a per-map lookup keyed by
  this project's own map names (the same `MapConstants` bridge `[M27O O1]` used for heal
  locations). Land only; water/fishing/rock-smash need M27E and have no corridor consumer.
- **H2 — the trigger.** Step onto `MB_TALL_GRASS` → roll against `encounter_rate` → pick a
  slot → build a wild party. Fires from the same step-completion seam warps, sight and
  poison already share. ⚠️ Source gates this on `RestartWildEncounterImmunitySteps` and a
  repel/immunity window; both need porting or explicitly declining.
- **H3 — the battle round trip.** Wild party into `BattleSetupContext` (no trainer key),
  correct return, no prize money, no defeated-flag. Largely reuse.
- **H4 — catching.** Real `attempt_catch` wiring plus a caught mon joining the party.
  ⚠️ **Blocked on a party that can grow** — see §3.3.
- **H5 — fleeing.** Real flee odds, replacing M25b's placeholder Run.

**Sizing**: H1–H3 are one session and make grass live. H4/H5 are a second.

---

## 3. Option B — M27I I5, party / Summary / PC

### 3.1 Most of it is already scoped, for the wrong screen

`docs/m26_e3_recon.md` (Party) and `docs/m26_e4_recon.md` (Summary) are both thorough,
route-compared and recommend the Emerald UI Pack. **But both scope the BATTLE versions.**
The roadmap's own commitment is that Summary is "built once and shared with M26E4", so
I5 should consume those recons rather than re-derive them — and the field screen adds
what battle never needed: reordering, item use, and field-move use.

### 3.2 E4's blocking data gap is confirmed still open

**`moves.json` has descriptions on 0 of 935 moves.** The move-detail panel needs them, so
E4/I5 genuinely starts with a `gen_moves.py` pipeline task, exactly as that recon says.

### 3.3 PC is the part worth questioning

`pokemon_storage_system.c` is **10,137 lines**, the 4th-largest file in the reference.
The roadmap moved PC into M27I from M33 on the grounds that it is a field menu. For a
Pewter-Gym slice it has **no consumer at all** — you cannot fill a 6-slot party before
Pewter without catching, and catching is H4.

⚠️ **This is a real ordering dependency in the other direction too**: H4 (catching) needs
somewhere for a 7th Pokémon to go, which is either "refuse the catch when the party is
full" (source's own behaviour when the PC is unavailable) or the PC itself.

### 3.4 Proposed sub-phases

- **I5-1 — move descriptions** into `gen_moves.py` (unblocks Summary).
- **I5-2 — the field party screen**: the six slots, HP/status, reorder, and *select →
  submenu*. Consumes `m26_e3_recon.md`'s asset route.
- **I5-3 — item use from the bag**, routed through I5-2. This is what makes I4's bag more
  than a read-only list.
- **I5-4 — Summary**, shared with M26E4.
- **I5-5 — PC**, deliberately last and arguably deferrable past the slice.

---

## 4. Two corrections to existing docs, both found by measurement

1. ⚠️ **`docs/m26_e4_recon.md` §0.2 says "item descriptions are empty".** Precisely:
   **`items.json` has all 816**, and the **`.tres` pipeline has 0 of 162**. Both files are
   real and they disagree. `[M27I I4]`'s description box works because
   `PokemonRegistry.get_item_identity` reads the JSON, not the `.tres`. The recon's
   conclusion ("E4 doesn't need them") is unaffected; the statement of fact is not.
2. ⚠️ **`data/wild_encounters.json` is NOT a processed data file.** The M27 roadmap
   describes Kanto's encounters as "imported (264 of 388 entries)", which reads as done.
   It is the raw reference dump with no per-map lookup and no consumer — the same state
   `heal_locations` was in before `[M27O O1]` built its generator.

---

## 5. Decisions — ALL SIX RESOLVED BY ROB, 2026-08-03

| # | Question | Rob's answer |
|---|---|---|
| 1 | Next step | **M27H (wild encounters)**, then I5 |
| 2 | Is the PC in the slice? | **Defer past the slice** |
| 3 | Catch with a full party | **Refuse the catch** (source's own no-PC behaviour) |
| 4 | Repel + encounter-immunity window | **Decline BOTH, record the gap** |
| 5 | Fleeing | **Real flee odds in H5** |
| 6 | Who builds Summary | **Whichever milestone reaches it first** |

⚠️ **Decision 4 went AGAINST this document's own recommendation, and that is recorded
deliberately.** §2.3 recommended porting the post-battle immunity window on the grounds
that back-to-back encounters read as a bug. Rob declined both. So H ships with a bare
encounter roll, and **the absence of an immunity window is a decision, not an oversight** —
a later session finding `RestartWildEncounterImmunitySteps` in source must not "fix" it
without asking. Same for Repel, which was additionally moot until item use exists (I5-3).

**Consequences for H's own sub-phases**, following from the answers above:

* **H4 (catching) is UNBLOCKED and needs no PC** — decision 3 is what makes decision 2
  safe rather than merely convenient. A full party refuses, exactly as source does when
  no storage is available.
* **H2 gets simpler**: no immunity counter, no repel step counter. The trigger is the
  encounter-rate roll and nothing else.
* **H5 is IN**, replacing `[M25b]`'s Run placeholder ("end battle now, return to setup",
  which always succeeds) with source's real speed-and-attempt-counter escape formula.
  ⚠️ That placeholder is shared with TRAINER battles, where fleeing must stay impossible —
  so H5 must not simply repoint it.
* **Summary is not H's problem**, and when I5 reaches it, `docs/m26_e4_recon.md` is the
  scope of record either way.

---

## 5b. Original framing of the questions (superseded, kept for the reasoning)

1. **Next step: M27H or I5?** Recommendation **M27H** — it is the last unproven seam, its
   data is complete for the corridor, and it makes 1,223 currently-inert cells live.
2. **Does the slice need the PC at all?** Recommendation **defer past the slice**: 10k
   lines of reference, no consumer before a full party.
3. **What happens when you catch with a full party?** Source's answer without a PC is to
   refuse. Recommendation **refuse**, which unblocks H4 without I5-5.
4. **Repel and the encounter-immunity window** — port, or decline and record?
5. **Fleeing (H5)**: real odds, or leave M25b's placeholder Run until M29?
6. **Is I5's Summary built now or deferred to M26E4's own session?** The roadmap says
   "built once and shared"; whichever milestone reaches it first pays for it.

---

## 6. Explicitly NOT proposed

- **M27E (field moves)** — nothing in the corridor needs Cut/Surf to reach Pewter Gym.
- **M27G (specials)** — measured at `[M27F Stage 4]` as **2,109 uses / 569 distinct
  functions**, bigger than the roadmap's "a few hundred". Its own session, and nothing in
  the slice is currently blocked on it.
- **M27L (save)** — real, and the slice survives without it; a session ends and you
  replay. Worth doing before the slice is shown to anyone else, not before it works.
