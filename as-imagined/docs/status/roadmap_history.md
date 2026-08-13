# Roadmap history — the original build order, and every renumbering

Extracted from `CLAUDE.md` during the 2026-08-13 housekeeping pass. Three
things live here, none of which a session needs loaded to do work, and all of
which are needed to read an older label or commit message correctly:

1. **The original M1–M14 build order** as written at project start. It is
   complete and superseded by the roadmap table, but it records the sequencing
   reasoning (why UI was deliberately last, why doubles could not start before
   weather and items were stable).
2. **Milestone notes** that had accumulated under the roadmap table — the
   M24 item-roster verification (including the still-open Smoke Ball backlog
   item) and the M24c doubles-AI gap now owned by M26F2.
3. **The complete renumbering history** — every retirement, insertion,
   narrowing and old→new label mapping (M21, M22, M25, M26a–s → M26A–H,
   M26–M34 → M27–M35, M27's twelve-block decomposition, M32/M34 retirement).
   Historical entries in `docs/decisions.md`, in the `docs/status/` build logs
   and in commit messages are deliberately left under their ORIGINAL labels —
   use the mappings here rather than assuming an old label is stale.

Verbatim from `CLAUDE.md`, only relocated.

## The original build order (M1–M14), as written at project start

## Build order (milestones — do not skip ahead)

[Scope note, added this session] This numbered list (M1–M10) and the "Phase
2" list below it (M11–M14) are the **battle simulator's own** original
build order — the full project roadmap now extends well past this into the
RPG wrapper itself (M24–M34); see "Project Roadmap" below, inserted before
"Current status".

1. **Data schema + state machine skeleton**
   Define `PokemonSpecies`, `MoveData`, `AbilityData`, `ItemData` resource
   classes. Build the `BattlePokemon` runtime class (species + current
   HP/stats/status/PP). Build the empty state machine above with one dummy
   move so two Pokémon can "battle" with no real mechanics yet — just to
   prove the loop works and a winner is declared.

2. **Damage formula + type chart**
   Implement the damage formula exactly as the expanded engine computes it
   (base power, attack/defense stat use via the Physical/Special split,
   STAB, type effectiveness, random factor, critical hits). Build the full
   18-type effectiveness chart (including Fairy). Verify against known
   damage calc examples from the source or community damage calculators
   that target this engine.

3. **Status conditions**
   Burn, poison, toxic, paralysis, sleep, freeze, confusion — implement each
   condition's application rules, turn-start/turn-end effects, and cure
   conditions, matching the expanded engine's specifics.

4. **Move effects — Tier 1 (simple damage)**
   Implement ~15–20 simple attacking moves with no secondary effect, across
   different types, to validate the damage/type system against real data.

5. **Move effects — Tier 2 (stat changes & status infliction)**
   Stat-modifying moves (Swords Dance, Growl, etc.) and status-inflicting
   moves (Thunder Wave, Toxic, etc.).

6. **Move effects — Tier 3 (multi-turn, recoil, drain, fixed damage)**
   Solar Beam / Dig / Fly style charge-and-release moves, recoil moves,
   drain moves (Giga Drain), fixed-damage moves (Seismic Toss, Dragon Rage).

7. **Move effects — Tier 4 (one-off / unique mechanics)**
   Counter, Destiny Bond, Metronome, Substitute, etc. — the long tail.

8. **Abilities**
   Tiered similarly: passive stat modifiers first, then switch-in effects,
   then complex interactions (weather-setting abilities, contact-based
   abilities like Static).

9. **Trainer AI**
   Port the expanded engine's actual rule-based decision logic from
   `battle_ai_script_commands.c` / `battle_ai_main.c`.

10. **UI / animation layer**
    Battle HUD, health bars, menu navigation, text box sequencing, basic move
    animations. Deliberately last — logic must be solid first so the UI has
    something correct to display.

    

Do not jump to UI or "make it look like the game" before the move/damage/
status core is working — visuals are the easiest part to get wrong-but-
convincing, which masks logic bugs.

## Build order — Phase 2 (post-core-engine expansion)

These milestones build on the complete M1–M10 core. Same rules: one milestone
at a time, verify against source, regression-sweep before moving on.

11. **Weather**
    Field-wide weather state (rain / sun / sandstorm / hail). End-of-turn tick
    following the same burn/poison trigger pattern established in M3. Damage
    modifiers in `DamageCalculator`: rain ×1.5 Water / ×0.5 Fire; sun the
    reverse; sand and hail deal end-of-turn chip to non-immune types. Un-stub
    the weather-setting abilities (`Drizzle`, `Drought`) left as placeholders in
    M8. Weather-aware AI scoring (explicitly deferred in M10's `decisions.md`).

12. **Held items**
    `ItemData` exists from M1 but is unpopulated. Build item mechanics before
    item AI: passive stat items (e.g. Choice Band); single-use consumables
    (berries triggered by HP thresholds, using the same trigger-shape as M8's
    contact abilities); choice-lock items (source already references
    `AI_DoesChoiceEffectBlockMove`, found during M10's source read).

13. **Item AI**
    Extend `TrainerAI` to consider held items in move scoring and switch
    decisions. Source: `battle_ai_items.c` (located but deferred during M10).
    This is a sequel to M10, not new architecture — requires M12 complete first.

14. **Doubles battle support**
    The largest item. Must not start until M11 and M12/M13 are stable and
    verified, since doubles must correctly interact with weather and items. Treat
    as three separate milestone passes with a full regression sweep after each —
    do not collapse into one combined effort.

    - **14a — State machine + turn order for 4 combatants:** spread/ally
      targeting changes core assumptions in `BattleManager`,
      `DamageCalculator`, and every move/ability that currently assumes a
      single attacker/defender pair. Fix the foundations here before touching
      move or AI logic.
    - **14b — Spread moves and ally-targeting effects:** move effects that hit
      multiple targets or interact with the ally slot.
    - **14c — Doubles AI:** source is `ChooseMoveOrAction_Doubles`,
      `AI_FLAG_DOUBLE_BATTLE`, `AI_DoubleBattle` / `AI_AttacksPartner` — all
      located but skipped during M10's source read.


## Milestone notes carried out of the roadmap table

**M24 note (item-roster verification, 2026-07-18):** a post-M24a check of the
5 item names `gen_trainer_data.py` failed to resolve (Full Restore, Hyper
Potion, Super Potion, Nugget, Smoke Ball) confirmed all 5 are real Gen III
items in source and genuinely absent from this project's item roster — not a
converter bug. 4 of 5 (Full Restore/Hyper Potion/Super Potion/Nugget) are
known, already-documented M18 exclusions (bag-consumable/non-held items,
deferred to M25 per `docs/m18_item_ledger.md`) — no action needed. The 5th,
**Smoke Ball, is a genuine unflagged gap**: a real Gen III held item that
should have qualified under the item ledger's own Rule 1 ("all held items
through Gen IV included") but was never added and was never excluded
anywhere either. Backlog item for a future item-tier session.

**M24 note (doubles-mode AI gap, found M24c) — moved to M25g:** M24c wired
the new `ai_flags` bitmask (RISKY/FORCE_SETUP_FIRST_TURN/narrow-combo
gating) into `TrainerAI`'s singles path (`_score_move`/`choose_action`)
only. The parallel doubles path (`_score_move_doubles`/
`choose_action_doubles`) is unaffected and still behaves as unconditional
BASIC-tier regardless of a trainer's real `ai_flags`. This is disclosed,
not an oversight — affects 77/854 real trainers flagged
`Double Battle: Yes`. Originally flagged as needing "a future session"
with none named; now scoped as **M25g** (see M25's roadmap row), alongside
RISKY/FORCE_SETUP_FIRST_TURN's own narrow-implementation gap (same
closing report, documented in M24c's own CLAUDE.md entry below) — porting
the same gating logic into the doubles scoring path is M25g's job, not a
dangling future-session reference anymore.

**Renumbering history** (kept inline so future sessions don't cross-reference
stale numbers or wonder why M21/M22/M26 read differently than a flat
sequential list would suggest — this is the single, resolved account;
supersedes an earlier version of this note from the prior session that left
the M21/M22 discrepancy below flagged as unresolved):

- **M21 (Doubles interaction cleanup) was retired as a standalone milestone
  slot and folded into M23**, specifically to avoid M23 (simulator layer)
  being blocked waiting on a separate M21 slot. The underlying work itself
  is NOT affected by this — it was completed in full under the old M21
  label (`2026-07-15` bundle-safe group, `2026-07-16` closeout — "closes
  the ENTIRE M21 doubles-interaction-cleanup inventory... No open items
  remain") — see "Current status" below's existing M21 entries, which stay
  exactly as written and are NOT being relabeled or duplicated. Only the
  roadmap table's own reference to that milestone NUMBER changed (see the
  M21 row above); confirmed directly by the project owner, resolving the
  prior session's own flagged conflict.
- **M22 (Battle item actions — turn-queue) was introduced as a genuinely
  new milestone slot**, created during this same renumbering to absorb the
  remaining/reassigned items that the M21 retirement displaced — not a
  phantom or mistaken number; the table's existing M22 row is accurate as
  given and needed no correction.
- Separately, **M25 was inserted on 2026-07-18**, shifting whatever
  previously occupied M25–M32 up by one.
- **M34 (Advanced Battle Systems) is a consolidation point, not new
  discovery** — added 2026-07-18 specifically to give every exclusion
  flagged during M24 scoping a formal future home, rather than letting them
  live only as scattered notes inside `docs/m24_recon.md`. Sequenced right
  after M33 (not earlier) because the rematch-progression piece explicitly
  depends on M33's save-state infrastructure existing first. Full reasoning
  for each of the 4 consolidated items lives in `docs/m24_recon.md`'s own
  §6 — cross-referenced from the M34 row above, deliberately not
  duplicated here. [Citation correction made while writing this entry: the
  original task prompt cited these items as deferred from sub-tiers
  "M24d/M24e/M24f/M24g" — those labels don't exist anywhere in
  `docs/m24_recon.md`, which only defines M24a/M24b/M24c; the M34 row above
  cites the real section numbers (§6.1/§6.2/§6.3/§6.5) instead.]
- **M26 was relabeled "Full RPG rescope" this same session**, specifically
  to mark it as the project's actual pivot point from battle-sim-only to
  the full game loop.
- **M26–M34 all shifted up by one to M27–M35, and a new M26 (Battle and
  UI graphical rework and polish) was inserted, on 2026-07-20** — the
  former M26 ("Full RPG rescope") is now M27; nothing under the old
  M26–M34 range had shipped yet (all were still ⬜ Not started), so this
  is a pure forward-looking renumbering with no historical-work conflict
  to preserve, unlike the M21/M22 case above. New M26 exists to hold
  battle-UI graphical-quality threads opened during M25h-4's own
  follow-up work (Essentials-pack asset investigation, the font-migration
  decision, the base-resolution/aspect-ratio question) that go beyond
  M25h's own already-locked scope.
- **M25 was closed outright as a milestone, and M26 fully scoped with**
  **lettered sub-phases (M26a–M26i), on 2026-07-20** — superseding the
  "M26 exists to hold open threads" framing immediately above from earlier
  the same day; M26 is no longer just a container for loose threads, it is
  now M25's full successor with a real locked sequence. M25's own already-
  shipped scope (M25a-e, M25h-1 through h-1.5, h-3, h-4) is completely
  unaffected — kept exactly as recorded, per the same principle already
  established for M21's own retirement above. Every M25 item that was
  still open got an explicit disposition rather than being silently
  dropped: M25h-2 (log/debug merge) and M25j (TARGET_SELECT redesign) are
  absorbed into M26b and M26c-4 respectively, scope unchanged; M25h-5
  (font corrections for the old GBA bitmap font) is retired outright as
  moot, since M26d-1's own font migration replaces that font entirely, not
  just its FONT_NARROW/FONT_SMALL mismatches; M25h-6 (playthrough pass)
  and M25i (reserved/unscoped) are retired, their intent folded into M26's
  own natural closing point and ongoing per-sub-phase scoping
  respectively; M25f and M25g are carried forward unchanged in scope to
  M26h/M26i specifically because they are NOT graphical/UI work (bespoke
  move-animation research + team-level balancing, and doubles AI-scoring
  gaps) and don't fit M26's own mandate, but are real, sourced,
  already-identified gaps that were deliberately not dropped just because
  M25 closed. [**Label note, added 2026-07-26**: the `M26b`/`M26c-4`/
  `M26d-1`/`M26h`/`M26i` references in this bullet are the ORIGINAL
  lowercase M26 labels, correct as of when this bullet was written. They
  now map to `M26A2`/`M26C7`/`M26D1`/`M26F1`/`M26F2` respectively — see the
  reorganization bullet immediately below. This bullet's own text is
  deliberately left as originally written rather than rewritten in place,
  matching this section's standing convention of never retroactively
  editing a historical entry.]
- **M26 was reorganized from accretion-order lettering (M26a–M26s) into**
  **six themed blocks (M26A–M26F), on 2026-07-26.** The original lettering
  had grown alphabetically by discovery date rather than by theme, so
  related work ended up scattered across the alphabet — move-select
  authenticity alone spanned M26c-3/M26q-1/M26q-2/M26q-3/M26s-1/M26s-2,
  and the targeting rework (M26c-4) sat five letters away from the
  directional-input work (M26d) it structurally depends on. **This was a
  labeling change only** — every item's scope, source citations, findings,
  and disclosed limitations carried over unchanged; nothing was added,
  dropped, merged, or re-scoped, and no code or test was touched.
  **Uppercase block letters are deliberate and load-bearing**: `M26C1` and
  the retired `M26c-1` are never confusable when an older status-history
  line, commit message, or `docs/decisions.md` entry is read. Shipped items
  were renumbered along with open ones (rather than frozen at their old
  labels, the alternative considered) so the roadmap reads as one coherent
  sequence with no mixed-scheme gaps; the historical status-history bullets
  in "Current status" below and every `docs/decisions.md` entry are
  deliberately left under their ORIGINAL labels — use the mapping below
  rather than assuming an old label is stale or missing.

  Complete old → new mapping (7 shipped, 20 open, **27 total — the same 27
  items before and after, verified by direct count in both directions**):

  | Old | New | Item | C/T/A |
  |---|---|---|---|
  | M26a | **M26A1** | Base resolution change (1024×768 4:3) | `C--` |
  | M26b | **M26A2** | Log/debug-overlay merge | `CT-` |
  | M26c-1 | **M26B1** | HP/name/level/positioning + EXP bar | `CT-` |
  | M26c-2 | **M26B2** | Battle backgrounds | `CT-` |
  | M26l | **M26B3** | Trainer portraits in battle | `CT-` |
  | M26m | **M26B4** | Battle weather animation | `---` |
  | M26o | **M26B5** | Party status summary | `CT-` |
  | M26p | **M26B6** | Ability activation popup | `---` |
  | M26n | **M26B7** | Catch UI | `---` |
  | M26c-3 | **M26C1** | TOP/Fight 2×2 grid regrid | `CT-` |
  | M26s-1 | **M26C2** | Two-box window split | `CT-` |
  | M26q-3 | **M26C3** | Move info sub-window (PP + Type) | `CT-` |
  | M26q-1 | **M26C4** | Move category icon | `---` |
  | M26q-2 | **M26C5** | Move type badge | `---` |
  | M26s-2 | **M26C6** | Border-style variants | `---` |
  | M26c-4 | **M26C7** | Targeting rework (orig. M25j) | `CT-` |
  | M26d | **M26C8** | Keyboard/gamepad input | `---` |
  | M26e-1 | **M26D1** | Essentials font migration | `---` |
  | M26e-2 | **M26D2** | Announcement/entry/ability text polish | `---` |
  | M26r | **M26D3** | Battle dialogue completeness | `---` |
  | M26f-1 | **M26E1** | Bag screen visual rework | `---` |
  | M26f-2 | **M26E2** | Real pocket-tab implementation | `---` |
  | M26g | **M26E3** | Party/Switch screen | `---` |
  | M26h | **M26E4** | Summary/Stats screen | `---` |
  | M26i | **M26E5** | Matchup overlay screen | `---` |
  | M26j | **M26F1** | Move-animation research + balance (orig. M25f) | `---` |
  | M26k | **M26F2** | Doubles AI-scoring gaps (orig. M25g) | `---` |

- **M27 was decomposed into twelve lettered blocks (M27A–M27L) on
  2026-07-28** (M27M/N/O were appended 2026-07-30/31 and M27P on 2026-08-07 —
  the twelve is the 2026-07-28 record, not the live count), and four
  neighbouring milestones were narrowed, retired or
  expanded around it — Rob-approved, proposed in `docs/overworld_scope.md` §31.
  Same treatment M26 received, and for the same reason: M27 was one milestone
  doing the work of nine, while every comparable milestone here got sub-tiers
  (M17: 14, M18: 24, M19: bucketed, M26: 8 themed blocks).

  **Deliberately NOT a renumbering.** M28–M35 keep their numbers; **M32 and
  M34 are retired as slots** with tombstone rows (the M21 precedent), **M29,
  M30 and M33 are narrowed**, **M28 and M31 clarified**, and **M35 expanded**
  to own the battle simulator's own game modes and difficulty. Renumbering
  M32–M35 downward would have invalidated citations across this file,
  `docs/decisions.md` and commit history for no benefit.

  The two retirements were the only genuine category errors in the old list:
  **HM field effects (M32) are player traversal**, so they belong inside the
  milestone that owns the step resolver; and **save/load (M34) could not
  follow the milestone whose state it must already constrain** — the
  save-slot self-containment "box rule" is a day-one requirement, which is
  precisely the conflict retiring M34 into M27L resolves.

  Uppercase block letters are load-bearing here exactly as they are in M26:
  `M27E` and any older lowercase label are never confusable.

  **Two blocks were added AFTER the reorganization and are deliberately
  absent from the mapping table above** (2026-07-26, same day): **M26G
  (Polish, 3 items)** and **M26H (Bug fix, 3 items)**. These are net-new
  scope, not remapped items — the 27-item mapping describes the
  reorganization only, and remains exactly correct as an old→new
  reconciliation. Their addition closes a real loop this file had left
  open: M25's own closure bullet above states that M25h-6 (playthrough
  pass) and M25i were "retired, their intent folded into M26's own natural
  closing point and ongoing per-sub-phase scoping respectively" — but M26
  was never actually given any closing sub-phases when it was scoped, so
  that intent had nowhere to live until now. M26G is the successor to
  M25h-3's audit method; M26H is the successor to M25h-6's playthrough
  pass. Post-addition M26 totals **33 items across 8 blocks** (7 shipped,
  26 open).

  **Status correction — 2026-07-26.** Three items were carried into the C/T/A
  migration as `---` (nothing started) that were in fact **already implemented
  and committed**. The migration converted CLAUDE.md's own status prose
  faithfully — that prose read *"M26c-4, M26d-q, and M26r not started"*, a
  range shorthand that swept up M26l and M26o — but nobody checked the claim
  against the codebase. **Corrected to `CT-`**, with the real state recorded
  per Rob:

  | Item | Committed evidence | Real state (Rob, 2026-07-26) |
  |---|---|---|
  | **M26B3** (was M26l) | `_show_trainer_intro()`, `[M26l]` ×5 | **Built, but does NOT follow reference convention — needs recertification against how trainer sprites actually behave in battle.** Currently a small framed portrait banner + "X wants to battle!" line, shown briefly then hidden. |
  | **M26B5** (was M26o) | `_show_party_status_summary()`, `[M26o]` ×5 | **Implemented but NOT correct — needs a rework.** |
  | **M26C7** (was M26c-4) | health-box hover/click zones + focus bounce, `[M26c-4]` ×8 | **Built; needs final review only.** Comment at `battle_screen_shared.gd:947` discloses it matches source's cue *"in spirit"* (a bounce on the candidate's health box) rather than porting `DoBounceEffect`'s D-pad cycling — a deliberate simplification, not an oversight. |

  ⚠️ **`T` is filled here on suite-passes, which is what `T` means — but for
  B3 and B5 a passing suite does NOT imply correct behavior.**
  `m26_trainer_category_party_test` passes 31/31 while testing an
  implementation Rob has judged wrong (B5) or non-conforming (B3); the suite
  asserts what was built, not what should have been. C7's coverage is
  `m25h1_3_cursor_test` (30/30) and `m25h1_bottom_region_test` (41/41), both
  exercising `_clear_target_select_hover_wiring()` directly. **Reworking B3/B5
  will require rewriting their assertions, not just their code.**

  **Three probes that looked like the same problem but are NOT** — checked
  rather than assumed: **M26C4** (category icon) — the code comments say
  `_category_icon_texture()` *"is gone"*, i.e. removed, not built;
  **M26C5** (type badge) — the only hit is an asset-directory path in a smoke
  test, assets present with zero consumers, still the cheapest open item;
  **M26C8** (input) — the hits are a comment recording that a grep for
  `grab_focus`/`focus_neighbor`/`ui_up` found nothing. All three are correctly
  `---`.

  Three structural changes came with the regrouping, all labeling-level,
  none scope-level: (1) **M26q-3 is marked ✅** — it was pulled forward and
  genuinely shipped inside M26c-3's own session (the real PP+Type
  `MoveInfoPanel`), but the old roadmap's status column still listed it
  under the blanket "M26d-q not started" phrasing; the new table records
  what actually shipped. (2) **M26C7 and M26C8 are now adjacent** — the
  targeting rework and the directional-input work are one arc (both are
  source-confirmed D-pad-driven mechanisms), and building either without
  the other only ports half the real behavior. (3) **M26F is explicitly
  framed as a split-out candidate** — its two items are the only
  non-graphical work in a graphical milestone, kept only because M25's
  closure deliberately refused to drop them; if M26 runs long they can move
  to their own milestone without disturbing A–E.
