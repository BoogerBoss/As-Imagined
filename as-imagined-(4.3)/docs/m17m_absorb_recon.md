# M17m Pre-Recon: Absorb-Family Ability Effect Audit

Report-only. No implementation in this pass. All line numbers/quotes are from
`reference/pokeemerald_expansion` as it exists on disk today; all IDs re-verified
directly against `include/constants/abilities.h` (not trusted from memory or
`docs/m17_recon.md`).

## The dispatch function

All candidates route through one function, `CanAbilityAbsorbMove` in
`src/battle_util.c:2235-2313`, called from `CanMoveBeBlockedByTarget` (line 2184) —
this is the single switch statement M17l's `AbilityManager.absorbs_move_type()`
partially implements. It returns a `battleScript` per-case; `battleScript == NULL`
means "not absorbed, proceed normally." When absorbed, damage is always fully
prevented (0 damage) — the switch decides only what side-effect happens on top of
that, not whether the move connects.

**Key finding confirming the task's premise**: the on-absorb effect is genuinely one
of THREE different shapes, not one:
1. **Heal 25% max HP** (`AbsorbedByDrainHpAbility`, line 2315) — Volt Absorb, Water
   Absorb, Dry Skin (water half), Earth Eater.
2. **Stat stage boost** (`AbsorbedByStatIncreaseAbility`, line 2328) — Motor Drive,
   Lightning Rod, Storm Drain, Sap Sipper, Well-Baked Body, Wind Rider (not in this
   audit's scope, flagged below).
3. **Persistent volatile flag, no immediate stat/HP effect** (`AbsorbedByFlashFire`,
   line 2342) — Flash Fire only.

M17l's `absorbs_move_type(defender, move_type, ng_active, attacker) -> int` returns
a `BattlePokemon.STAGE_*` constant (shape 2 only) or `-1`. It has no way to express
shape 1 (heal) or shape 3 (flag-set, no stat). **This signature cannot be reused
as-is for Volt Absorb/Water Absorb/Earth Eater/Flash Fire** — M17m's implementation
prompt should plan either a broader return contract (e.g. a small result Dictionary
with `{"kind": "heal"/"stat"/"flag", ...}`) or a second sibling function, rather than
stretching `absorbs_move_type`'s int-return contract to also mean "heal amount" or
"flag set."

## Per-ability findings (this audit's requested scope)

| Ability | ID (verified) | Type matched | Effect shape | Source detail |
|---|---|---|---|---|
| Volt Absorb | 10 | Electric | Heal maxHP/4 | `case ABILITY_VOLT_ABSORB: if (moveType == TYPE_ELECTRIC) battleScript = AbsorbedByDrainHpAbility(...)` (L2241-2243) |
| Water Absorb | 11 | Water | Heal maxHP/4 | `case ABILITY_WATER_ABSORB: case ABILITY_DRY_SKIN: if (moveType == TYPE_WATER) battleScript = AbsorbedByDrainHpAbility(...)` (L2245-2248) — **literally the same case label as Dry Skin**, see cross-reference below |
| Sap Sipper | 157 | Grass | Atk +1 | `case ABILITY_SAP_SIPPER: if (moveType == TYPE_GRASS) battleScript = AbsorbedByStatIncreaseAbility(ctx, STAT_ATK, 1)` (L2266-2268) |
| Flash Fire | 18 | Fire | Sets `volatiles.flashFireBoosted = TRUE` (no immediate stat/HP change); later multiplies the HOLDER's own Fire-type move power (checked at `battle_util.c:6818`, `if (moveType == TYPE_FIRE && gBattleMons[battlerAtk].volatiles.flashFireBoosted)`) | `case ABILITY_FLASH_FIRE: if (moveType == TYPE_FIRE && (B_FLASH_FIRE_FROZEN >= GEN_5 \|\| !frozen)) battleScript = AbsorbedByFlashFire(...)` (L2278-2280); flag defined in `AbsorbedByFlashFire` (L2342-2355); cleared at `L10564` (per-battle-reset point, i.e. lasts for the whole battle, not just one turn) |
| Motor Drive | 78 | Electric | Speed +1 | `case ABILITY_MOTOR_DRIVE: if (moveType == TYPE_ELECTRIC) battleScript = AbsorbedByStatIncreaseAbility(ctx, STAT_SPEED, 1)` (L2254-2257) |
| Well-Baked Body | 273 | Fire | Def **+2** (not +1 — only absorb-family member with a 2-stage boost) | `case ABILITY_WELL_BAKED_BODY: if (moveType == TYPE_FIRE) battleScript = AbsorbedByStatIncreaseAbility(ctx, STAT_DEF, 2)` (L2270-2272) |
| Earth Eater | 297 | Ground | Heal maxHP/4 | `case ABILITY_EARTH_EATER: if (moveType == TYPE_GROUND) battleScript = AbsorbedByDrainHpAbility(...)` (L2250-2253) |

All confirmed genuinely part of `CanAbilityAbsorbMove` — none needed to be excluded
from this family.

## Cross-reference: Dry Skin (per the task's explicit ask)

Dry Skin (ID 87) shares Water Absorb's literal `case` label in
`CanAbilityAbsorbMove` (L2246-2248) — Water-type moves get the identical
heal-maxHP/4 treatment as Water Absorb, via the same `AbsorbedByDrainHpAbility`
call, when `runScript` there also gates on `IsBattlerAtMaxHp`/heal-block exactly
like every other heal-shape entry.

**Already implemented in this project** (M17c, confirmed by reading
`ability_manager.gd:808-845` and `:1585-1668` directly — not re-derived from
memory):
- Fire-type damage taken ×1.25 (`defense_damage_modifier_uq412`, line 844-845).
- End-of-turn rain heal maxHP/8 and sun self-damage maxHP/8 (`try_end_of_turn`,
  lines 1659-1663) — note these use `/8`, a **different divisor** from the
  Water-absorb heal's `/4`; they are not the same effect and must not be
  conflated when M17m implements the absorb half.

**Explicitly deferred, confirmed still unimplemented** by this same grep pass (no
`TypeChart.TYPE_WATER` branch exists anywhere in `ability_manager.gd` gated on
`ABILITY_DRY_SKIN`): the Water-move absorb+heal third. This is exactly the "Bucket
half" the M17c decisions.md entry names as blocked on Volt-Absorb/Water-Absorb-style
infra not existing yet — that infra is precisely what this M17m tier will build, so
**Dry Skin's Water-absorb half should be picked up as a free-rider in M17m
alongside Water Absorb**, reusing whatever heal-shape function M17m introduces,
not re-scoped elsewhere.

## Family members NOT in this audit's requested scope, found during the sweep

Flagging per the task's instruction to check for others belonging to the same
dispatch, since `docs/m17_recon.md` already lists these separately and none should
be silently absorbed into this pre-recon's conclusions without a note:

- **Wind Rider** (ID 274) — `case ABILITY_WIND_RIDER: if (IsWindMove(ctx->move)) battleScript = AbsorbedByStatIncreaseAbility(ctx, STAT_ATK, 1)` (L2274-2276). Same stat-boost shape as Sap Sipper, but keyed on a move flag (`IsWindMove`) rather than a type — `docs/m17_recon.md:282` already separately notes this needs a new "wind move" `MoveData` flag that doesn't exist yet, shared with Wind Power/Electromorphosis. Not part of this tier's proposed scope per the recon doc's own M17m line (813-817); left there.
- **Soundproof** (43), **Bulletproof** (171), **Good As Gold** (283) — all three also route through `CanAbilityAbsorbMove` (L2282-2297), but `battleScript` is unconditionally `BattleScript_AbilityProtectedTarget` with no stat/HP/flag side-effect at all — pure blockers, not absorbers. These belong to a "same gate, no payload" sub-family already tracked separately in `docs/m17_recon.md` (Soundproof line 246, Bulletproof line 630, Good As Gold line 662) under their own move-flag infra (sound/ballistic/status-move-target), not this one. Confirmed they should stay excluded from M17m's absorb-effect work specifically — including them here would misrepresent them as needing heal/stat-boost handling when they need none.

**Already implemented, correctly excluded**: Lightning Rod (31) and Storm Drain
(114) — both `AbsorbedByStatIncreaseAbility(ctx, STAT_SPATK, 1)` shape, done in
`[M17l]`. Confirmed no further work needed on these two for M17m.

## Config flags relevant to this family (defaults confirmed, all `GEN_LATEST`)

- `B_HEAL_BLOCKING` (`include/config/battle.h:111`) — gates whether Heal Block
  prevents the Volt-Absorb-shape heal. `GEN_LATEST` in this project's reference
  tree, so the `AbsorbedByDrainHpAbility` heal-blocked branch is live and should be
  implemented (this project's `StatusManager`/`ItemManager` context should be
  checked in the M17m implementation pass for whatever "heal block" state already
  exists, if any — not checked further in this report-only pass).
- `B_FLASH_FIRE_FROZEN` (`:168`) — `GEN_LATEST`, meaning Flash Fire triggers even
  while the holder is frozen. No freeze-status gate needed in the Godot port under
  current config.
- `B_REDIRECT_ABILITY_IMMUNITY` (`:176`) — `GEN_LATEST`; already correctly assumed
  active for Lightning Rod/Storm Drain in `[M17l]` (consistent, no drift).

This project has no local copy of `config/battle.h` — these defaults are read
directly from the reference tree each time, matching the established convention
noted for `B_UPDATED_SHADOW_TAG` in `[M17f]`'s decisions.md entry.

## Summary for the M17m implementation prompt

- 7 abilities in scope (Volt Absorb, Water Absorb, Sap Sipper, Flash Fire, Motor
  Drive, Well-Baked Body, Earth Eater) + Dry Skin's deferred Water-absorb third as
  an 8th free-rider — all confirmed via direct source read, all IDs re-verified
  against `abilities.h` fresh (not reused from any prior recon doc or memory).
- 3 genuinely different effect shapes, not 1: heal maxHP/4 (Volt Absorb/Water
  Absorb/Dry Skin-water/Earth Eater), stat boost of varying magnitude (Sap
  Sipper/Motor Drive Atk-or-Speed +1, **Well-Baked Body Def +2**), and a
  persistent no-immediate-effect flag that later modifies the HOLDER's own
  move power (Flash Fire) — this last one needs the new "boost own same-type move
  power" mechanism `docs/m17_recon.md:812-816` already flagged as shared with
  Normalize/the "-ate" family's now-larger mechanism, worth sequencing/designing
  together rather than building Flash Fire's flag-storage in isolation.
  Full-HP/heal-block gating on the heal shape should reuse whatever this project's
  existing heal-blocking convention is (check `ItemManager`/`StatusManager` first,
  per the standing "check for a dormant mechanism first" discipline).
- `AbilityManager.absorbs_move_type()`'s current int/stat-stage-only return value
  cannot be stretched to cover heal or flag-set effects — the M17m implementation
  prompt should decide up front whether to widen this function's contract (e.g. a
  Dictionary result) or add sibling functions, rather than discovering this
  mid-implementation.
- Soundproof/Bulletproof/Good As Gold share the same C dispatch gate but carry no
  absorb payload — correctly out of scope for this effect audit, already tracked
  under their own move-flag tiers elsewhere in `docs/m17_recon.md`.
- Wind Rider shares the stat-boost shape but is move-flag-keyed (not type-keyed)
  and needs new `MoveData` infra `docs/m17_recon.md` already scopes elsewhere —
  correctly not pulled into this tier.
