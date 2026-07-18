# M17.5 Pre-Recon — Full Immunity Audit (Type-Based and Move-Flag-Based)

**Status: RECON ONLY — no implementation code touched in this session.** This document
is the complete findings report requested for the M17.5 pre-recon pass. It does not
modify `CLAUDE.md`, `docs/decisions.md`, or any `.gd`/`.tres` file. Rob reviews this and
decides what (if anything) becomes an implementation prompt.

**UPDATE (2026-07-06, same day):** Findings D.1–D.5 below were implemented in the
`[M17.5 Batch Fix]` session immediately following this recon — see `docs/decisions.md`'s
`[M17.5 Batch Fix]` entry for the full change/test/regression detail per fix. Section D
below has been updated in place to mark each finding's resolution status; the rest of
this document (Sections A–C, E) is left as originally written, describing the state of
the codebase AT RECON TIME, before those fixes.

**Why this exists:** M17 (Remaining Abilities) is fully reconciled (226 implemented /
91 excluded / 1 open — Stench; see `docs/m17_final_ledger.md`). During M17n, two real
immunity gaps were found *by accident*: the Sand Veil/Sand Force/Sand Rush/Snow Cloak
missing weather-chip immunity (found during `[M17n-6]`, fixed in a same-day follow-up
— see `[M17n-2]`'s decisions.md entry), and Grass-type's missing general immunity to
powder moves (found incidentally during `[M17n-1]`'s Effect Spore work, **still
unfixed** as of this recon). If two gaps of this shape were found purely by accident,
there are very likely others sitting silently in the engine. This recon systematically
enumerates every canonical type-based and move-flag-based immunity, checks each against
current code, and produces a prioritized list for Rob to triage.

**Method note:** this recon was produced by four parallel research passes — (1)
`CLAUDE.md` + `docs/decisions.md` + `docs/m17_final_ledger.md` context gathering, (2) a
full `move_data.gd` flag audit with codebase-wide usage grep, (3) a full read of
`status_manager.gd`/`damage_calculator.gd`/`ability_manager.gd` mapping every current
immunity check, and (4) a canonical ground-truth pull directly from
`reference/pokeemerald_expansion` source (not from memory/training data) — then
cross-checked against each other and, for the two highest-priority findings, verified
directly against the live file a fifth time before writing this report.

---

## Section A — Canonical type-immunity checklist

### A.1 Type-vs-type damage immunity (effectiveness = 0.0×)

Canonical source: `reference/pokeemerald_expansion/src/data/types_info.h`,
`gTypeEffectivenessTable`. Exactly 8 hard immunity pairs exist in the default
(`GEN_LATEST`) ruleset — no extra or unusual ones beyond the standard modern chart:

| # | Attacking type | Defending type | Project status | Citation |
|---|---|---|---|---|
| 1 | Normal | Ghost | ✅ Correct | `scripts/data/type_chart.gd` `TABLE` row 1, col 8 = 0.0 |
| 2 | Fighting | Ghost | ✅ Correct | row 2, col 8 = 0.0 |
| 3 | Poison | Steel | ✅ Correct | row 4, col 9 = 0.0 (and correctly 0.5×, not 0×, vs. Poison-type itself — the nuance is modeled right) |
| 4 | Ground | Flying | ✅ Correct | row 5, col 3 = 0.0 |
| 5 | Ghost | Normal | ✅ Correct (Gen 6+ symmetric immunity) | row 8, col 1 = 0.0 |
| 6 | Electric | Ground | ✅ Correct | row 14, col 5 = 0.0 |
| 7 | Psychic | Dark | ✅ Correct | row 15, col 18 = 0.0 |
| 8 | Dragon | Fairy | ✅ Correct | row 17, col 19 = 0.0 |

One conditional immunity in the reference source does **not** apply to this project:
Ghost→Psychic is only 0.0× under `B_UPDATED_TYPE_MATCHUPS < GEN_2` (Gen 1 mechanics);
this project targets `GEN_LATEST` throughout, so Ghost correctly hits Psychic
super-effectively (2.0×) here. Not a gap.

**Verdict: 8/8 canonical type-immunity pairs correctly implemented.** Single source of
truth confirmed (`TypeChart.TABLE`, consumed by both `get_effectiveness()` and
`get_uq412()` — no duplicated per-type conditionals anywhere in `damage_calculator.gd`).

### A.2 Status-condition type immunities

Canonical source: `reference/pokeemerald_expansion/src/battle_util.c`,
`CanSetNonVolatileStatus` (L5235–5400) and `CanBeConfused` (L5447–5458).

| Status | Canonical type-immunity gate | Project status | Citation |
|---|---|---|---|
| Burn | Fire-type (unconditional) | ✅ Correct | `status_manager.gd:152–155` |
| Poison/Toxic | Poison-type OR Steel-type; bypassed by attacker's Corrosion | ✅ Correct, including the Corrosion bypass | `status_manager.gd:157–165` |
| Paralysis | Electric-type (`B_PARALYZE_ELECTRIC >= GEN_6`, active by default) | ✅ Correct | `status_manager.gd:167–170` |
| Freeze | Ice-type, **OR** field weather is Sun (`IsBattlerWeatherAffected(..., B_WEATHER_SUN)`) | ⚠️ **PARTIAL — Ice-type half correct, Sun half missing** | `status_manager.gd:172–176`, own comment explicitly says "Sun weather also prevents freeze but weather is not in M3 scope" |
| Sleep | None (correctly no type immunity in canon) | ✅ Correct absence | `status_manager.gd:177` (comment confirms deliberate) |
| Confusion | None (correctly no type immunity in canon) | ✅ Correct absence | `status_manager.gd:209–228`, only ability check (Own Tempo) present |

**Finding A.2-1 (real, currently-reachable gap):** Freeze's Sun-weather immunity half
was deferred all the way back in M3, with an explicit comment citing "weather is not
in M3 scope." Weather is now fully implemented (M17c/M17d weather-setter abilities,
`DamageCalculator.WEATHER_SUN`, Drought, Sunny Day-equivalent mechanics all present per
`scripts/battle/core/status_manager.gd:125`'s own Leaf Guard sun-check, which proves
`weather` is already threaded into this exact function). **The blocker that justified
the original deferral no longer exists** — this is now a stale scope-limitation
comment sitting on top of a real, reachable gap: any Pokémon (not just Ice-types) in
Sun should currently be immune to Freeze, and in this engine it is not.

### A.3 Powder-move immunity — complete canonical set

Canonical source: `reference/pokeemerald_expansion/src/battle_util.c:10545–10554`,
`IsAffectedByPowderMove()`. Three independent exemptions, all active by default
(`B_POWDER_OVERCOAT`/`B_POWDER_GRASS` both default `GEN_LATEST`):

| # | Exemption | Project status | Citation |
|---|---|---|---|
| 1 | Grass-type Pokémon (general, any powder move) | ❌ **MISSING** | No `TYPE_GRASS` check tied to `move.powder_move` anywhere in `status_manager.gd` or `battle_manager.gd` (confirmed via grep — zero hits) |
| 2 | Overcoat ability holders | ✅ Correct | `AbilityManager.blocks_move_flag`, `ability_manager.gd:2106–2127`, wired into `battle_manager.gd:1146` |
| 3 | Safety Goggles item holders | ❓ **Unverified / likely absent** | Grepped `item_manager.gd` and `data/items` — no Safety Goggles handling of any kind found. This project's item scope (M12/M13) focused on choice items, berries, Life Orb, Leftovers; Safety Goggles was never mentioned in that scope. Flagging for Rob rather than asserting definitively, since a full item audit is a different milestone's job — but noting it here since it's part of the same canonical "powder move immunity" set. |

**Finding A.3-1 (real, currently-reachable gap — this is the gap named in the task
prompt):** There is no general Grass-type immunity to powder-flagged moves anywhere in
this codebase. The only Grass-type check anywhere near powder mechanics is a narrow,
unrelated one: Effect Spore's own attacker-side exemption at `ability_manager.gd:3277`
(`if id == ABILITY_EFFECT_SPORE and TypeChart.TYPE_GRASS not in attacker.species.types`)
— this only protects a Grass-type *attacker* from Effect Spore's contact-proc, and has
nothing to do with a Grass-type *defender* being hit by an actual powder move
(Sleep Powder, Stun Spore, Spore, Cotton Spore). `blocks_move_flag` — the only place
`move.powder_move` is read outside that one Effect Spore site — implements Overcoat's
exemption only. A Grass-type Pokémon in this engine is currently hittable by every
powder move exactly like any other type, contradicting Gen 6+ mainline mechanics. The
`MoveData.powder_move` field's own doc comment already half-documents this
(`move_data.gd:105–107`: "Blocked by Overcoat and Grass-type immunity" — only the
first half is wired).

### A.4 Ability-granted type-like immunities (already implemented in this project)

Full cross-check against `docs/m17_final_ledger.md`; all of the following are
IMPLEMENTED and re-verified for scope correctness in Section C below: Levitate (26),
Volt Absorb (10), Water Absorb (11), Flash Fire (18), Motor Drive (78), Sap Sipper
(157), Dry Skin (87, water half), Earth Eater (297), Wonder Guard (25), Scrappy (113),
Mind's Eye (300), Soundproof (43), Bulletproof (171), Overcoat (142), Magic Guard (98),
Infiltrator (151), Magic Bounce (156), Sand Veil (8) / Sand Force (159) / Sand Rush
(146) / Snow Cloak (81) weather-chip halves, Corrosion (212), Telepathy (ally-damage
block).

Excluded abilities in this domain, re-confirmed still correctly excluded (not silently
expected to exist): Suction Cups (21), Water Bubble (199), Wind Rider (274) / Wind
Power (277) / Electromorphosis (280) — all blocked on a genuinely-absent `wind_move`
flag — Good As Gold (283), Perish Body (253, blocked on unimplemented Perish Song).

---

## Section B — MoveData flag audit: intended vs. actual readership

Full schema read: `scripts/data/move_data.gd`. Every flag relevant to
immunity/interaction mechanics, its full intended readership per
`reference/pokeemerald_expansion` source, and its actual current readership in this
project.

| Flag | Declared | Canonical readers (per source) | Actual readers (this project) | Gap? |
|---|---|---|---|---|
| `makes_contact` | line 39 | Long Reach (removes it), Punching Glove (removes it for punch moves), Rough Skin/Iron Barbs/Static/Poison Point/Flame Body/Cute Charm/Effect Spore/Mummy/Wandering Spirit/Gooey/Tangling Hair/Aftermath/Perish Body (all gate on it), Fluffy (both directions), Tough Claws (1.3× boost), Rocky Helmet/Sticky Barb (items) | Fully wired via canonical wrapper `AbilityManager.move_makes_contact()` (`ability_manager.gd:1430–1434`, Long-Reach-aware) at 4+ call sites (`:658,697,3205,3636`) covering all contact-triggered abilities in this project's scope | ⚠️ **Style inconsistency, not a bug today**: Tough Claws reads `move.makes_contact` *directly* at `ability_manager.gd:1661` instead of going through the shared wrapper — every other consumer uses the wrapper. Currently harmless (a battler can't simultaneously hold Tough Claws and Long Reach), but it's the one call site that doesn't follow the established discipline, and would silently diverge if a future ability/item ever needs to override contact status for the attacker's own moves (mirroring Punching Glove's shape) rather than just the defender-facing Long Reach case. |
| `punching_move` | line 40 | Iron Fist (1.2×), Punching Glove (1.1× + removes contact) | Iron Fist only (`ability_manager.gd:1667`) | Punching Glove is an item — not in this project's implemented item scope (M12/M13 covered choice items/berries/Life Orb/Leftovers only). Not a bug in ability scope; a potential item-scope gap, out of M17.5's core focus. |
| `biting_move` | line 41 | Strong Jaw (1.5×) | Strong Jaw only (`ability_manager.gd:1675`) | None at ability level. No roster move currently carries this flag (tested via synthetic `MoveData` in `m17n5_test.gd`) — **this is a scope gap, not a bug**: waiting on real biting moves (Crunch, Bite, etc.) to be added to the movepool, which is M19 territory per `[M17n-5]`'s own note. |
| `sound_move` | line 42 | Soundproof (block), Punk Rock (both halves), Liquid Voice (type change), Throat Chop (self-lock, not implemented) | All 4 real consumers present and correct: Punk Rock both halves (`ability_manager.gd:1415,1679`), Liquid Voice (`:2066`), Soundproof (`:2110`) | None — fully wired. Throat Chop doesn't exist as a move in this project; not flagged as a gap since it's move-content scope, not immunity scope. |
| `ballistic_move` | line 43 | Bulletproof (block) | Bulletproof only (`ability_manager.gd:2112`) | None |
| `powder_move` | line 44 | Overcoat (block), Grass-type (block), Safety Goggles (block), Follow Me powder-redirect | Overcoat only (`ability_manager.gd:2125`) | **See A.3-1 above — this is the audit's #1 finding.** Grass-type general immunity entirely missing; Safety Goggles unverified/likely absent. |
| `dance_move` | line 45 | Dancer (copies the move) | **Never read anywhere in production code** (confirmed via project-wide grep — every other hit is a `.tres`/`.json` data value or decisions.md prose) | Not a bug — Dancer (216) is deliberately `EXCLUDED` per `docs/m17_final_ledger.md:263` ("needs new dance flag + move-repeat mechanism"), consistent with this dead flag. Scope gap, correctly deferred. |
| `slicing_move` | line 46 | Sharpness (1.5×) | Sharpness only (`ability_manager.gd:1681`) | None at ability level; no roster move carries the flag yet — same M19 scope-gap shape as `biting_move`. |
| `pulse_move` | line 47 | Mega Launcher (1.5×) | Mega Launcher only (`ability_manager.gd:1677`) | None at ability level; no roster move carries the flag yet (Water Pulse, Aura Sphere etc. are M19 territory) — scope gap, not a bug. |
| `healing_move` | line 48 | Triage (+3 priority) | Triage only (`ability_manager.gd:1120`), wired onto Recover/Slack Off/Heal Order | None |
| `ignores_protect` | line 49 | Protect-bypass moves | `battle_manager.gd:1010` | None |
| `ignores_substitute` | line 50 | Substitute-bypass moves | 5 call sites, `battle_manager.gd:1521,1747,1855,3119,3254` | None |
| `thaws_user` | line 51 | Fire-type moves that thaw a frozen user/target | `status_manager.gd:373,489` | None |
| `critical_hit_stage` | line 52 | Crit-stage-modifying moves | `damage_calculator.gd:244` | None |
| `always_critical_hit` | line 53 | Guaranteed-crit moves (Frost Breath, Storm Throw, etc.) | **Never read anywhere outside its own declaration** — confirmed dead | Scope gap, not a bug: no guaranteed-crit move exists in the roster yet. Worth a one-line TODO if not already tracked, since this is the kind of "dormant field nobody wired to the generator" pattern that has bitten this project before (Ice Ball's `ballistic_move`, `biting_move`/`slicing_move` before `[M17n-5]`). |
| `blocked_by_aroma_veil` | line 75 | Attract/Taunt/Torment/Encore/Disable/Heal Block per AI-facing logic; only Disable/Encore actually implemented as moves | `battle_manager.gd:1482`, correctly scoped to just Disable/Encore per its own doc comment | None — deliberate partial scope, matches the real execution engine (not the AI's aspirational list) |
| `bounceable` | line 610 | Magic Bounce | `battle_manager.gd:1843` | None |
| `multi_hit` (bonus finding, not in the requested list but directly relevant) | line 35 | Skill Link (guarantees max hits) | **Never read anywhere** — `ability_manager.gd:369–370` has an explicit comment confirming no multi-hit mechanic exists in this codebase at all | Not a bug — Skill Link (92) is `EXCLUDED` per the ledger, deliberately deferred in `[M17n-5]` for exactly this reason. Scope gap, correctly tracked. |

**Wind moves — schema-level absence, not a read/write gap:** `wind_move` does not
exist as a `MoveData` field at all (confirmed via grep — genuinely absent from the
schema, not merely unread). This matches `docs/m17_final_ledger.md`'s existing
exclusion notes for Wind Rider (274)/Wind Power (277)/Electromorphosis (280): "needs
new `wind_move` `MoveData` flag." Not a new finding — already correctly tracked as a
deliberate exclusion, included here only for completeness of the flag audit.

---

## Section C — Re-verification of existing immunity-granting/bypassing abilities

Re-checked every implemented immunity ability specifically through a "does it grant/
bypass exactly what source says, no more, no less" lens — a different angle than each
ability's own original implementation session used.

| Ability | Scope as implemented | Correctness verdict |
|---|---|---|
| Levitate | Ground-move immunity only (`blocks_move_type`) | ✅ Correct — no Gravity field exists to interact with it, correctly noted as N/A in the function's own comment |
| Wonder Guard | Blocks any hit ≤1.0× combined effectiveness; exempts status moves (power=0) and Struggle (TYPE_MYSTERY) | ✅ Correct — verified positioned *after* `TypeChart.get_effectiveness` runs (required, since it needs the full combined multiplier), unlike every flat-0× gate which runs before |
| Scrappy / Mind's Eye | Ghost-immunity bypass (attacker's own ability, correctly no Mold-Breaker param since an ability never "breaks through" itself); Mind's Eye also ignores defender evasion stage | ⚠️ **Partially correct — Ghost-bypass half is right, but the Intimidate-block half is missing.** See Finding D.1 below (Section D). |
| Overcoat | Two independent halves: powder-move block + weather-chip immunity | ⚠️ Both halves individually correct, but the previously-flagged Effect-Spore-self-interaction (Overcoat should block Effect Spore's own proc against itself) remains unfixed — see Finding D.2 |
| Soundproof / Bulletproof | Block sound/ballistic-flagged moves outright, both damaging and status | ✅ Correct |
| Absorb family (Volt/Water Absorb, Sap Sipper, Motor Drive, Well-Baked Body, Flash Fire, Earth Eater, Dry Skin water-half) | Full immunity + correct per-ability side effect (stat boost / heal / persistent flag) | ✅ Correct, verified individually |
| Magic Guard | Blocks weather chip, status residual, standard recoil, contact-ability self-damage, Life Orb recoil, hazard switch-in damage (6 sites); correctly does NOT block Struggle recoil or Aftermath/Innards Out retaliation | ✅ Correct — matches source's exact exemption boundary, toxic counter still ticks per source's own behavior |
| Infiltrator | Bypasses screens (Reflect/Light Screen/Aurora Veil) and Substitute for both damaging and status moves, at all 5 relevant call sites; deliberately does NOT bypass type immunities or other abilities | ✅ Correct, narrow scope matches source |
| Magic Bounce | Reflects flagged foe-targeting status moves; confirmed positioned before the Dark-type Prankster-immunity gate | ✅ Correct |
| Sand Veil / Sand Force / Sand Rush / Snow Cloak | Weather-chip immunity (sandstorm for the first three, hail for Snow Cloak), correctly NOT cross-granting (Sand Veil doesn't exempt hail) | ✅ Correct (the `[M17n-2]` follow-up fix) |
| Corrosion | Bypasses Poison/Steel status immunity from the attacker's side only | ✅ Correct |
| Magic Guard vs. Sand-Veil-family/Overcoat weather-chip predicates | Two independent predicates (`blocks_indirect_damage` for Magic Guard, `blocks_weather_chip_damage` for the others) both consulted at the same `_is_weather_damage_immune` call site | ✅ No divergence found — both predicates are simple boolean checks OR'd together at the call site; no double-counting risk since weather chip damage is a single fixed amount, not additively stacked |

---

## Section D — Prioritized findings list

### Tier 1 — Confirmed real bugs, currently reachable in normal play (fix first)

**D.1 — Scrappy does not block Intimidate's Attack drop. — ✅ RESOLVED** (see
`docs/decisions.md`'s `[M17.5 Batch Fix]` entry, Fix 1).
`[M17n-1]`'s own decisions.md entry (2026-07-01) documented that Inner Focus/Own
Tempo/Oblivious block Intimidate under `B_UPDATED_INTIMIDATE >= GEN_8`, and explicitly
left a TODO: *"Scrappy... not yet implemented... add it here too once it exists."*
Scrappy (113) was implemented five tiers later in `[M17n-6]`, but the TODO was never
followed up. **Confirmed still missing today**: the Intimidate-block gate at
`ability_manager.gd:2601–2604` checks only `ABILITY_INNER_FOCUS`,
`ABILITY_OWN_TEMPO`, `ABILITY_OBLIVIOUS` — the comment at `ability_manager.gd:2596–2597`
still says "also includes Scrappy (113), not yet implemented... add it here too once it
exists" verbatim. A Scrappy holder in this engine currently has its Attack lowered by
an opposing Intimidate switch-in, contradicting source. **Fix size: trivial** (one
additional `or` clause, one new test assertion). **Commonality: high** — Intimidate is
one of the most frequently-triggered switch-in abilities in the existing roster.

**D.2 — No general Grass-type immunity to powder moves. — ✅ RESOLVED** (see
`docs/decisions.md`'s `[M17.5 Batch Fix]` entry, Fix 2).
See Section A.3-1 above for full detail. A real Grass-type Pokémon can currently be
put to sleep/paralyzed/etc. by Sleep Powder, Stun Spore, Spore, and Cotton Spore, which
contradicts Gen 6+ mainline mechanics. **Fix size: small-to-medium** — needs a new
general check (likely in `battle_manager.gd`'s move-execution pipeline, parallel to
where `blocks_move_flag` is consulted) rather than reuse of the narrow Effect-Spore-only
inline check. **Commonality: medium-high** — any of this project's currently-Grass-typed
Pokémon vs. any of the currently-implemented powder moves.

**D.3 — Sun weather does not block Freeze. — ✅ RESOLVED** (see
`docs/decisions.md`'s `[M17.5 Batch Fix]` entry, Fix 3).
See Section A.2 (Finding A.2-1). Deferred at M3 with an explicit "weather not in scope"
comment that is now stale — weather is fully implemented. Any non-Ice-type Pokémon
battling in Sun can currently be frozen, contradicting mainline mechanics.
**Fix size: small** — thread `weather == DamageCalculator.WEATHER_SUN` into the
existing `STATUS_FREEZE` case at `status_manager.gd:172–176` (the function already
receives a `weather` parameter, used two lines away for Leaf Guard). **Commonality:
medium** — requires Sun to be active, which is a real, already-implemented mechanic
(weather-setter abilities from `[M17c]`/`[M17d]`).

### Tier 2 — Flagged-but-unfixed, narrower interaction (real but lower-commonality)

**D.4 — Overcoat does not block Effect Spore's proc against itself. — ✅ RESOLVED**
(see `docs/decisions.md`'s `[M17.5 Batch Fix]` entry, Fix 4 — note the fix's mechanism
is slightly corrected from this finding's original framing: it's the ATTACKER's own
Overcoat that matters, not the Effect Spore holder's, confirmed via direct source
read).
Already found and explicitly recorded as unaddressed in `[M17n-6]`'s own decisions.md
entry (2026-07-04): "Overcoat should, in principle, also block Effect Spore's proc
against itself... This project's existing Effect Spore implementation does not check
Overcoat... Recorded here as a found-but-unaddressed gap." Confirmed still unaddressed
— `ability_manager.gd:3277` checks only `TYPE_GRASS`, no Overcoat check. **Fix size:
trivial** (one additional `or` clause on the attacker's own effective ability).
**Commonality: low** — requires the specific matchup of an Effect-Spore holder landing
a contact hit on an Overcoat holder.

**D.5 — Tough Claws bypasses the shared `move_makes_contact()` wrapper. — ✅ RESOLVED
(style-only, no behavior change)** (see `docs/decisions.md`'s `[M17.5 Batch Fix]`
entry, Fix 5).
Style/architecture inconsistency, not a functional bug today (a battler can't hold both
Tough Claws and Long Reach simultaneously, so the divergence is currently inert). Every
other contact-flag consumer in the project goes through the canonical wrapper; Tough
Claws alone reads `move.makes_contact` directly at `ability_manager.gd:1661`. Worth
normalizing the next time this code is touched, purely for consistency/future-proofing
— low priority, no user-visible effect right now.

### Tier 3 — Scope gaps, correctly blocked on future move-content work (not bugs)

These are all *already correctly excluded or deferred* per `docs/m17_final_ledger.md`
and prior decisions.md entries — listed here only to confirm the audit reached them and
found no additional hidden problem beyond the already-known scope gap:

- **D.6** Wind Rider (274) / Wind Power (277) / Electromorphosis (280) — blocked on a
  genuinely-absent `wind_move` `MoveData` flag (schema-level, not a read/write gap).
  Correctly excluded.
- **D.7** Dancer (216) — `dance_move` flag exists but is never read anywhere; needs a
  move-repeat mechanism that doesn't exist yet. Correctly excluded.
- **D.8** Skill Link (92) — `multi_hit` is a fully dead flag; no multi-hit mechanism
  exists in this engine at all. Correctly deferred.
- **D.9** `biting_move` / `slicing_move` / `pulse_move` — all three are correctly wired
  to their respective abilities (Strong Jaw, Sharpness, Mega Launcher), but zero moves
  in the current roster carry any of these flags. This is purely a "movepool hasn't
  reached these moves yet" gap (M19 territory per `[M17n-5]`'s own note), not an
  immunity-system bug.
- **D.10** `always_critical_hit` — fully dead flag, no guaranteed-crit move exists yet.
  Same shape as D.9; flagged only so it doesn't get silently forgotten the way
  `biting_move`/`slicing_move` almost were before `[M17n-5]` caught them.
- **D.11** Safety Goggles (item) powder-move immunity — likely absent (no item-manager
  handling found), but this is item-scope (M12/M13's territory), not ability/type/
  move-flag scope. Flagged for awareness, not counted in this audit's core tallies.

---

## Section E — Summary count table

| Category | Total canonical items audited | Confirmed correct | Confirmed broken/missing (real bug) | Blocked on future move-content work (not a bug) |
|---|---|---|---|---|
| Type-vs-type damage immunity pairs | 8 | 8 | 0 | 0 |
| Status-condition type immunities (incl. correct-absence cases) | 6 (Burn, Poison/Toxic, Paralysis, Freeze, Sleep, Confusion) | 5 | 1 (Freeze/Sun half) | 0 |
| Powder-move immunity exemptions | 3 (Grass-type, Overcoat, Safety Goggles) | 1 (Overcoat) | 1 (Grass-type — D.2) | 0 (Safety Goggles is item-scope, tracked separately, not counted as a bug here) |
| Move-flag readership completeness (of flags with any canonical reader) | 13 flags with real canonical readers | 11 fully correct | 1 partial (`powder_move` — same as above) + 1 style inconsistency (`makes_contact`/Tough Claws, D.5, not counted as broken) | 3 flags waiting on movepool (`biting_move`, `slicing_move`, `pulse_move`) + 1 dead flag correctly deferred (`always_critical_hit`) + 2 already-excluded mechanics (`dance_move`/Dancer, `multi_hit`/Skill Link) |
| Re-verified ability scope correctness | 12 immunity-granting/bypassing abilities | 11 fully correct | 1 partial (Scrappy — Ghost-bypass correct, Intimidate-block missing, D.1) | 0 |
| Known-but-deliberately-out-of-scope (schema-level absence) | Wind moves (`wind_move` flag) | — | — | 1 (D.6, already excluded) |

**Bottom line: 3 real, currently-reachable bugs found (D.1 Scrappy/Intimidate, D.2
Grass-type powder immunity, D.3 Sun-blocks-Freeze), all small-to-trivial fixes; 1
narrower flagged-but-unfixed interaction (D.4 Overcoat/Effect Spore self-proc); 1 pure
style inconsistency with no current functional impact (D.5 Tough Claws); everything
else audited is either already correct or already a properly-tracked, correctly-excluded
scope gap waiting on future move-content milestones (M19-territory).**
**UPDATE: all five (D.1–D.5) were implemented the same day in the `[M17.5 Batch Fix]`
session — see `docs/decisions.md`'s entry of that name for the full change/test/
regression detail. `scripts/count_assertions.sh`: 45 files, 2489 assertions (2477 + 12
new), 0 failures.** No new exclusion
decisions are needed as a result of this audit — every scope gap found was already
recorded somewhere. Recommend Rob review D.1–D.3 as the M17.5 implementation scope
(all three are small, well-isolated fixes with obvious test shapes reusing this
project's existing conventions), with D.4/D.5 as optional low-priority cleanup.
