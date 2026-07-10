class_name MoveData
extends Resource

# Source struct: include/move.h :: struct MoveInfo

# Ban flag bitmask — use BAN_* constants below.
# Source: struct MoveInfo ban flag bitfields (gravityBanned … dampBanned)
const BAN_GRAVITY: int       = 1 << 0
const BAN_MIRROR_MOVE: int   = 1 << 1
const BAN_ME_FIRST: int      = 1 << 2
const BAN_MIMIC: int         = 1 << 3
const BAN_METRONOME: int     = 1 << 4
const BAN_COPYCAT: int       = 1 << 5
const BAN_ASSIST: int        = 1 << 6
const BAN_SLEEP_TALK: int    = 1 << 7
const BAN_INSTRUCT: int      = 1 << 8
const BAN_ENCORE: int        = 1 << 9
const BAN_PARENTAL_BOND: int = 1 << 10
const BAN_SKY_BATTLE: int    = 1 << 11
const BAN_SKETCH: int        = 1 << 12
const BAN_DAMP: int          = 1 << 13

@export var move_name: String = ""
@export var description: String = ""
@export var effect: int = 0         # BattleMoveEffects enum id
@export var type: int = 0           # Type enum id
# category: 0 = Physical, 1 = Special, 2 = Status (per-move field, not per-type)
# Physical/Special split confirmed in struct MoveInfo.category; see decisions.md.
@export var category: int = 0
@export var power: int = 0
@export var accuracy: int = 100     # 0 = always hits
@export var pp: int = 5
@export var priority: int = 0
# [M18.5g] strike_count: fixed hit count for the 16 strikeCount-family multi-hit
#   moves (Bonemerang/Double Hit/Double Iron Bash/Double Kick/Dragon Darts/Dual
#   Chop/Dual Wingbeat/Gear Grind/Surging Strikes/Tachyon Cutter/Triple Axel/
#   Triple Dive/Triple Kick/Twineedle/Twin Beam — Population Bomb's strikeCount=10
#   is confirmed but deliberately excluded from this project's scope, see below).
#   A single accuracy check gates the WHOLE sequence (only hit 1 rolls; hits 2+
#   auto-land) for every one of these EXCEPT Triple Kick/Triple Axel, which each
#   roll independently — see is_triple_kick. Source: GetMoveStrikeCount reads this
#   field directly; ShouldSkipAccuracyCalcPastFirstHit (battle_move_resolution.c
#   L2137-2151) confirms the single-accuracy-check default and its two exceptions.
#   Population Bomb EXCLUDED: unlike every other strikeCount move, it also rolls
#   accuracy independently per hit (grouped with Triple Kick/Axel in that same
#   exception list) AND has a uniquely-shaped Loaded Dice interaction
#   (RandomUniform(4,10) instead of the max-4-5 pattern every other multi-hit
#   move's Loaded Dice uses) — a genuinely higher complexity class than the other
#   30 moves this tier resolves, flagged for a future tier rather than built here.
@export var strike_count: int = 1   # number of hits; defaults to 1
# [M18.5g] multi_hit: the 15 variable-hit moves (Arm Thrust/Barrage/Bone Rush/
#   Bullet Seed/Comet Punch/Double Slap/Fury Attack/Fury Swipes/Icicle Spear/Pin
#   Missile/Rock Blast/Scale Shot/Spike Cannon/Tail Slap/Water Shuriken). Hit
#   count rolled ONCE when the move is used: 35% 2 hits / 35% 3 hits / 15% 4 hits /
#   15% 5 hits — this project's default GEN_LATEST config maps to the Gen5+
#   branch of SetRandomMultiHitCounter (battle_move_resolution.c L2304-2312); the
#   OLDER 37.5/37.5/12.5/12.5 weighting (the figure commonly cited without a
#   generation qualifier) is a DIFFERENT, pre-Gen5 branch of that same function
#   and is not modeled here, matching this project's established "config defaults
#   to GEN_LATEST, older branches not reproduced" precedent (e.g. B_BINDING_TURNS
#   in [M18.5f]). Skill Link (ability, unblocked but not implemented this tier —
#   would force exactly 5) and Loaded Dice (item, likewise — would roll uniformly
#   4-5 instead of the weighted distribution) both hook in at this SAME roll site;
#   deferred per this tier's own mechanism-only scope, matching Grip Claw's
#   precedent from [M18.5f].
@export var multi_hit: bool = false # random multi-hit (overrides strike_count)
@export var target: int = 0         # MoveTarget enum id

# Move flags — source: struct MoveInfo flag bitfields
@export var makes_contact: bool = false
@export var punching_move: bool = false
@export var biting_move: bool = false
@export var sound_move: bool = false
@export var ballistic_move: bool = false
@export var powder_move: bool = false
@export var dance_move: bool = false
@export var slicing_move: bool = false
@export var pulse_move: bool = false
@export var healing_move: bool = false
@export var ignores_protect: bool = false
@export var ignores_substitute: bool = false
@export var thaws_user: bool = false
@export var critical_hit_stage: int = 0   # 0–3; added to base crit stage
@export var always_critical_hit: bool = false

# M17n-1: Aroma Veil's protected-effect list. Source: battle_ai_util.c ::
# IsAromaVeilProtectedEffect (L1961-1974) lists the full protected set (Attract,
# Taunt, Torment, Encore, Disable, Heal Block) — but that function is ONLY ever
# consulted by the AI's own move-scoring logic (battle_ai_main.c L1368/1431), never
# by the real execution engine. Individually verified each protected effect's actual
# in-battle command: Torment (`BS_TrySetTorment`, L12270-12286) DOES check
# `IsAbilityOnSide(..., ABILITY_AROMA_VEIL)` directly; Disable
# (`Cmd_disablelastusedattack`, L7898-7927) and Encore (`Cmd_trysetencore`, L7929+) do
# NOT — a genuine, source-verified gap in this hack's own execution engine (the AI
# "expects" Aroma Veil to block them, matching real-game behavior, but the effect
# commands themselves never check it). Implemented here matching the AI's own list
# (real intended behavior) rather than the execution engine's apparent oversight —
# flagged explicitly in docs/decisions.md, not silently assumed correct either way.
#
# [M18.5d-2] CORRECTION: this comment originally (mis)cited `BS_TrySetInfatuation`
# (L12233-12251) as Attract's real command — that function is actually
# `BattleScript_EffectInfatuateSide`'s (a side-wide effect this project doesn't
# implement, no Z-moves), NOT the base single-target Attract move. Attract's real
# script (`BattleScript_EffectAttract`, battle_scripts_1.s L2220+) calls a SEPARATE
# `jumpifability BS_TARGET_SIDE, ABILITY_AROMA_VEIL` check BEFORE `tryinfatuating`
# (`Cmd_tryinfatuating`, L7613-7650, which ALSO re-checks Aroma Veil plus Oblivious
# plus gender/already-infatuated). Since Attract needs Oblivious in the same gate as
# Aroma Veil — a combination `blocked_by_aroma_veil`'s own single-flag shape doesn't
# cover — Attract deliberately does NOT use this flag; it has its own dedicated
# `AbilityManager.blocks_attract()` gate instead (also reused by Cute Charm's
# identical Oblivious+Aroma-Veil combination). `is_attract` (below) is therefore NOT
# added to this flag's "eventually add Taunt/Torment/Heal Block too" list.
#
# This project has no generic move-effect-ID dispatch (each protected effect is its
# own per-move boolean here, e.g. `is_disable`/`is_encore`), so this is a per-move flag
# instead, set on whichever of the six are actually implemented today (Disable/Encore)
# and intended to be set on Taunt/Torment/Heal Block too whenever those are eventually
# added, so Aroma Veil automatically covers them without further code changes.
@export var blocked_by_aroma_veil: bool = false

# Packed ban flags. Test with: move.ban_flags & MoveData.BAN_X
@export var ban_flags: int = 0

# ── Secondary effect (fires after damage on hit) ────────────────────────────
# Source: src/data/moves_info.h :: additionalEffects → moveEffect / chance
# secondary_chance: 0 = guaranteed (primary effect, or pure status/confusion
#   moves where the effect IS the move); 1–100 = percent chance roll.
const SE_NONE: int      = 0
const SE_BURN: int      = 1
const SE_FREEZE: int    = 2
const SE_PARALYSIS: int = 3
const SE_SLEEP: int     = 4
const SE_TOXIC: int     = 5
const SE_CONFUSION: int = 6
const SE_FLINCH: int    = 7
# [M18.5f] SE_WRAP: Bind/Wrap/Fire Spin/Clamp/Whirlpool/Sand Tomb/Magma Storm/
#   Infestation/Snap Trap/Thunder Cage — all 10 share the identical real-source
#   MOVE_EFFECT_WRAP additional effect (battle_script_commands.c L2465-2477),
#   unconditional on a successful hit (no .chance field in moves_info.h → not a
#   "true secondary", so Shield Dust/Sheer Force/Covert Cloak do NOT gate it,
#   matching this project's existing is_true_secondary = secondary_chance > 0
#   gate above for free). Jaw Lock is a DIFFERENT mechanic (MOVE_EFFECT_TRAP_BOTH,
#   a zero-damage bidirectional permanent trap sharing the Mean Look/Block
#   family's escapePrevention volatile, not this one) and is deliberately
#   excluded — confirmed via direct source read, not assumed from name/flavor
#   similarity. See BattlePokemon.wrapped_by for the applied-state field and
#   AbilityManager.is_trapped() for the switch-blocking half.
const SE_WRAP: int      = 8
# [M18.5g] SE_POISON: a small, genuinely in-scope side-fix, not a tangent — this
#   schema had SE_TOXIC (→ BattlePokemon.STATUS_TOXIC, badly poisoned) but NO way
#   to represent regular (non-toxic) poison as a move's secondary effect at all,
#   confirmed via direct inspection of try_secondary_effect's match statement and
#   _se_to_status's mapping (neither had a STATUS_POISON case). Twineedle — one of
#   this tier's own 31 target moves — inflicts regular Poison at a 20% chance per
#   hit (MOVE_EFFECT_POISON, moves_info.h MOVE_TWINEEDLE, .chance = 20), which
#   would have been mis-cast as Toxic without this addition. Needed to correctly
#   implement an in-scope move, not a speculative unrelated fix.
const SE_POISON: int    = 9
# [Bucket 4 cheapest singles] SE_THROAT_CHOP: Throat Chop(638) — sets a 2-turn
#   "target's sound moves fail" timer on the target. Explicit chance=100 in
#   source (a TRUE secondary, unlike a chance=0/omitted guaranteed effect), so
#   this correctly gates through Shield Dust/Covert Cloak/Sheer Force/Serene
#   Grace via the normal try_secondary_effect roll — same "return true, caller
#   applies it" shape as SE_FLINCH/SE_WRAP.
const SE_THROAT_CHOP: int = 10
# [Bucket 4 cheapest singles] SE_EERIE_SPELL: Eerie Spell(754) — cuts 3 PP from
#   the target's own last-used move. Also explicit chance=100 (true secondary).
#   Reuses the pre-existing BattlePokemon.last_move_used field (already
#   comprehensively wired since [M16e]'s Conversion 2) — no new tracking state
#   needed.
const SE_EERIE_SPELL: int = 11
# [M19-random-status-choice] SE_RANDOM_STATUS: Tri Attack(161)/Dire
#   Claw(755) — picks UNIFORMLY at random from `random_status_pool` (below)
#   and applies it via the SAME `StatusManager.try_apply_status` every
#   other status-inflicting move already uses (already-statused target
#   blocks it, same as every other status move — confirmed source checks
#   this too, not a new gate). Two genuinely DIFFERENT pools, confirmed
#   individually from source, not shared: Tri Attack picks from {burn,
#   freeze, paralysis}; Dire Claw picks from {poison, paralysis, sleep}.
const SE_RANDOM_STATUS: int = 12
# [M19f] SE_PREVENT_ESCAPE: Spirit Shackle(625) — the SAME underlying
#   escapePrevention volatile Mean Look/Block/Spider Web set (see
#   `is_mean_look`'s own doc comment below), but dispatched as a damaging
#   move's secondary effect (explicit chance=100, a true secondary) rather
#   than a status move's sole effect. NO Ghost-type immunity here — that
#   check lives only inside `BattleScript_EffectMeanLook`'s own dedicated
#   script (data/battle_scripts_1.s L2100-2112), never in the generic
#   `MOVE_EFFECT_PREVENT_ESCAPE` additionalEffects dispatch Spirit Shackle
#   uses (battle_script_commands.c L2518-2525) — confirmed via direct source
#   read, not assumed symmetric with the status-move family.
const SE_PREVENT_ESCAPE: int = 13
# [M19f] SE_TRAP_BOTH: Jaw Lock(692) — the BIDIRECTIONAL variant of the same
#   escapePrevention mechanism: traps BOTH the attacker AND the defender,
#   gated on NEITHER already being trapped (a stricter guard than Spirit
#   Shackle's own single-sided check). No `.chance` field in source
#   (guaranteed, secondary_chance=0 — same "no true-secondary gates apply"
#   shape as SE_WRAP). Source: battle_script_commands.c ::
#   MOVE_EFFECT_TRAP_BOTH (L2661-2676).
const SE_TRAP_BOTH: int = 14

@export var secondary_effect: int = 0   # SE_* constant above
@export var secondary_chance: int = 0   # 0 = guaranteed; 1–100 = % roll

# [Bucket 3 combined-secondary] A SECOND, fully independent secondary-effect
# roll — Thunder/Ice/Fire Fang each carry a status effect (slot 1 above) AND
# an independently-rolled 10% flinch (slot 2), confirmed from source
# (moves_info.h ADDITIONAL_EFFECTS lists two separate {.moveEffect,.chance}
# blocks) to be TWO SEPARATE rolls, not one shared roll — real source's
# Cmd_setadditionaleffects loop rolls each additionalEffect independently
# (own RNG index via RNG_SECONDARY_EFFECT + counter, own Serene-Grace
# doubling, own Shield-Dust/Covert-Cloak/Sheer-Force gate — all confirmed via
# CalcSecondaryEffectChance/MoveIsAffectedBySheerForce operating per-effect,
# not per-move). Empty (SE_NONE/0) for every move except this one 3-move
# family. Only ever populated with SE_FLINCH by this project's current
# roster — kept schema-symmetric with slot 1 (any SE_* value is legal here)
# rather than narrowed to a flinch-only field, since a future combined-status
# move is plausible and the caller-side dispatch already supports the
# generic case for free.
@export var secondary_effect_2: int = 0
@export var secondary_chance_2: int = 0

# ── Stat change effect ──────────────────────────────────────────────────────
# Source: src/data/moves_info.h :: additionalEffects → STAT_CHANGE_EFFECT_PLUS/MINUS
# stat_change_stat: -1 = no stat change; else BattlePokemon.STAGE_* index.
# stat_change_amount: positive = raise, negative = lower (e.g. +2 for Swords Dance, -1 for Growl).
# stat_change_self: true = applies to the attacker (Swords Dance); false = applies to the opponent.
@export var stat_change_stat: int = -1
@export var stat_change_amount: int = 0
@export var stat_change_self: bool = false

# [Bucket 3 multi-stat] Additional (stat, amount) pairs beyond the primary
# stat_change_stat/amount above, for moves that touch 2+ distinct stats in
# one shot (Ancient Power's +1 to all 5 non-HP stats, Shell Smash's mixed
# +2/-1, Spicy Extract's mixed +2 Atk/-2 Def) — parallel arrays, same index
# = same pair. Empty for every single-stat move (the vast majority) — the
# primary pair alone is sufficient for those, matching this project's
# established default-omitted-from-.tres convention. stat_change_self
# applies uniformly to every pair in a move (self/foe never varies within
# one move's own multiple stat sub-fields — confirmed by direct source
# inspection of every multi-stat move in this project's roster).
@export var extra_stat_change_stats: Array[int] = []
@export var extra_stat_change_amounts: Array[int] = []

# [M19-random-status-choice] random_status_pool: the fixed set of
#   BattlePokemon.STATUS_* values SE_RANDOM_STATUS (above) picks uniformly
#   from. Empty for every other move. Tri Attack's real 3rd option
#   (freeze-or-frostbite) resolves to plain STATUS_FREEZE at this project's
#   config — no STATUS_FROSTBITE exists anywhere in this codebase
#   (confirmed via grep, B_USE_FROSTBITE is not modeled).
@export var random_status_pool: Array[int] = []

# [M19-self-faint] is_self_faint: Self-Destruct(120)/Explosion(153) —
#   unconditional self-KO, regardless of whether the move's own hit lands.
#   Blocked entirely by Damp anywhere on the field (a simplified execution-
#   time translation of source's selection-time `.dampBanned` flag — this
#   project has no move-selection legality filter). TARGET_FOES_AND_ALLY in
#   source (hits every OTHER battler, opponents AND the user's own ally) —
#   modeled here as `is_spread` (opponents only); the ally-hit half in
#   doubles is a known, FLAGGED-not-built gap (same class as Shell Bell's
#   own doubles spread-accumulation gap, deferred to M22).
# Source: moves_info.h .explosion=TRUE, .dampBanned=TRUE; battle_move_resolution.c
#   :: CancelerExplosion (L1841-1848) — see the BattleManager call site's own
#   doc comment for the full pre-move-canceler-timing citation.
@export var is_self_faint: bool = false

# [M19-berry-steal] steals_and_eats_berry: Pluck(365)/Bug Bite(450) — both
#   share the LITERAL SAME `MOVE_EFFECT_BUG_BITE` additionalEffect in
#   source (Pluck's own name is a historical artifact, not a distinct
#   mechanism). Steals the target's berry and immediately consumes its
#   effect ON THE ATTACKER — genuinely different from Incinerate (destroys,
#   no beneficiary effect) and from Pickpocket/Magician/Sticky Barb
#   (possession TRANSFER, held not eaten). Blocked entirely by the target's
#   own Sticky Hold. A held Jaboca/Rowap Berry specifically is exempt —
#   triggers its OWN retaliation instead of being stolen.
# Source: moves_info.h MOVE_PLUCK/MOVE_BUG_BITE additionalEffects
#   {MOVE_EFFECT_BUG_BITE}; battle_script_commands.c ::
#   case MOVE_EFFECT_BUG_BITE (L2641-2656) — see BattleManager's own call
#   site doc comment and ItemManager.steal_and_eat_berry_effect's doc
#   comment for the full citation and the explicit scope-limitation note
#   (4 common berry families covered; Starf/Micle/Enigma/White
#   Herb/Weakness Policy/Lansat/Custap are NOT wired into this path).
@export var steals_and_eats_berry: bool = false

# [M19-ignores-target-ability] ignores_target_ability: Sunsteel
#   Strike(667)/Moongeist Beam(668) — a MOVE-level trigger for the LITERAL
#   SAME `moldBreakerActive` flag Mold Breaker/Mycelium Might already set,
#   confirmed directly from source (not a separate, parallel mechanism):
#     moldBreakerActive = IsMoldBreakerTypeAbility(atk, GetBattlerAbility(atk))
#                          || MoveIgnoresTargetAbility(gCurrentMove);
#   Reuses AbilityManager.effective_ability_id's existing `attacker_move`
#   param (threaded through every damage-pipeline ability check that already
#   reaches Mold Breaker — Levitate/absorb-family/Wonder Guard/Multiscale/
#   Filter/Solid Rock/Fur Coat/Ice Scales/etc.) rather than a new bypass
#   path — this move-level trigger inherits Mold Breaker's EXACT scope for
#   free (same `breakable` gate inside effective_ability_id), since it's
#   the identical underlying flag.
# Source: include/move.h L34 (`ignoresTargetAbility:1`); battle_util.c L9800
#   (`SpecialStatusesClear`, the moldBreakerActive assignment cited above).
@export var ignores_target_ability: bool = false

# powder_move (already declared above in move flags) is set for Sleep Powder et al.
# Blocked by Overcoat and Grass-type immunity (Gen 6+, M8+ scope).
# Source: struct MoveInfo.powderMove — Sleep Powder, Stun Spore, Spore, etc.

# ── Two-turn / semi-invulnerable (M6) ────────────────────────────────────────
# Source: src/data/moves_info.h :: .argument.twoTurnAttack.status
# Semi-invulnerable state constants (set on the user on the charge turn):
const SEMI_INV_NONE: int        = 0
const SEMI_INV_UNDERGROUND: int = 1  # Dig — underground on turn 1
const SEMI_INV_ON_AIR: int      = 2  # Fly, Bounce, Sky Attack — on-air on turn 1
const SEMI_INV_UNDERWATER: int  = 3  # Dive — underwater on turn 1
# [M19-break-protect] Shadow Force/Phantom Force's "vanish" state
# (STATE_PHANTOM_FORCE in source). UNLIKE the 3 states above, nothing can
# hit through it — no move carries a "damages_vanish"-style bypass flag,
# by design, matching source's `CanBreakThroughSemiInvulnerablityInternal`
# (battle_util.c L10464-10493): `case STATE_PHANTOM_FORCE: return FALSE;`,
# a DIFFERENT, explicit-false branch from the function's own default
# `case STATE_NONE: return TRUE;`. This distinction matters here because
# this project's own `StatusManager._can_hit_semi_invulnerable` helper
# defaults an UNRECOGNIZED state to `true` ("no restriction") — the
# opposite of what SEMI_INV_VANISH needs — so it requires its own explicit
# match case returning false, not reliance on that default. See
# `_can_hit_semi_invulnerable`'s own doc comment.
const SEMI_INV_VANISH: int      = 4  # Shadow Force, Phantom Force

# two_turn: Move requires a charge turn before releasing damage.
# Source: struct MoveInfo.effect == EFFECT_TWO_TURNS_ATTACK or EFFECT_SEMI_INVULNERABLE
@export var two_turn: bool = false

# semi_inv_state: State applied to the user on the charge turn.
# 0 = no invulnerability (Razor Wind, Solar Beam); >0 = one of SEMI_INV_* above.
# Source: struct MoveInfo.argument.twoTurnAttack.status
@export var semi_inv_state: int = 0

# Bypass flags — the move can hit a target in the corresponding state.
# Source: struct MoveInfo.damagesUnderground / .damagesAirborne / .damagesUnderwater
# Evaluated in battle_util.c :: CanBreakThroughSemiInvulnerablityInternal
@export var damages_underground: bool = false  # hits Dig users (e.g. Earthquake)
@export var damages_airborne: bool = false     # hits Fly/Bounce users (e.g. Gust, Thunder)
@export var damages_underwater: bool = false   # hits Dive users (e.g. Surf)

# ── Recoil and drain (M6) ─────────────────────────────────────────────────────
# recoil_percent: fraction of damage dealt that the attacker receives as recoil.
# Source: struct MoveInfo.argument.recoilPercentage; applied as damage * pct / 100.
# Common values: 25 (Take Down), 33 (Double-Edge, Brave Bird, Flare Blitz).
@export var recoil_percent: int = 0

# drain_percent: fraction of damage dealt that the attacker heals.
# Source: struct MoveInfo.argument.absorbPercentage (default 50 for all Absorb moves).
# Applied as heal = damage * pct / 100; heal is capped at max_hp.
@export var drain_percent: int = 0

# ── Fixed-damage moves (M6) ────────────────────────────────────────────────────
# fixed_damage > 0: always deals this exact HP regardless of stats or type eff.
# Type immunity (0.0×) still blocks the move entirely.
# Source: struct MoveInfo.argument.fixedDamage; EFFECT_FIXED_HP_DAMAGE in source.
# Examples: Dragon Rage (40), Sonic Boom (20), Night Shade / Seismic Toss use level_damage.
@export var fixed_damage: int = 0

# level_damage: damage equals the attacker's current level. Respects type immunity.
# Source: battle_util.c :: DoFixedDamageMoveCalc :: EFFECT_LEVEL_DAMAGE → gBattleMons.level
# Used by: Seismic Toss (Fighting), Night Shade (Ghost).
@export var level_damage: bool = false

# [M19-percent-current-hp-damage] percent_current_hp_damage > 0: damage is
#   this percent of the TARGET's CURRENT HP (not max HP) — genuinely
#   distinct from fixed_damage/level_damage above. Type immunity (0.0×)
#   still blocks the move entirely; skips STAB/crit/roll/stage math exactly
#   like fixed_damage/level_damage do.
# Source: battle_util.c :: DoMoveDamageCalc, case EFFECT_FIXED_PERCENT_DAMAGE
#   (L7660-7661): dmg = GetNonDynamaxHP(battlerDef) * GetMoveDamagePercentage(move) / 100.
# Used by: Super Fang(162, 50%), Ruination(803, 50%).
@export var percent_current_hp_damage: int = 0

# [M19-ignores-stat-stages] ignores_defense_evasion_stages: Chip Away(498)/
#   Sacred Sword(533)/Darkest Lariat(626) — a MOVE-level equivalent of
#   Unaware's own defense/evasion-ignore, reusing the EXACT SAME insertion
#   points (DamageCalculator's def_stage reset, StatusManager.
#   check_accuracy's eva_stage reset) rather than a new mechanism. Resets
#   the DEFENDER's Defense stage to neutral for damage calc AND their
#   Evasion stage to neutral for the accuracy roll — confirmed TWO separate
#   effects from ONE flag (source's own function name, "DefenseEvasion",
#   already names both).
# Source: include/move.h L135 (`ignoresTargetDefenseEvasionStages:1`);
#   battle_util.c :: CalcDefenseStat (L7075) and GetTotalAccuracy (L10254),
#   both via the shared `MoveIgnoresDefenseEvasionStages(move)` inline getter.
@export var ignores_defense_evasion_stages: bool = false

# ── M7: One-off / unique mechanics ────────────────────────────────────────────

# creates_substitute: user pays HP = max_hp / 4 and creates a decoy with that much HP.
# Fails if user HP ≤ max_hp / 4 (i.e. the cut would faint them).
# Incoming damaging moves hit the substitute instead of the Pokémon; when
# substitute_hp reaches 0 the substitute breaks. Status/entry effects are blocked.
# Source: battle_script_commands.c :: Cmd_setsubstitute (L7807)
#   hp = GetNonDynamaxMaxHP(attacker) / 4; fails if attacker.hp <= hp
#   substitute = TRUE; substituteHP = hp
@export var creates_substitute: bool = false

# is_protect: Protect/Detect — blocks all incoming moves for one turn.
# Consecutive use (Gen 5+) fails with probability 1/(3^n) where n = consecutive uses.
# Source: battle_util.c :: CanUseMoveConsecutively (L10862)
#   sGen5ProtectFailChances = {1, 3, 9, 27} (uses-0, 1, 2, 3+)
@export var is_protect: bool = false

# [M19c] protect_method: which Protect-family variant this move sets, using
# BattlePokemon's own PROTECT_METHOD_* constants. ALL 7 new moves (and
# Protect/Detect) share `is_protect = TRUE`'s existing dispatch — Step 0
# confirmed every one of them uses the LITERAL SAME `.effect = EFFECT_PROTECT`
# as Protect itself in source, distinguished only by a per-move
# `.argument.protectMethod` value, and the SAME shared consecutive-use
# fail-chance counter (`usesProtectCounter` is a per-EFFECT setting, not
# per-move) — zero changes needed to the existing is_protect dispatch or
# `_roll_protect_success`. Left at the class default (0 = PROTECT_METHOD_NONE)
# for Protect/Detect themselves, which is indistinguishable in practice from
# "blocks everything unconditionally" (`_is_protected_from`'s own `_` match
# branch), so their existing `.tres` data needs no change either.
@export var protect_method: int = 0

# counter: returns 2× physical damage taken this turn to the attacker.
# Priority −5. Fails if user wasn't hit by a physical move this turn.
# Source: battle_move_resolution.c :: EFFECT_REFLECT_DAMAGE (L1199)
#   physicalDmg = actual_damage+1; Counter returns (physicalDmg-1)*200/100
# Source (move data): moves_info.h MOVE_COUNTER — priority=-5, category=PHYSICAL
@export var counter: bool = false

# mirror_coat: returns 2× special damage taken this turn to the attacker.
# Priority −5. Fails if user wasn't hit by a special move this turn.
# Source: same EFFECT_REFLECT_DAMAGE handler, category=SPECIAL branch
@export var mirror_coat: bool = false

# [M19d] metal_burst: returns 1.5× damage taken this turn to the attacker —
# a GENUINELY DIFFERENT multiplier from Counter/Mirror Coat's 2x (confirmed
# individually from source, not assumed uniform), and reflects EITHER
# category (Counter is Physical-only, Mirror Coat Special-only). Priority=0
# (NOT Counter/Mirror Coat's own -5 — a real, easy-to-miss asymmetry despite
# all 3 sharing the identical `EFFECT_REFLECT_DAMAGE` handler). When damage
# was taken from BOTH categories in the same turn (doubles), reflects
# whichever was taken LAST (`BattlePokemon.last_hit_was_special`), not the
# larger of the two. Deliberately kept as its OWN separate flag rather than
# generalizing `counter`/`mirror_coat` into one data-driven mechanism —
# reuses the existing per-mon `last_physical_damage`/`last_special_damage`
# tracking directly, avoiding any risk to Counter/Mirror Coat's own
# already-tested dispatch.
# Source: moves_info.h MOVE_METAL_BURST: .argument.reflectDamage =
#   { .damagePercent = 150, .damageCategories = PHYSICAL | SPECIAL }.
@export var metal_burst: bool = false

# [M19d] is_mirror_move: calls the SAME move that most recently hit the user
# THIS TURN, targeting whoever used it — a genuinely different tracking axis
# from "the target's own last-used move" (Copycat-style). Reuses the
# pre-existing per-turn `BattleManager._last_attacker_move`/`_last_attacker`
# dictionaries (already built for Destiny Bond/Aftermath/Innards Out, cleared
# every turn) directly — no new tracking state needed. Fails if the user
# hasn't been hit by any move yet this turn. Falls through to the SAME
# "reassign `move` and let normal dispatch continue" pattern this project's
# existing Metronome redirect already established — confirmed from source
# that both dispatch through the identical `CancelerCallSubmove` mechanism
# (battle_move_resolution.c L523-553, EFFECT_MIRROR_MOVE and EFFECT_METRONOME
# are two cases of the same switch).
# Source: GetMirrorMoveMove (battle_move_resolution.c L4966-4993) reads
#   gBattleStruct->lastTakenMove[gBattlerAttacker] — the move that hit the
#   MIRROR MOVE USER, not any move the target itself used.
@export var is_mirror_move: bool = false

# destiny_bond: if this Pokémon faints before acting next turn, the KO attacker also faints.
# Fails (consecutive-use rule, Gen 7+): if already set when used again.
# Source: battle_scripts_1.s :: BattleScript_EffectDestinyBond → setvolatile destinyBond 2
#   battle_move_resolution.c :: FAINT_BLOCK_TRY_DESTINY_BOND (L2953)
@export var destiny_bond: bool = false

# is_disable: prevents the target's last-used move for 4 turns (Gen 5+).
# Fails if: target has no last move, or that move has 0 PP, or is already disabled.
# ignores_substitute = true in source (Disable reaches through substitute).
# Source: battle_script_commands.c :: Cmd_disablelastusedattack (L7898)
#   disabledMove = lastMoves[target]; disableTimer = B_DISABLE_TIMER (=4, Gen5+)
@export var is_disable: bool = false

# is_encore: forces the target to repeat its last-used move for 3 turns (Gen 5+).
# Fails if: no last move, already encored, or last move is encore-banned.
# Source: battle_script_commands.c :: Cmd_trysetencore (L7924)
#   encoreTimer = B_ENCORE_TIMER (=4); but if target hasn't acted this turn: 4-1=3
#   We always use 3 (simpler, matches typical case where target already moved).
@export var is_encore: bool = false

# [M18.5d-2] is_attract: inflicts infatuation (StatusManager.try_apply_attract) on
# the target — opposite-gender only, blocked by the target's own Oblivious or
# Aroma Veil on the target's side, fails if already infatuated. Each turn while
# infatuated, a 50% chance the holder can't move at all (StatusManager.
# pre_move_check, after Paralysis in the canceler order). Cured by the
# INFATUATED mon's own switch-out (BattleManager._clear_volatiles).
# Source: battle_script_commands.c :: Cmd_tryinfatuating (L7613-7650);
#   battle_move_resolution.c :: CancelerInfatuation (L460-479, 50% roll).
@export var is_attract: bool = false

# [M18.5g] is_triple_kick: Triple Kick / Triple Axel — the two EFFECT_TRIPLE_KICK
# moves, the only members of the 31-move multi-hit family where EACH hit (not just
# the first) rolls its own independent accuracy check, and where per-hit power
# escalates ×1/×2/×3 (base power × the 1-indexed hit number) rather than staying
# flat. Confirmed via ShouldSkipAccuracyCalcPastFirstHit (battle_move_resolution.c
# L2137-2151), which explicitly excepts EFFECT_TRIPLE_KICK (and EFFECT_POPULATION_
# BOMB, excluded from this project's scope — see strike_count's own doc comment)
# from the "only hit 1 checks accuracy" rule every other strike_count/multi_hit
# move follows; escalation formula confirmed via battle_util.c L6165-6167
# (`basePower *= 1 + GetMoveStrikeCount(move) - gMultiHitCounter`, which reduces
# to a flat ×hit_number multiplier for a fixed-strikeCount move). Both moves also
# set strike_count=3 (the fixed-hit path is still used to determine the MAXIMUM
# hit count reachable — 3 — even though each hit can independently miss and stop
# the sequence early, unlike every other strike_count move).
@export var is_triple_kick: bool = false

# [M18.5g] is_scale_shot: a ONE-TIME self stat change (-1 Defense, +1 Speed)
# applied ONCE after the whole multi-hit sequence completes, gated on at least one
# hit having landed — NOT per hit. Confirmed via source's MoveEnd-table dispatch
# (battle_move_resolution.c L3620-3628, case EFFECT_SCALE_SHOT), the same
# once-at-sequence-end shape as Shell Bell's own accumulate-then-apply-once
# pattern (see BattleManager._do_multi_hit_sequence's own doc comment).
@export var is_scale_shot: bool = false

# is_bide: stores damage taken over 2 waiting turns then releases 2× total.
# Priority +1 (Gen 4+). Locks into Bide via charging_move.
# Source: battle_move_resolution.c :: CancelerBide (L1106)
#   bideTurns=2 on setup; each activation: decrement; when 0 → release 2×gBideDmg
# Damage is accumulated from direct hits (not through substitute).
@export var is_bide: bool = false

# is_metronome: calls a random non-banned move from the move registry.
# Source: battle_move_resolution.c :: GetMetronomeMove (L4998)
#   RandomUniformExcept from moves pool, filter = InvalidMetronomeMove
#   which checks metronomeBanned flag (= ban_flags & BAN_METRONOME in our system).
@export var is_metronome: bool = false

# ── M9: Switching mechanics ────────────────────────────────────────────────────

# is_roar: forces the target to switch to a random party member (Roar, Whirlwind).
# Priority −6 (GEN_LATEST). Accuracy 0 (always hits in Gen6+). Fails if the
# target has no valid non-fainted, non-active party member to switch in.
# Source: src/data/moves_info.h MOVE_ROAR (L1234) / MOVE_WHIRLWIND (L482)
#   .effect = EFFECT_ROAR; .priority = -6; .accuracy = 0 (B_UPDATED >= GEN_6)
#   .ignoresProtect = TRUE; .ignoresSubstitute = TRUE (B_UPDATED_MOVE_FLAGS >= GEN_6)
#   .soundMove = TRUE
@export var is_roar: bool = false

# is_baton_pass: user switches out, passing stat stages and certain volatiles to
# the incoming Pokémon (confusion_turns, substitute_hp; stat_stages always passed).
# Source: src/data/moves_info.h MOVE_BATON_PASS (L6164); .effect = EFFECT_BATON_PASS
# Source: battle_main.c :: SwitchInClearSetData() (L3117) — baton-passable list
#   Stat stages NOT cleared (L3122 skipped for Baton Pass).
#   confusionTurns (VOLATILE_CONFUSION) — V_BATON_PASSABLE (constants/battle.h L210)
#   substituteHP — explicitly copied (L3185)
@export var is_baton_pass: bool = false

# ── M14b: Doubles move effects ─────────────────────────────────────────────────

# Target type constants — source: include/constants/battle.h :: enum MoveTarget
# These mirror the C enum values used in moves_info.h .target fields.
const TARGET_NONE:           int = 0
const TARGET_SELECTED:       int = 1  # single selected target (most moves)
const TARGET_SMART:          int = 2  # like SELECTED but can smart-redirect with multi-hit
const TARGET_DEPENDS:        int = 3
const TARGET_OPPONENT:       int = 4  # one random opponent
const TARGET_RANDOM:         int = 5  # random target including ally
const TARGET_BOTH:           int = 6  # all opponents (Earthquake, Surf, etc.)
const TARGET_USER:           int = 7  # user only (Follow Me, Protect)
const TARGET_ALLY:           int = 8  # partner only (Helping Hand, Gen 4+)
const TARGET_USER_AND_ALLY:  int = 9
const TARGET_USER_OR_ALLY:   int = 10
const TARGET_FOES_AND_ALLY:  int = 11 # all opponents + user's ally (Explosion, etc.)
const TARGET_FIELD:          int = 12 # whole-field effects (Rain Dance, etc.)
const TARGET_OPPONENTS_FIELD: int = 13
const TARGET_ALL_BATTLERS:   int = 14

# is_spread: move hits all opponents simultaneously in doubles (TARGET_BOTH or
# TARGET_FOES_AND_ALLY). Spread moves receive a 0.75× damage reduction per target
# when ≥2 targets are live at move-use time (Gen 4+).
# Source: IsSpreadMove (include/battle.h L1163):
#   moveTarget == TARGET_BOTH || moveTarget == TARGET_FOES_AND_ALLY
# Source: GetTargetDamageModifier (battle_util.c L7220):
#   if GetMoveTargetCount >= 2 → UQ_4_12(0.75) = 3072; applied as first post-base modifier.
# Examples: Earthquake, Surf, Discharge, Rock Slide (doubles spread flag set in source).
@export var is_spread: bool = false

# is_helping_hand: grants the user's ally a 1.5× base-power boost on their next move.
# Fails in singles, or if the ally has already moved this turn or is fainted.
# Source: Cmd_trysethelpinghand (battle_script_commands.c L8850): sets
#   gProtectStructs[ally].helpingHand++; cleared by TurnValuesCleanUp at turn end.
# Source: CalcMoveBasePowerAfterModifiers (battle_util.c L6436):
#   1.5× applied to base power; priority = 5.
# Target: TARGET_ALLY (Gen 4+), priority = +5.
@export var is_helping_hand: bool = false

# is_follow_me: redirects all incoming single-target moves toward the user this turn.
# Also covers Rage Powder (same EFFECT_FOLLOW_ME in source; adds powder_move flag).
# Source: Cmd_setforcedtarget (battle_script_commands.c L8748):
#   gSideTimers[GetBattlerSide(self)].followmeTimer = 1; followmeTarget = self.
# Source: IsAffectedByFollowMe (battle_move_resolution.c L799):
#   redirects TARGET_SELECTED/SMART/OPPONENT/RANDOM; spread moves bypass entirely.
# Source: GetBattleMoveTarget (battle_util.c L5529): redirect at target resolution.
# Cleared by TurnValuesCleanUp at turn end.
# Target: TARGET_USER; priority = +2.
@export var is_follow_me: bool = false

# ── M15 Task 5: Two-turn move extras ─────────────────────────────────────────

# is_solar_beam: Solar Beam fires immediately (no charge turn) in harsh sun.
# Source: CanTwoTurnMoveFireThisTurn (battle_move_resolution.c L1664) — returns
#   TRUE when attackerWeather|weather & GetMoveTwoTurnAttackWeather == B_WEATHER_SUN.
#   Only Solar Beam has this field set; all semi-inv moves (Fly/Dig/Dive/Bounce)
#   can NEVER fire early (CanTwoTurnMoveFireThisTurn returns FALSE for semiInvulnerableEffect).
@export var is_solar_beam: bool = false

# charge_turn_defense_boost: defense stages added to the user on the charge turn only.
# Source: moves_info.h MOVE_SKULL_BASH :: additionalEffects {MOVE_EFFECT_STAT_PLUS,
#   .defense = 1, .self = TRUE, .onChargeTurnOnly = TRUE}.
# Only Skull Bash uses this; value is 1.
@export var charge_turn_defense_boost: int = 0

# [M19-charge-turn-spatk-boost] charge_turn_spatk_boost: Sp.Atk stages added
#   to the user on the charge turn only — a deliberate PARALLEL field to
#   charge_turn_defense_boost above, not a generalization of it (generalizing
#   risks Skull Bash's own already-working behavior; a parallel field is
#   safer despite minor duplication, per this project's own scope decision).
# Source: moves_info.h MOVE_METEOR_BEAM/MOVE_ELECTRO_SHOT :: additionalEffects
#   {MOVE_EFFECT_STAT_PLUS, .spAtk = 1, .self = TRUE, .onChargeTurnOnly = TRUE}.
# Used by: Meteor Beam(728), Electro Shot(833); value is 1 for both.
@export var charge_turn_spatk_boost: int = 0

# [M19-charge-turn-spatk-boost] skips_charge_in_rain: Electro Shot ONLY —
#   the same early-release shortcut SHAPE as is_solar_beam's sun-skip, but
#   gated on RAIN. A genuinely separate flag from charge_turn_spatk_boost —
#   Meteor Beam has the stat boost but NOT this skip (confirmed
#   individually from source, not assumed symmetric between the two moves).
# Source: moves_info.h MOVE_ELECTRO_SHOT :: .argument.twoTurnAttack =
#   { .weather = B_WEATHER_RAIN }; battle_util.c :: CanTwoTurnMoveFireThisTurn
#   reads this generically (Solar Beam's own entry uses B_WEATHER_SUN).
@export var skips_charge_in_rain: bool = false

# ── M15 Task 3: PP System ─────────────────────────────────────────────────────

# is_struggle: this move is Struggle — used when all PP are exhausted.
# Struggle: power=50, TYPE_MYSTERY (typeless — no STAB, no type effectiveness),
#   Physical, makes_contact=true, accuracy=0 (always hits), recoil=max_hp/4 (NOT
#   % of damage dealt — see MOVE_EFFECT_RECOIL_HP_25 in battle_script_commands.c L2536).
# PP is never decremented for Struggle (CancelerPPDeduction skips if cv->move == MOVE_STRUGGLE).
# Source: moves_info.h MOVE_STRUGGLE; battle_move_resolution.c L979 (PP skip);
#   battle_script_commands.c L2534–2543 (HP/4 recoil); battle_main.c L4727-4728
#   (noValidMoves → MOVE_STRUGGLE substitution).
@export var is_struggle: bool = false

# ── M16a move effects ─────────────────────────────────────────────────────────

# is_restore_hp: Recover / Slack Off / Heal Order — heals max_hp / 2.
# Fails if attacker is already at full HP.
# Source: battle_script_commands.c :: Cmd_tryhealhalfhealth (L7016)
#   SetHealAmount(target, GetNonDynamaxMaxHP(target) / 2)
@export var is_restore_hp: bool = false

# is_focus_energy: Focus Energy — raises crit stage by +2 (Gen 3+, B_FOCUS_ENERGY_CRIT_RATIO >= GEN_3).
# Volatile; cleared on switch-out and faint. Fails if already active.
# Source: battle_script_commands.c :: Cmd_setfocusenergy (L7718)
# Source: battle_util.c :: CalcCritChanceStage (L7836): focusEnergy adds +2 to critChance stage.
@export var is_focus_energy: bool = false

# is_growth: Growth — raises Atk +1 and SpAtk +1 (Gen 5+, B_UPDATED_MOVE_DATA >= GEN_5).
# In harsh sun (WEATHER_SUN): raises +2 to both instead.
# Source: src/data/moves_info.h MOVE_GROWTH (L2003–2026): both attack and spAtk raised.
# Source: battle_stat_change.c :: AdjustStatStage (L800): sun doubles the stage for EFFECT_GROWTH.
@export var is_growth: bool = false

# is_ohko: OHKO moves (Guillotine/Horn Drill/Fissure/Sheer Cold) — instant KO on hit.
# Level check: fails if defender.level > attacker.level.
# Custom accuracy: move.accuracy + (attacker.level − defender.level), rolled vs randi() % 100.
# Damage = defender.current_hp (instant KO). Bypasses normal damage formula entirely.
# Source: battle_util.c :: DoesOHKOMoveMissTarget (L10378)
# Source: battle_util.c L7696: case EFFECT_OHKO: dmg = gBattleMons[ctx->battlerDef].hp
@export var is_ohko: bool = false

# ── M16b move effects ─────────────────────────────────────────────────────────

# is_minimize: Minimize — self-targeting, raises Evasion +2 (Gen 5+, B_MINIMIZE_EVASION
#   >= GEN_5) and sets attacker.minimized = true if the evasion raise actually landed.
# Source: src/data/moves_info.h MOVE_MINIMIZE: additionalEffects {STAT_CHANGE_EFFECT_PLUS,
#   .evasion = (B_MINIMIZE_EVASION >= GEN_5) ? 2 : 1} — GEN_LATEST config → +2.
# Source: battle_stat_change.c :: SetAdditionalEffectsOnStatChange, case EFFECT_MINIMIZE (L1000):
#   volatiles.minimize = TRUE only if MOVE_RESULT_STAT_CHANGED (i.e. the raise succeeded).
@export var is_minimize: bool = false

# is_defense_curl: Defense Curl — self-targeting, raises Defense +1 and unconditionally
#   sets attacker.defense_curled = true (not gated on the stat raise succeeding).
# Source: src/data/moves_info.h MOVE_DEFENSE_CURL: additionalEffects
#   {STAT_CHANGE_EFFECT_PLUS, .defense = 1}.
# Source: battle_stat_change.c :: SetAdditionalEffectsOnStatChange, case EFFECT_DEFENSE_CURL
#   (L997): volatiles.defenseCurl = TRUE unconditionally.
@export var is_defense_curl: bool = false

# double_power_on_minimized: Stomp (and Astonish, Extrasensory, Needle Arm, Steamroller,
#   Body Slam, Flying Press, etc.) deal a ×2.0 damage modifier against a minimized target.
# This is a standalone post-roll damage MULTIPLIER, not a doubling of the base power input —
# confirmed from source: GetMinimizeModifier (battle_util.c L7319) is folded into
# GetOtherModifiers, which fires inside ApplyModifiersAfterDmgRoll (after the random roll,
# STAB, type effectiveness, and burn — the same modifier group as ability/item damage mods).
# Source: struct MoveInfo.minimizeDoubleDamage (include/move.h L132).
@export var double_power_on_minimized: bool = false

# is_rollout: Rollout / Ice Ball — power doubles each consecutive successful hit
#   (30→60→120→240→480 over 5 hits), then resets. Defense Curl doubles the starting power.
# Source: battle_util.c :: CalcRolloutBasePower (L6034-6042):
#   basePower = move.power; basePower <<= rolloutTimer; if (defenseCurl) basePower *= 2.
# Source: battle_move_resolution.c :: SetSameMoveTurnValues, case EFFECT_ROLLOUT (L4899-4909):
#   on a successful consecutive hit, rolloutTimer increments (locks up to 5 uses, then resets
#   to 0); using any other move (the switch's `default` branch, L4915-4917) unconditionally
#   resets rolloutTimer to 0 — this is how "interruption" resets the counter.
@export var is_rollout: bool = false

# is_magnitude: Magnitude — variable base power rolled fresh each use from a weighted table.
# Source: battle_move_resolution.c :: CalculateMagnitudeDamage (L5196-5234):
#   roll = RandomUniform(0, 99); weighted bands →
#   [0,5)=10, [5,15)=30, [15,35)=50, [35,65)=70, [65,85)=90, [85,95)=110, [95,100)=150.
#   (5%, 10%, 20%, 30%, 20%, 10%, 5% respectively.)
@export var is_magnitude: bool = false

# ── M16c: Screens (side conditions) ──────────────────────────────────────────

# is_reflect: Reflect — side-wide, halves damage from Physical-category moves hitting the
#   caster's side for 5 turns. Fails (does not refresh) if already up on that side.
# Source: src/data/moves_info.h MOVE_REFLECT: .effect = EFFECT_REFLECT, .accuracy = 0,
#   .pp = 20, .target = TARGET_USER, .ignoresProtect = TRUE.
# Source: battle_script_commands.c :: TrySetReflect (L2088-2106): fails if
#   gSideStatuses[side] & SIDE_STATUS_REFLECT already set; else sets it and
#   gSideTimers[side].reflectTimer = 5 (8 with Light Clay — not modeled, no held-item
#   duration extension in this project's scope yet).
@export var is_reflect: bool = false

# is_light_screen: Light Screen — same shape as Reflect, but for Special-category moves.
# Source: src/data/moves_info.h MOVE_LIGHT_SCREEN: .effect = EFFECT_LIGHT_SCREEN,
#   .accuracy = 0, .pp = 30, .target = TARGET_USER, .ignoresProtect = TRUE.
# Source: battle_script_commands.c :: TrySetLightScreen (L2109-2127): same shape as
#   TrySetReflect but SIDE_STATUS_LIGHTSCREEN / lightscreenTimer.
@export var is_light_screen: bool = false

# [Bucket 3 screen+damage] sets_reflect_on_hit / sets_light_screen_on_hit:
# Glitzy Glow / Baddy Bad — EFFECT_HIT damage moves (unlike is_reflect/
# is_light_screen above, which are pure EFFECT_REFLECT/EFFECT_LIGHT_SCREEN
# status moves with no damage at all) that ALSO set a screen on the user's
# OWN side as a guaranteed (no .chance field — primary, not a true secondary,
# so Shield Dust/Sheer Force/Serene Grace do not apply) self-targeted
# additional effect after dealing damage. Source: moves_info.h MOVE_GLITZY_
# GLOW/MOVE_BADDY_BAD: .effect = EFFECT_HIT, additionalEffects = {.moveEffect
# = MOVE_EFFECT_LIGHT_SCREEN/MOVE_EFFECT_REFLECT, .self = TRUE}. Source:
# battle_script_commands.c :: SetMoveEffect, case MOVE_EFFECT_REFLECT/
# MOVE_EFFECT_LIGHT_SCREEN (L2876-2889) — the exact same TrySetReflect/
# TrySetLightScreen calls is_reflect/is_light_screen already use (same
# already-up no-refresh check, same Light Clay duration extension), just
# reached via the damage-dispatch path instead of the pure-status-move path,
# since a damaging move can never take the is_reflect/is_light_screen early-
# return branch (that branch never deals damage at all).
@export var sets_reflect_on_hit: bool = false
@export var sets_light_screen_on_hit: bool = false

# is_aurora_veil: Aurora Veil — combines Reflect + Light Screen in a single slot (reduces
#   BOTH Physical and Special damage), 5 turns. Requires Hail active or fails outright
#   (checked BEFORE the "already up" check). Independent bitmask from Reflect/Light Screen —
#   can coexist with either or both already up on the same side (does not stack the
#   reduction multiplicatively; see DamageCalculator's screen modifier).
# Source: src/data/moves_info.h MOVE_AURORA_VEIL: .effect = EFFECT_AURORA_VEIL,
#   .accuracy = 0, .pp = 20, .target = TARGET_USER, .ignoresProtect = TRUE.
# Source: battle_move_resolution.c (L1191-1193): case EFFECT_AURORA_VEIL — fails
#   (BattleScript_ButItFailed) unless GetWeather() & B_WEATHER_ICY_ANY. This project only
#   models Hail (no separate Snow weather), so the gate simplifies to weather == WEATHER_HAIL.
# Source: src/battle_script_commands.c :: BS_SetAuroraVeil (L13439-13462): fails only if
#   SIDE_STATUS_AURORA_VEIL already set (does NOT check Reflect/Light Screen — independent
#   slot). auroraVeilTimer = 5 (8 with Light Clay — not modeled).
@export var is_aurora_veil: bool = false

# breaks_screens: Brick Break — clears ALL screens (Reflect/Light Screen/Aurora Veil) on the
#   target's side, then deals damage as normal. The removal fires BEFORE this hit's own
#   damage calc (preAttackEffect=TRUE in source), so a screen this move itself breaks does
#   NOT reduce its own damage.
# Source: src/data/moves_info.h MOVE_BRICK_BREAK: .effect = EFFECT_HIT, .power = 75,
#   .type = TYPE_FIGHTING, .accuracy = 100, .pp = 15, .makesContact = TRUE.
#   additionalEffects = {MOVE_EFFECT_BREAK_SCREEN, .preAttackEffect = TRUE}.
# Source: src/battle_script_commands.c :: MOVE_EFFECT_BREAK_SCREEN case (L3308-3336):
#   B_BRICK_BREAK >= GEN_4 (GEN_LATEST config) → clears GetBattlerSide(target) — the
#   move's actual target's side, not hardcoded to "the opponent's side" (matters if Brick
#   Break is used on an ally in doubles). Only clears/emits if a screen was actually up.
@export var breaks_screens: bool = false

# ── M16d: Entry hazards + Trick Room ─────────────────────────────────────────

# is_spikes: Spikes — layered (max 3) entry hazard set on the OPPONENT's side. Damages
#   grounded Pokémon on switch-in: maxHP / ((5 - layers) * 2) → 1/8 (1 layer), 1/6 (2),
#   1/4 (3). Fails (does not wrap) if the opponent's side already has 3 layers.
# Source: src/data/moves_info.h MOVE_SPIKES: .effect = EFFECT_SPIKES, .accuracy = 0,
#   .pp = 20, .target = TARGET_OPPONENTS_FIELD, .ignoresProtect = TRUE.
# Source: src/battle_script_commands.c :: Cmd_trysetspikes (L8373-8390): fails at
#   spikesAmount == 3; else spikesAmount++.
# Source: src/battle_switch_in.c :: TryHazardsOnSwitchIn, case HAZARDS_SPIKES
#   (L306-315): spikesDmg = maxHP / ((5 - spikesAmount) * 2); requires grounded.
@export var is_spikes: bool = false

# is_toxic_spikes: Toxic Spikes — layered (max 2) entry hazard set on the OPPONENT's side.
#   1 layer poisons a grounded switch-in; 2 layers badly poisons (toxic) instead. A
#   grounded Poison-type switch-in ABSORBS (clears) the hazard instead of being poisoned.
#   Ungrounded Pokémon are entirely unaffected (no absorb, no poison).
# Source: src/data/moves_info.h MOVE_TOXIC_SPIKES: .effect = EFFECT_TOXIC_SPIKES,
#   .accuracy = 0, .pp = 20, .target = TARGET_OPPONENTS_FIELD, .ignoresProtect = TRUE.
# Source: src/battle_script_commands.c :: Cmd_settoxicspikes (L9043-9059): fails at
#   toxicSpikesAmount >= 2; else toxicSpikesAmount++.
# Source: src/battle_switch_in.c :: TryHazardsOnSwitchIn, case HAZARDS_TOXIC_SPIKES
#   (L328-359): ungrounded → no effect; Poison-type → absorb (clear hazard); else
#   CanBePoisoned → STATUS1_POISON (1 layer) or STATUS1_TOXIC_POISON (2 layers).
@export var is_toxic_spikes: bool = false

# is_stealth_rock: Stealth Rock — single-application hazard (no layers) set on the
#   OPPONENT's side. Damages EVERY switch-in (including Flying-types and Levitate holders —
#   NOT a grounded-only check, unlike Spikes/Toxic Spikes) based on Rock-type effectiveness
#   against the switching-in Pokémon's typing: 0×→0, 0.25×→maxHP/32, 0.5×→maxHP/16,
#   1×→maxHP/8, 2×→maxHP/4, 4×→maxHP/2 (each nonzero case floors to a minimum of 1).
# Source: src/data/moves_info.h MOVE_STEALTH_ROCK: .effect = EFFECT_STEALTH_ROCK,
#   .accuracy = 0, .pp = 20, .target = TARGET_OPPONENTS_FIELD, .ignoresProtect = TRUE.
# Source: src/battle_script_commands.c :: MOVE_EFFECT_STEALTH_ROCK case (L2707-2712):
#   fails if IsHazardOnSide already true (single application, no stacking).
# Source: src/battle_util.c :: GetStealthHazardDamageByTypesAndHP (L8317-8353) with
#   hazardType = TYPE_SIDE_HAZARD_POINTED_STONES = TYPE_ROCK (include/constants/battle.h
#   L430-434).
@export var is_stealth_rock: bool = false

# is_rapid_spin: Rapid Spin — a normal damaging move (power=50, GEN_8+ config) that ALSO
#   clears exactly ONE hazard type from the user's OWN side after dealing damage (fires
#   even if the hit landed on a Substitute). Order of removal when multiple hazard types
#   are up: Spikes → Toxic Spikes → Stealth Rock (matches this project's implemented subset
#   of the source's hazard-type enum order; Sticky Web/Steelsurge are out of scope). Only
#   fires if the move actually dealt damage this turn — a missed or Protect-blocked Rapid
#   Spin clears nothing.
# Source: src/data/moves_info.h MOVE_RAPID_SPIN: .effect = EFFECT_RAPID_SPIN, .power = 50
#   (B_UPDATED_MOVE_DATA >= GEN_8), .type = TYPE_NORMAL, .accuracy = 100, .pp = 40,
#   .makesContact = TRUE.
# Source: src/battle_move_resolution.c, case EFFECT_RAPID_SPIN (L3569-3574):
#   IsAnyTargetTurnDamaged(battlerAtk, INCLUDING_SUBSTITUTES) gates the effect.
# Source: src/battle_script_commands.c :: Cmd_rapidspinfree (L8578-8612): checks
#   wrapped → leechSeed → one hazard type (loop-and-return-on-first-match) on the
#   ATTACKER's own side. This project has no Bind/Wrap trapping moves or Leech Seed
#   implemented yet, so only the hazard-clearing branch applies here — noted as a
#   follow-up gap rather than silently ignored.
@export var is_rapid_spin: bool = false

# is_trick_room: Trick Room — field-wide (not side-wide) effect that reverses turn order
#   within each priority bracket for 5 turns: the normally-slower Pokémon acts first.
#   Priority brackets themselves are UNCHANGED — a priority move still always goes before
#   a non-priority move; Trick Room only inverts the speed tiebreak used when two actions
#   share the same priority. TOGGLES rather than fails: using Trick Room again while it's
#   already active immediately cancels it (does not refresh to a fresh 5 turns).
# Source: src/data/moves_info.h MOVE_TRICK_ROOM: .effect = EFFECT_TRICK_ROOM,
#   .accuracy = 0, .pp = 5, .target = TARGET_FIELD, .priority = -7 (very low — even lower
#   than Roar/Whirlwind's -6), .ignoresProtect = TRUE.
# Source: src/battle_script_commands.c :: HandleRoomMove (L9116-9121): if the field status
#   is already set, clear it (timer = 0) instead of refreshing; else set it (timer = 5).
# Source: src/battle_main.c :: GetWhichBattlerFasterArgs (L4775-4821): priority is compared
#   FIRST (unaffected by Trick Room); only when priority1 == priority2 does the speed
#   comparison invert under STATUS_FIELD_TRICK_ROOM (lower effective speed strikes first).
@export var is_trick_room: bool = false

# ── M16e: Tier E move effects ────────────────────────────────────────────────

# is_pursuit: Pursuit — a normal 40-power Dark-type hit that doubles power (80) when its
#   target chose to switch out THIS turn. Also executes BEFORE the switch resolves, hitting
#   the still-present outgoing Pokémon (not the incoming replacement). Handled with dedicated
#   turn-order interception in BattleManager._phase_priority_resolution (switches otherwise
#   always sort before all move actions in this engine) rather than as a pure damage
#   modifier — see _pursuit_targets_switcher().
# Source: src/data/moves_info.h MOVE_PURSUIT: .effect = EFFECT_PURSUIT, .power = 40,
#   .type = TYPE_DARK, .accuracy = 100, .pp = 20, .category = DAMAGE_CATEGORY_PHYSICAL,
#   .makesContact = TRUE.
# Source: src/battle_util.c L6180-6182 (EFFECT_PURSUIT base-power case): `if
#   (gBattleStruct->battlerState[battlerDef].pursuitTarget) basePower *= 2;`
# Source: src/battle_util.c :: SetTargetToNextPursuiter (L9827), IsPursuitTargetSet (L9850),
#   ClearPursuitValues (L9860) — the interception/reordering machinery.
# Source: src/battle_script_commands.c :: Cmd_jumpifnopursuitswitchdmg (L8494) — fires when
#   a switch action is about to resolve; reorders a queued Pursuit user (GEN_LATEST:
#   B_PURSUIT_TARGET >= GEN_4 means ANY opposing Pursuit user intercepts, not only one that
#   specifically targeted the switcher) to strike first.
# Known simplification: source supports CHAINING multiple pursuers against the same
#   switcher one-at-a-time via MoveEndPursuitNextAction (battle_move_resolution.c L4321).
#   This project instead lets every intercepting Pursuit user act (in normal speed order)
#   before the switch resolves — same end state for the common 1-pursuer case; documented
#   as a deliberate gap for the rare multi-pursuer doubles case.
@export var is_pursuit: bool = false

# ── M19-pre1: weight-based and friendship-based dynamic power ───────────────

# is_low_kick_power: Low Kick / Grass Knot — power derived from the TARGET's own
#   weight (PokemonSpecies.weight, hectograms), via a fixed threshold table. Not the
#   attacker's weight, and not a ratio — confirmed a genuinely different formula from
#   is_heat_crash_power below despite both being "weight-based."
# Source: src/battle_util.c :: CalcMoveBasePowerAfterModifiers, case EFFECT_LOW_KICK
#   (L6216-6225): `weight = GetBattlerWeight(battlerDef); for (...) if
#   (sWeightToDamageTable[i] > weight) break; basePower = sWeightToDamageTable[i+1];`
#   sWeightToDamageTable (L6022-6029, threshold/power pairs, hectograms):
#   <100→20, <250→40, <500→60, <1000→80, <2000→100, else→120.
#   GetBattlerWeight's own modifier chain (Autotomize/Heavy Metal/Light Metal/Float
#   Stone, L5913-5940) is confirmed entirely absent from this project (grep, zero
#   hits for all four) — raw species weight is used directly, no adjustment needed.
@export var is_low_kick_power: bool = false

# is_heat_crash_power: Heavy Slam / Heat Crash — power derived from the INTEGER
#   RATIO of the attacker's weight to the target's weight (both PokemonSpecies.weight,
#   hectograms), via a fixed lookup table indexed by the ratio directly (capped).
# Source: src/battle_util.c, case EFFECT_HEAT_CRASH (L6227-6233): `weight =
#   GetBattlerWeight(battlerAtk) / GetBattlerWeight(battlerDef);` (integer division);
#   `if (weight >= ARRAY_COUNT(sHeatCrashPowerTable)) basePower =
#   sHeatCrashPowerTable[last]; else basePower = sHeatCrashPowerTable[weight];`
#   sHeatCrashPowerTable (L6033): {40, 40, 60, 80, 100, 120} — ratio 0-1→40, 2→60,
#   3→80, 4→100, 5+→120. Same GetBattlerWeight modifier-chain-is-moot finding as
#   is_low_kick_power above.
@export var is_heat_crash_power: bool = false

# is_return_power: Return / Pika Papow / Veevee Volley — power derived from the
#   ATTACKER's own friendship (BattlePokemon.friendship, 0-255). Confirmed Pika Papow
#   and Veevee Volley share this EXACT formula (both literally .effect = EFFECT_RETURN
#   in source, not a separate/similar effect) — not assumed from their similar
#   in-game descriptions.
# Source: src/battle_util.c, case EFFECT_RETURN (L6148-6150): `basePower = 10 *
#   (gBattleMons[battlerAtk].friendship) / 25;` (integer division). A universal
#   `if (basePower == 0) basePower = 1;` floor applies after the whole switch
#   (L6371-6372) — friendship=0 would otherwise compute power=0.
@export var is_return_power: bool = false

# is_frustration_power: Frustration — the INVERSE of is_return_power: power derived
#   from (MAX_FRIENDSHIP - friendship), NOT friendship directly. Confirmed the exact
#   inverse relationship from source rather than assumed to mirror Return's own
#   formula directly (higher friendship = LOWER Frustration power).
# Source: src/battle_util.c, case EFFECT_FRUSTRATION (L6151-6153): `basePower = 10 *
#   (MAX_FRIENDSHIP - gBattleMons[battlerAtk].friendship) / 25;` MAX_FRIENDSHIP=255
#   (include/constants/pokemon.h L223). Same universal power==0→1 floor applies
#   (friendship=255 would otherwise compute power=0).
@export var is_frustration_power: bool = false

# [M19-hp-based-power] is_flail_power: Flail(175)/Reversal(179) — power from
#   the USER'S OWN missing-HP fraction, a STEPPED/BANDED formula, confirmed
#   NOT continuous (a real risk this task's own Step 0 flagged and verified
#   from source directly rather than assuming a smooth curve). Both moves
#   share the LITERAL SAME `.effect = EFFECT_FLAIL` in source.
# Source: battle_util.c, case EFFECT_FLAIL (L6138-6145) — see
#   BattleManager._flail_power's own doc comment for the full table citation.
@export var is_flail_power: bool = false

# [M19-stat-raised-trigger] requires_target_stat_raised: Burning
#   Jealousy(735)/Alluring Voice(842) — the secondary (burn/confusion) only
#   applies if the TARGET's stats rose THIS TURN, from ANY source (a move,
#   ability, or item — a broad, general concept in source, not move-driven
#   specifically). Neither move raises stats itself, so self-triggering
#   isn't a real risk for these 2 — confirmed from source, not assumed.
#   Both moves already gate on the SAME pre-existing "already has a status"/
#   "already confused" check every other status/confusion move uses
#   (`!gBattleMons[effectBattler].status1`-equivalent), so no separate gate
#   was needed for that half.
# Source: include/move.h L35 (`onlyIfTargetRaisedStats:1`); dispatch via
#   AdditionalEffectsMoveConditionMet (battle_script_commands.c L3481-3483)
#   — see StatusManager.try_secondary_effect's own doc comment for the
#   exact citation and insertion point (before the chance roll).
@export var requires_target_stat_raised: bool = false

# [Bucket 4 cheapest singles] is_rage: Rage(99) — a guaranteed, self-targeted
#   EFFECT_HIT additional effect (`.self = TRUE`, no `.chance` field) that sets
#   `BattlePokemon.rage_active` on a successful hit — see that field's own doc
#   comment for the full set/clear lifecycle.
# Source: src/data/moves_info.h MOVE_RAGE: .effect = EFFECT_HIT, .power = 20,
#   .type = TYPE_NORMAL, .accuracy = 100, .pp = 20, .makesContact = TRUE.
# Source: src/battle_script_commands.c :: MoveEndRage (battle_move_resolution.c
#   L2669-2689) — the REACTIVE half (raises Attack +1 whenever the rage_active
#   holder takes ANY damaging hit, excluding self-hits and ally-hits, capped at
#   +6) is dispatched separately in BattleManager._do_damaging_hit, keyed on
#   the DEFENDER's own rage_active flag, not on this flag.
@export var is_rage: bool = false

# [Bucket 4 cheapest singles] is_clear_smog: Clear Smog(499) — resets ALL 7 of
#   the target's stat stages to exactly 0 (an absolute reset, NOT a relative
#   stat_change_amount delta — the existing stat_change_stat/amount schema
#   cannot represent this at all). No-ops silently if the target's stats were
#   already all at 0 (matching source's own pre-check), and only fires if the
#   hit actually connected.
# Source: src/data/moves_info.h MOVE_CLEAR_SMOG: .effect = EFFECT_HIT,
#   .power = 50, .type = TYPE_POISON, .accuracy = 0 (never misses — accuracy
#   check bypassed, not "always fails"), .pp = 15.
# Source: src/battle_script_commands.c :: case MOVE_EFFECT_CLEAR_SMOG
#   (L2558-2571): loops NUM_BATTLE_STATS, resets each to DEFAULT_STAT_STAGE(0),
#   gated on `IsBattlerTurnDamaged(...) && <at least one stat != 0>`.
@export var is_clear_smog: bool = false

# [Bucket 4 cheapest singles] is_incinerate: Incinerate(510) — destroys the
#   target's held item OUTRIGHT (no consumption effect triggers — no Cheek
#   Pouch heal, no Harvest/Cud Chew last-consumed-berry registration) if it's
#   a Berry (this project has no Gem items, so the Gen6+ Gem half of source's
#   condition is permanently moot here). Blocked by the target's Sticky Hold.
#   Correctly triggers Unburden on the target (source calls CheckSetUnburden
#   directly from this same case) via a small dedicated destroy-path, NOT this
#   project's existing `_consume_item` (which would incorrectly also trigger
#   Cheek Pouch / set last_consumed_berry — confirmed from source that
#   Incinerate's own case never calls the consumption-effect dispatch chain
#   those two features hook into).
# Source: src/data/moves_info.h MOVE_INCINERATE: .effect = EFFECT_HIT,
#   .power = 60 (GEN_LATEST >= GEN_6), .type = TYPE_FIRE, .accuracy = 100,
#   .pp = 15, .target = TARGET_BOTH (spread).
# Source: src/battle_script_commands.c :: case MOVE_EFFECT_INCINERATE
#   (L2626-2639).
@export var is_incinerate: bool = false

# [Bucket 4 cheapest singles] is_sparkling_aria: Sparkling Aria(627) — cures
#   BURN specifically on whichever battler(s) it hits (the TARGET's own status,
#   not the user's — the inverse of every existing self-cure precedent in this
#   project). `.sheerForceOverride = TRUE` in source is redundant/defensive
#   here: this project's own is_true_secondary gate (secondary_chance > 0)
#   already exempts a chance=0/omitted guaranteed effect from Sheer Force, and
#   this dispatches via a dedicated flag/branch rather than the SE_* schema at
#   all (no existing SE_* token represents "cure a status FROM the target").
# Source: src/data/moves_info.h MOVE_SPARKLING_ARIA: .effect = EFFECT_HIT,
#   .power = 90, .type = TYPE_WATER, .accuracy = 100, .pp = 10,
#   .target = TARGET_FOES_AND_ALLY (spread), .soundMove = TRUE,
#   .argument.status = STATUS1_BURN.
# Source: src/battle_script_commands.c :: case MOVE_EFFECT_REMOVE_STATUS
#   (L3270-3289): only cures if the target currently HAS that exact status.
@export var is_sparkling_aria: bool = false

# [Bucket 4 cheapest singles] cant_use_twice: Blood Moon(829) — fails at
#   execution if this exact move was the user's own last move used (compares
#   against BattlePokemon.last_move_used by reference, the same equality-by-
#   loaded-resource pattern this project's existing Disable check already
#   uses). Real source gates this at SELECTION time (a menu-legality filter,
#   MOVE_LIMITATION_CANT_USE_TWICE) — this project has no such menu-filter
#   architecture, so it's implemented at execution time instead, matching the
#   exact fail-at-execution shape Assault Vest/Disable already established
#   (see move_data.gd's own `blocked_by_aroma_veil` doc comment for that
#   precedent's fuller citation).
# Source: src/data/moves_info.h MOVE_BLOOD_MOON: .effect = EFFECT_HIT,
#   .power = 140, .type = TYPE_NORMAL, .accuracy = 100, .pp = 5,
#   .cantUseTwice = TRUE — no additionalEffects at all.
# Source: src/battle_util.c L1645 (MOVE_LIMITATION_CANT_USE_TWICE) +
#   include/move.h L144/472 (`cantUseTwice` field/accessor).
@export var cant_use_twice: bool = false

# [M19-rampage] is_rampage: Thrash(37)/Petal Dance(80)/Outrage(200)/Raging
#   Fury(761) — all four share the LITERAL SAME additionalEffects shape
#   (MOVE_EFFECT_THRASH, self=TRUE), confirmed structurally identical from
#   source, no per-move turn-count/behavior difference. On a successful,
#   non-immune hit: locks BattlePokemon.locked_move to this move for a random
#   2-3 turns (rampage_turns) — the mon's action is FORCED to this exact move
#   every turn regardless of what's chosen (BattleManager._phase_move_selection
#   overrides just like charging_move already does for two-turn moves), no
#   menu-legality architecture needed since selection is bypassed entirely.
#   Accuracy is rolled independently each turn — a miss does NOT cancel the
#   lock. When rampage_turns reaches 0, the lock clears and the user is
#   self-confused (CanBeConfused-gated, e.g. blocked by Own Tempo) in the SAME
#   turn's resolution. If a turn's hit is fully unaffected by type immunity,
#   the lock cancels WITHOUT the self-confuse (source: IsBattlerUnaffectedByMove
#   branch) — a real, distinct rule from a miss. Target-faints-mid-rampage
#   needs no special handling: this project's _default_target already
#   re-resolves fresh every turn with no stored target reference, so a
#   replacement is auto-targeted for free, matching source's TARGET_RANDOM
#   shape. Attacker faints/switches mid-lock is already handled for free by
#   the existing _clear_volatiles (clears locked_move/rampage_turns
#   unconditionally, same as charging_move).
# Source: src/data/moves_info.h MOVE_THRASH/MOVE_PETAL_DANCE/MOVE_OUTRAGE/
#   MOVE_RAGING_FURY: .effect = EFFECT_HIT, .target = TARGET_RANDOM,
#   .additionalEffects = ADDITIONAL_EFFECTS({.moveEffect = MOVE_EFFECT_THRASH,
#   .self = TRUE}).
# Source: src/battle_script_commands.c :: case MOVE_EFFECT_THRASH (L2545-2557)
#   — sets volatiles.multipleTurns=TRUE, gLockedMoves[battler]=gCurrentMove,
#   volatiles.rampageTurns=RandomUniform(2, B_RAMPAGE_TURNS).
# Source: src/battle_util.c L390-392 (HandleAction_UseMove) — forces
#   gCurrentMove=gLockedMoves[battler] whenever multipleTurns is set, bypassing
#   any menu choice entirely.
# Source: src/battle_move_resolution.c :: MoveEndRampage (L4152-4181) —
#   decrements rampageTurns each MoveEnd; on reaching 0, CancelMultiTurnMoves
#   then self-confuses via CanBeConfused; on IsBattlerUnaffectedByMove (type
#   immunity), cancels WITHOUT confusing, without waiting for the counter.
@export var is_rampage: bool = false

# [M19-rampage] is_uproar: Uproar(253) — shares the SAME underlying
#   forced-move-repeat lock primitive as is_rampage (locked_move,
#   BattleManager._phase_move_selection's existing override), but a distinct
#   counter (uproar_turns, not rampage_turns) and a genuinely different
#   end-of-lock behavior: NO self-confuse when the lock ends. While
#   uproar_turns > 0 on ANY active battler (either side, field-wide — not just
#   the user's own team), no NEW sleep can be inflicted by any means (Rest
#   included, since both route through the same non-volatile-status-setting
#   gate) — confirmed field-wide via UproarWakeUpCheck's `i < gBattlersCount`
#   scan across ALL battlers, not just the Uproar user's side. Does NOT wake
#   already-sleeping mons at this project's Gen5+ config (B_UPROAR_TURNS/
#   B_UPROAR default GEN_LATEST) — that "wake sleepers every turn" half is
#   explicitly pre-Gen5-only in source and dead code at this config.
# Source: src/data/moves_info.h MOVE_UPROAR: .effect = EFFECT_HIT,
#   .target = TARGET_RANDOM, .soundMove = TRUE,
#   .additionalEffects = ADDITIONAL_EFFECTS({.moveEffect = MOVE_EFFECT_UPROAR,
#   .self = TRUE}).
# Source: src/battle_script_commands.c :: case MOVE_EFFECT_UPROAR
#   (L2399-2410) — sets volatiles.multipleTurns=TRUE,
#   gLockedMoves[battler]=gCurrentMove, volatiles.uproarTurns = 3 at
#   B_UPROAR_TURNS>=GEN_5 (this project's config), else RandomUniform(2,5).
# Source: src/battle_end_turn.c L1279-1324 (THIRD_EVENT_BLOCK_UPROAR) —
#   decrements uproarTurns each end of turn; the pre-Gen5-only sleeper-wake
#   loop `break`s immediately at GEN_5+ config (L1284); no self-confuse
#   anywhere in this dispatch, unlike rampage's MoveEndRampage.
# Source: src/battle_util.c L5306-5314 (CanSetNonVolatileStatus,
#   case MOVE_EFFECT_SLEEP) :: UproarWakeUpCheck (battle_script_commands.c
#   L7130-7149) — scans `for (i = 0; i < gBattlersCount; i++)`, field-wide,
#   blocking new-sleep infliction on ANY battler while ANY battler has
#   uproarTurns active.
@export var is_uproar: bool = false

# [M19-recharge] is_recharge: Hyper Beam(63)/Blast Burn(307)/Hydro
#   Cannon(308)/Frenzy Plant(338)/Giga Impact(416)/Rock Wrecker(439)/Roar of
#   Time(459)/Prismatic Laser(665)/Meteor Assault(722)/Eternabeam(723) — all
#   ten share the identical `MOVE_EFFECT_RECHARGE` additionalEffect
#   (`self=TRUE`), but power/accuracy/pp/type/category are NOT uniform
#   (confirmed individually, not assumed — see gen_moves.py's own per-move
#   citations). A genuinely DIFFERENT mechanism shape from is_rampage/
#   is_uproar despite the surface "can't act" similarity: this is a PRE-MOVE
#   canceler (source: `CancelerRecharge`, checked BEFORE sleep/freeze/Truant
#   in the canceler chain), not a forced-move-repeat lock — there is no move
#   to force, the Pokémon does nothing at all on the recharge turn. On a
#   successful, non-immune hit (damage > 0 — mirroring the existing Rage/
#   Sparkling Aria "damage > 0"-gated guaranteed-self-effect insertion
#   point): sets `BattlePokemon.must_recharge = true`. The NEXT time this
#   Pokémon would act, `StatusManager.pre_move_check` blocks the action
#   entirely (no move selection, no PP cost) and clears the flag — a single
#   boolean reproduces source's literal `rechargeTimer=2`/decrement-twice
#   shape exactly, since the observable behavior is just "block exactly the
#   next turn, then clear."
#   A MISS does NOT set the lock — confirmed from source, NOT assumed: none
#   of these 10 moves set `.preAttackEffect = TRUE` on their additionalEffect
#   (checked individually — Prismatic Laser's own block was double-checked
#   against a false line-number match into the NEXT move, Spectral Thief,
#   which DOES set it), so the effect dispatches ONLY via
#   `Cmd_setadditionaleffects`, itself only reachable via the successful-hit
#   script path (`BattleScript_Hit_RetFromAtkAnimation`) — a miss branches
#   straight to `BattleScript_MoveMissed`/`BattleScript_MoveEnd`, never
#   reaching it. This is the OPPOSITE of the commonly-assumed "recharges
#   even on a miss" folklore — this project follows the reference source,
#   not the folklore, per CLAUDE.md's own ground-truth rule. Confirmed via
#   `AskUserQuestion` before implementing.
#   Switch-out/faint clears the pending recharge for free: source's
#   `SwitchInClearSetData`/`FaintClearSetData` both bulk-`memset` the whole
#   `Volatiles` struct `rechargeTimer` lives in — mirrored here by
#   `BattleManager._clear_volatiles` clearing `must_recharge` unconditionally,
#   same as every other switch/faint-cleared volatile.
# Source: src/data/moves_info.h (all 10 moves' own blocks, individually
#   verified — see gen_moves.py for exact per-move power/accuracy/pp/type/
#   category/flag citations).
# Source: src/battle_script_commands.c :: case MOVE_EFFECT_RECHARGE
#   (L2506-2513) — `volatiles.rechargeTimer = 2`, `gLockedMoves[battler] =
#   gCurrentMove` (source detail: sets a locked move purely for message/
#   context purposes since the canceler aborts before any real re-execution
#   — this project's `must_recharge` boolean has no equivalent need since it
#   never re-selects a move at all).
# Source: src/battle_move_resolution.c :: CancelerRecharge (L87-96) — the
#   pre-move canceler; `sMoveSuccessOrderCancelers` (L2397-2402) confirms
#   `CANCELER_RECHARGE` runs BEFORE `CANCELER_ASLEEP_OR_FROZEN`/
#   `CANCELER_TRUANT` in the real canceler chain — mirrored here by checking
#   `must_recharge` first in `StatusManager.pre_move_check`, before Sleep.
# Source: src/battle_main.c L5041-5042 (`TurnValuesCleanUp`) — the actual
#   per-turn decrement of `rechargeTimer`; L3145/L3272
#   (`SwitchInClearSetData`/`FaintClearSetData`) — the bulk-memset switch/
#   faint clear cited above.
@export var is_recharge: bool = false

# is_pain_split: Pain Split — averages the user's and target's CURRENT HP (not max HP) and
#   sets both to that average: `hpDiff = (attackerHP + targetHP) / 2` (integer division,
#   floor). Can heal the user and damage the target, or the reverse, depending on which
#   started higher. Cannot faint either side (floor average of two positive HP totals is
#   always >= 1). Blocked by the target's Substitute (no ignoresSubstitute flag in source).
# Source: src/data/moves_info.h MOVE_PAIN_SPLIT: .effect = EFFECT_PAIN_SPLIT, .power = 0,
#   .type = TYPE_NORMAL, .accuracy = 0, .pp = 20, .target = TARGET_SELECTED.
# Source: src/battle_script_commands.c :: Cmd_painsplitdmgcalc (L7989-8006):
#   `hpDiff = (gBattleMons[gBattlerAttacker].hp + GetNonDynamaxHP(gBattlerTarget)) / 2;`
#   fails via DoesSubstituteBlockMove check before computing hpDiff.
# Source: src/battle_script_commands.c :: PassiveDataHpUpdate (L1547-1562): negative
#   passiveHpUpdate = heal (clamped to maxHP); positive = damage (clamped at 0, never negative).
@export var is_pain_split: bool = false

# is_conversion: Conversion — changes the user's type to match the type of their FIRST
#   populated move slot (literally moves[0] in scan order — no special-casing of
#   Curse/Struggle/status moves in source). Fails if the user is already that exact type
#   (checked against ALL of the user's current types, so a dual-type user with either type
#   matching still fails). On success the user becomes MONO-typed as that single type
#   (both type slots set to the same value) — not "add a type," a full replacement.
# Source: src/data/moves_info.h MOVE_CONVERSION: .effect = EFFECT_CONVERSION, .power = 0,
#   .type = TYPE_NORMAL, .accuracy = 0, .pp = 30, .target = TARGET_USER,
#   .ignoresProtect = TRUE.
# Source: src/battle_script_commands.c :: Cmd_tryconversiontypechange (L7449-7482),
#   B_UPDATED_CONVERSION >= GEN_6 branch (GEN_LATEST): scans moves[0..3] for the first
#   non-MOVE_NONE slot; IS_BATTLER_OF_TYPE guards against a no-op change; SET_BATTLER_TYPE
#   (include/battle.h L797) sets both type slots to the new type (mono-type result).
@export var is_conversion: bool = false

# is_conversion2: Conversion 2 — changes the user's type to one that RESISTS (0x or 0.5x)
#   the type of the TARGET's last successfully used move (TARGET_SELECTED in Gen5+ — the
#   move's chosen target, reusing this project's existing `last_move_used` field; NOT a
#   "last hit the user" tracker, despite the move's flavor text — that was the pre-Gen5
#   behavior). Fails if the target has no last_move_used, or that move's type is
#   TYPE_NONE/TYPE_MYSTERY/TYPE_STELLAR, or every resisting type is one the user already
#   has. Selection among multiple valid resisting types is UNIFORM RANDOM (not "first
#   found") — source rejection-samples a random type id, discarding ones the user already
#   has. Ignores Protect and Substitute (both explicit flags in source).
# Source: src/data/moves_info.h MOVE_CONVERSION_2: .effect = EFFECT_CONVERSION_2,
#   .power = 0, .type = TYPE_NORMAL, .accuracy = 0, .pp = 30,
#   .target = B_UPDATED_MOVE_DATA >= GEN_5 ? TARGET_SELECTED : TARGET_USER,
#   .ignoresProtect = TRUE, .ignoresSubstitute = B_UPDATED_MOVE_FLAGS >= GEN_5 (GEN_LATEST).
# Source: include/config/battle.h L73 — B_UPDATED_CONVERSION_2 = GEN_LATEST (>= GEN_5):
#   "changes the user's type to a type that resists the last move used by the selected
#   target" (legacy pre-Gen5 used "last move being successfully hit by" instead).
# Source: src/battle_script_commands.c :: Cmd_settypetorandomresistance (L8009-8077):
#   GEN_LATEST branch reads `moveToCheck = gLastResultingMoves[gBattlerTarget]` /
#   `typeToCheck = gLastUsedMoveType[gBattlerTarget]`; builds a resistTypes bitmask via
#   GetTypeModifier == UQ_4_12(0) or UQ_4_12(0.5); loops `Random() % NUMBER_OF_MON_TYPES`
#   discarding already-had types until one is found or the mask empties.
@export var is_conversion2: bool = false

# is_psych_up: Psych Up — copies the TARGET's current 7 stat stages onto the user
#   (overwrites the user's own stages entirely, including negative stages). ALSO copies
#   the target's Focus Energy crit-boost volatile (Gen6+: B_PSYCH_UP_CRIT_RATIO >=
#   GEN_6 = GEN_LATEST) — NOT just the 7 numeric stages, confirmed from source rather than
#   assumed. (Source also copies Dragon Cheer / bonusCritStages volatiles that this project
#   does not implement — out of scope, no-op.) Always hits (accuracy=0) and ignores both
#   Protect and Substitute (explicit flags in source).
# Source: src/data/moves_info.h MOVE_PSYCH_UP: .effect = EFFECT_PSYCH_UP, .power = 0,
#   .type = TYPE_NORMAL, .accuracy = 0, .pp = 10, .target = TARGET_SELECTED,
#   .ignoresProtect = TRUE, .ignoresSubstitute = TRUE.
# Source: src/battle_script_commands.c :: Cmd_copyfoestats (L8555-8575): copies all
#   NUM_BATTLE_STATS statStages; then, gated on B_PSYCH_UP_CRIT_RATIO >= GEN_6, also copies
#   volatiles.focusEnergy (+ dragonCheer/bonusCritStages, unimplemented here).
# Source: include/config/battle.h L97 — B_PSYCH_UP_CRIT_RATIO = GEN_LATEST.
@export var is_psych_up: bool = false

# [M19-break-protect] breaks_protect: Feint(364)/Shadow Force(467)/Phantom
#   Force(566)/Hyperspace Hole(593) — all 4 share the identical
#   MOVE_EFFECT_FEINT additionalEffect in source, confirmed NOT Feint-specific
#   despite the move's own name (Shadow Force/Phantom Force/Hyperspace Hole
#   all carry the literal same effect token). This is a GENUINELY DIFFERENT,
#   ADDITIONAL mechanic from `ignores_protect` above — the two are easy to
#   conflate but source keeps them structurally separate:
#   - `ignoresProtect`/this project's `ignores_protect` only lets THIS move's
#     own hit bypass an already-up Protect check (battle_manager.gd's
#     `defender.protect_active and not move.ignores_protect` gate). It does
#     NOT touch `protect_active` itself.
#   - `breaks_protect` (MOVE_EFFECT_FEINT) is a separate POST-HIT mutation:
#     it clears the target's Protect state outright, so a DIFFERENT
#     attacker's move (in doubles) — or the same target's own next use —
#     is no longer blocked either. All 4 moves set BOTH flags: ignores so
#     their own hit connects, breaks so the Protect state doesn't survive.
# Source: src/battle_script_commands.c :: case MOVE_EFFECT_FEINT (L2584-2606):
#   `if (gProtectStructs[effectBattler].protected != PROTECT_NONE &&
#   != PROTECT_MAX_GUARD) { protected = PROTECT_NONE;
#   volatiles.consecutiveMoveUses = 0; }` — this project's analog is
#   `defender.protect_active = false; defender.protect_consecutive = 0`
#   (protect_consecutive is the exact existing field
#   `_roll_protect_success` already reads for the Gen5+ 1/3^n fail-chance
#   ramp, so resetting it here correctly un-ramps a broken Protect streak).
#   Source ALSO clears a side-wide Protect (Wide Guard/Quick Guard/Crafty
#   Shield, `PROTECT_TYPE_SIDE`) on the target's ally — this project has NO
#   side-wide protect moves implemented at all, so that half of source's
#   logic has nothing to act on and is not modeled; single-target scope only.
#   No move-specific exemption exists for King's Shield/Spiky
#   Shield/Baneful Bunker/Obstruct/Silk Trap/Crafty Shield either — none of
#   those are implemented in this project (only Protect/Detect, both plain
#   `is_protect`), so the "does this bypass ALL Protect-family moves
#   uniformly" question is moot for now; the check above already covers any
#   individual protect type except PROTECT_MAX_GUARD (unimplemented here).
# POST-HIT ONLY, confirmed: none of the 4 moves set `.preAttackEffect`
#   (unlike this project's own `[M19-recharge]` precedent for the same
#   distinction — see is_recharge's own doc comment), so MOVE_EFFECT_FEINT
#   dispatches via the post-hit-only `Cmd_setadditionaleffects` path — a
#   MISS does not break Protect. Gated here on `damage > 0`, matching
#   `[M19-recharge]`'s established `if damage > 0 and move.X:` convention in
#   `_do_damaging_hit`.
@export var breaks_protect: bool = false

# M17n-9: Magic Bounce — true for the exact subset of this project's foe-targeting
# status moves that carry `magicCoatAffected = TRUE` in source
# (`gMovesInfo[move].magicCoatAffected`, include/move.h L350-352). Re-derived
# per-move from source rather than assumed for "every status move" — see
# AbilityManager.bounces_status_move's doc comment for the full reasoning and the
# confirmed-excluded moves (Encore, Disable, Psych Up, Conversion/Conversion 2,
# Pain Split, Trick Room, self-targeting stat moves).
@export var bounceable: bool = false

# [M19-recoil-on-miss] crashes_on_miss: Jump Kick(26)/High Jump Kick(136)/Axe
#   Kick(781)/Supercell Slam(844) — all 4 share the literal same
#   `.effect = EFFECT_RECOIL_IF_MISS` in source, a genuinely uniform mechanism
#   (contrary to the possibility that the two newer-gen moves, Axe Kick/
#   Supercell Slam, might use a different formula — they don't).
# Formula, confirmed at this project's GEN_LATEST config
#   (`B_RECOIL_IF_MISS_DMG = GEN_LATEST`, `B_CRASH_IF_TARGET_IMMUNE =
#   GEN_LATEST`): a FLAT 50% of the ATTACKER'S OWN max HP — NOT damage-scaled,
#   NOT the target's HP. Source (battle_move_resolution.c ::
#   MoveEndMoveBlockRecoil, case EFFECT_RECOIL_IF_MISS, L3339-3372):
#     if (B_RECOIL_IF_MISS_DMG >= GEN_5) recoil = GetNonDynamaxMaxHP(battlerAtk) / 2;
#   The OTHER, older branch (`B_CRASH_IF_TARGET_IMMUNE == GEN_4`, defender's own
#   HP/2) is a literal `== GEN_4` equality check — never true at this project's
#   GEN_LATEST config, so it's dead code here; the GEN5+ branch below it always
#   wins and OVERWRITES `recoil` unconditionally regardless of which branch(es)
#   evaluated, since it's a separate `if`, not an `else if`.
# MISS-SCOPE, confirmed broader than "accuracy roll failed" alone: the entry
#   gate is `IsBattlerAlive(battlerAtk) && IsBattlerUnaffectedByMove(battlerDef)
#   && !unableToUseMove`. `IsBattlerUnaffectedByMove` checks
#   `MOVE_RESULT_NO_EFFECT = MOVE_RESULT_MISSED | MOVE_RESULT_FAILED |
#   MOVE_RESULT_PROTECTED | MOVE_RESULT_DOESNT_AFFECT_FOE` (include/constants/
#   battle.h L471) — i.e. crash triggers uniformly for an accuracy-roll miss,
#   a Protect block, OR ordinary type immunity, not just the first of these.
#   `!unableToUseMove` is the critical EXCLUSION: `unableToUseMove` is set
#   whenever ANY pre-move canceler fails (sleep/freeze/paralysis/confusion
#   self-hit/flinch/recharge/Truant/Disable/0 PP/obedience-loafing) — i.e. the
#   attacker never got to actually ATTEMPT the move at all. Crash damage never
#   fires in those cases; this project's `StatusManager.pre_move_check` already
#   gates all of those BEFORE move resolution ever reaches this project's own
#   crash-dispatch points, so nothing extra needs excluding here.
# ABILITY INTERACTION — a real, confirmed ASYMMETRY with ordinary recoil, not
#   assumed symmetric: Magic Guard blocks crash damage
#   (`data/battle_scripts_1.s` :: BattleScript_RecoilIfMiss — `jumpifability
#   BS_ATTACKER, ABILITY_MAGIC_GUARD, BattleScript_RecoilEnd`), but ROCK HEAD
#   DOES NOT — Rock Head is never checked anywhere in this script or in
#   `MoveEndMoveBlockRecoil`'s `EFFECT_RECOIL_IF_MISS` case (unlike ordinary
#   `EFFECT_RECOIL`/`EFFECT_CHLOROBLAST`, whose case block explicitly checks
#   `ABILITY_ROCK_HEAD || ABILITY_MAGIC_GUARD` a few lines below). This project
#   reuses `AbilityManager.blocks_indirect_damage` (Magic-Guard-only) for crash
#   damage, deliberately NOT `blocks_recoil` (Rock-Head-OR-Magic-Guard), to
#   preserve this exact asymmetry.
# Can faint the user: confirmed from source (`tryfaintmon BS_ATTACKER`
#   immediately follows the HP update in `BattleScript_RecoilIfMiss`) — this
#   project's existing FAINT_CHECK phase (which runs generically after every
#   resolved action) already handles this correctly with no special code.
# Gravity: `.gravityBanned = TRUE` on all 4 moves in source, but Gravity/
#   Ingrain/Smack Down/Telekinesis/Magnet Rise are all confirmed absent from
#   this project (`[M18t]`'s own doc comment) — nothing to build, out of scope.
# Also found (a related, unrequested but directly-adjacent finding): Reckless's
#   own power-boost check already anticipated this exact addition — see
#   AbilityManager.move_power_modifier_uq412's own doc comment, updated
#   alongside this field.
@export var crashes_on_miss: bool = false

# [M19-weather-conditional-accuracy] always_hits_in_rain: Thunder(87)/
#   Hurricane(542)/Bleakwind Storm(774)/Wildbolt Storm(775)/Sandsear
#   Storm(776) — ALL 5 share this flag, a FULL BYPASS of the entire
#   accuracy-modifier chain while it's raining (source's own
#   `.alwaysHitsInRain = TRUE`), gated on the ATTACKER's own effective
#   weather (Air Lock/Cloud Nine AND the attacker's own Utility Umbrella
#   both negate it — see StatusManager.check_accuracy's own citation).
# Source: src/include/move.h L145 (`alwaysHitsInRain:1`); dispatch via
#   `CanMoveSkipAccuracyCalc` (battle_util.c L10168-10199) — the SAME
#   early-exit "does this move skip the roll entirely" chain No Guard and
#   accuracy==0 already live in, not a modifier on top of the normal roll.
@export var always_hits_in_rain: bool = false

# [M19-weather-conditional-accuracy] accuracy_halved_in_sun: Thunder(87) and
#   Hurricane(542) ONLY — confirmed a genuinely SEPARATE, second flag from
#   always_hits_in_rain above, NOT shared by the "Storm" trio (Bleakwind/
#   Wildbolt/Sandsear all have `alwaysHitsInRain` but explicitly NO
#   `accuracy50InSun` in source — verified individually, not assumed
#   symmetric). A literal OVERRIDE of the move's own accuracy stat to a
#   FLAT 50 (source: `moveAcc = 50;`, NOT `moveAcc *= 0.5` — Thunder's own
#   base accuracy is 70, so this isn't literally "half"), applied BEFORE
#   the stage-ratio multiplication — the exact same insertion point
#   `[M17n-11]`'s Wonder Skin already established, so every other
#   accuracy-boosting ability/stat stage still applies on top of the
#   overridden value afterward, unaffected. Gated on the ATTACKER's own
#   effective weather, same Air-Lock/Cloud-Nine/Utility-Umbrella scope as
#   always_hits_in_rain above.
# Source: src/include/move.h L146 (`accuracy50InSun:1`); dispatch via
#   `GetTotalAccuracy` (battle_util.c L10271-10276), checked BEFORE Wonder
#   Skin's own floor-to-50 a few lines below it (mutually exclusive in
#   practice — Wonder Skin only ever gates STATUS moves, Thunder/Hurricane
#   are both damaging — but the relative order is preserved for fidelity).
@export var accuracy_halved_in_sun: bool = false

# [M19-steal-stats] steals_positive_stat_stages: Spectral Thief(666) —
#   steals the target's CURRENTLY positive stat stages onto the attacker,
#   removing them from the target, for ALL 7 stages (confirmed via
#   `NUM_BATTLE_STATS = NUM_STATS + 2`, includes Accuracy/Evasion, unlike
#   Starf Berry's narrower 5-stat pool). A genuinely DIFFERENT shape from
#   `AbilityManager`'s Opportunist (reacts to a fresh stat-RISE EVENT
#   elsewhere; Spectral Thief instead snapshots-and-transfers whatever
#   already exists at the moment of use) — see BattleManager's own call
#   site doc comment for the full citation, including the `.preAttackEffect
#   = TRUE` timing (fires regardless of this move's own subsequent
#   accuracy result — blocked only by Protect and type immunity, both
#   already-resolved by the time a pre-attack effect dispatches).
# Source: src/data/moves_info.h MOVE_SPECTRAL_THIEF: additionalEffects
#   {MOVE_EFFECT_STEAL_STATS, .preAttackEffect = TRUE}, .ignoresSubstitute
#   = TRUE (moot here — the steal is dispatched before any substitute-
#   redirect check could apply, matching Brick Break's own preAttackEffect
#   precedent, `move_data.gd`'s `breaks_screens` field, above).
@export var steals_positive_stat_stages: bool = false

# [M19-ally-targeting-stat-change] stat_change_target_ally: Aromatic
#   Mist(597)/Coaching(739) — TARGET_ALLY ONLY (never self, never
#   opponent). A real, source-confirmed OVERTURN of this sub-group's own
#   original framing ("no ally-targeting stat-change mechanism exists in
#   any form") — this project already had exactly such a mechanism, via
#   Helping Hand's own established `TARGET_ALLY`/"fails if not doubles"
#   dispatch shape (`[M14b]`), just not yet reused for a second move. See
#   BattleManager's own call site doc comment for the full citation.
# Source: moves_info.h MOVE_AROMATIC_MIST/MOVE_COACHING: .target = TARGET_ALLY.
@export var stat_change_target_ally: bool = false

# [M19-ally-targeting-stat-change] also_boosts_ally: Howl(336) ONLY —
#   TARGET_USER_AND_ALLY at this project's GEN_LATEST config
#   (`B_UPDATED_MOVE_DATA >= GEN_8`). The self half is an ordinary
#   self-buff (already fully supported by the pre-existing
#   `stat_change_self` field); this flag bolts the SAME stat change onto
#   the user's own ally too — a no-op in singles, the only difference
#   from a plain self-buff move in doubles.
@export var also_boosts_ally: bool = false

# [M19e] heals_based_on_weather: Morning Sun(234)/Synthesis(235)/
#   Moonlight(236)/Shore Up(622) — heal a fraction of max HP that varies
#   with the attacker's own effective weather. Shares one dispatch shape
#   with `is_restore_hp` (fails if already at full HP) but a DIFFERENT
#   fraction depending on `weather_heal_boost_type`/
#   `weather_heal_has_quarter_branch` below. Source: all 4 moves route
#   through the SAME shared function, `Cmd_recoverbasedonsunlight`
#   (battle_script_commands.c L8622-8689) — confirmed via direct read, not
#   assumed from the 4 separate `EFFECT_MORNING_SUN`/`EFFECT_SYNTHESIS`/
#   `EFFECT_MOONLIGHT`/`EFFECT_SHORE_UP` move-data effect IDs, which are
#   distinct per-move but converge to one real implementation.
@export var heals_based_on_weather: bool = false

# [M19e] weather_heal_boost_type: the DamageCalculator.WEATHER_* value that
#   triggers this move's 2/3-max-HP boosted heal — WEATHER_SUN for Morning
#   Sun/Synthesis/Moonlight, WEATHER_SANDSTORM for Shore Up (its own
#   sandstorm-specific bonus, a real difference from the other 3's shared
#   sun-based formula, confirmed individually from source rather than
#   assumed uniform).
@export var weather_heal_boost_type: int = 0

# [M19e] weather_heal_has_quarter_branch: TRUE for Morning Sun/Synthesis/
#   Moonlight (a THIRD fraction — max HP/4 — applies in any weather OTHER
#   than the boost weather); FALSE for Shore Up, which has only two states
#   (Sandstorm: 2/3; anything else including no weather: 1/2 — confirmed
#   via source that Shore Up's own branch never references the 1/4 case at
#   all, a genuine non-uniformity within this 4-move sub-group). When TRUE,
#   Strong Winds (Delta Stream) is treated as "no weather" (the 1/2 case),
#   NOT the 1/4 "other weather" case — source: `healingWeather =
#   attackerWeather & ~B_WEATHER_STRONG_WINDS`, stripped before the
#   "!(healingWeather & ANY)" check. Utility Umbrella (checked via
#   `ItemManager.blocks_weather_modifier`) strips SUN/RAIN specifically for
#   these 3 moves (treating either as "no weather"), but does NOT strip
#   Sandstorm/Hail — those still correctly fall into the 1/4 branch even
#   for an Umbrella holder. Shore Up's own branch never references Umbrella
#   at all (source only checks the raw Sandstorm bit directly), so Umbrella
#   has zero effect on Shore Up's formula.
@export var weather_heal_has_quarter_branch: bool = false

# [M19f] is_mean_look: Spider Web(169)/Mean Look(212)/Block(335) — sets
#   `BattlePokemon.escape_prevented_by` on the target, preventing its
#   voluntary switching (via `AbilityManager.is_trapped()`, which already
#   anticipated this exact move-based volatile in its own doc comment,
#   written back at `[M17f]`/`[M18.5f]`). Source: EFFECT_MEAN_LOOK's shared
#   script (`BattleScript_EffectMeanLook`, data/battle_scripts_1.s
#   L2100-2112) — `seteffectprimary ... MOVE_EFFECT_PREVENT_ESCAPE`, the
#   SAME underlying effect Spirit Shackle(625) sets as a damaging move's
#   secondary (see `SE_PREVENT_ESCAPE` above). Fails outright (not a silent
#   no-op) if the target is already escape-prevented, blocked by
#   Substitute, or — at this project's GEN_LATEST config
#   (`B_UPDATED_MOVE_FLAGS`/`B_GHOSTS_ESCAPE >= GEN_6`) — Ghost-type. This
#   Ghost-type check is a MOVE-SCRIPT-level immunity, NOT the general
#   type-effectiveness gate: Mean Look/Block are Normal-type (already 0x
#   vs Ghost on the type chart, so the general gate would catch them for
#   free), but Spider Web is Bug-type, which is only NOT-VERY-EFFECTIVE
#   (0.5x, not a 0x immunity) against Ghost — meaning Spider Web genuinely
#   needs this EXPLICIT check to match source, a real asymmetry the
#   type chart alone would miss. `bounceable = TRUE` on all 3 (source's
#   `magicCoatAffected = TRUE`) — reflected by Magic Bounce like any other
#   bounceable status move. A real, source-confirmed asymmetry WITHIN this
#   3-move family: Spider Web's own `ignoresProtect` is FALSE at
#   GEN_LATEST (only true pre-Gen-3), while Mean Look's and Block's are
#   both TRUE at GEN_LATEST (`>= GEN_6`) — confirmed individually per move,
#   not assumed uniform just because they share one effect ID.
@export var is_mean_look: bool = false

# [D0] is_leech_seed: Leech Seed(73) — plants a per-battler seeder-reference
#   (`BattlePokemon.leeched_by`) on the target, draining maxHP/8 from the
#   seeded battler to the seeder every end of turn. Grass-type immune,
#   checked at APPLY time via a dedicated move-script-level check (NOT the
#   general type-effectiveness gate — Grass-type moves are not generally
#   immune to Grass-type targets on the type chart; this is Leech Seed's own
#   bespoke rule), fails outright if already seeded. Source:
#   `Cmd_setseeded` (battle_script_commands.c L7061-7080):
#   `IS_BATTLER_OF_TYPE(target, TYPE_GRASS)` → fail; already
#   `volatiles.leechSeed` → miss; else `volatiles.leechSeed =
#   LEECHSEEDED_BY(attacker)`. Blocked by Substitute (`jumpifsubstituteblocks`
#   in `BattleScript_EffectLeechSeed`), `bounceable = TRUE`
#   (`magicCoatAffected = TRUE` in source). The end-of-turn drain itself
#   (`HandleEndTurnLeechSeed`, battle_end_turn.c L476-509) reuses TWO
#   already-implemented item/ability functions with zero changes:
#   `ItemManager.big_root_drain_heal` (a real correction to `[M18q]`'s own
#   "move-drain only" scope note — source's own `HandleEndTurnLeechSeed`
#   calls the SAME `GetDrainedBigRootHp` Giga Drain uses, confirming Big
#   Root's TRUE scope always included Leech Seed; `[M18q]` simply hadn't
#   built Leech Seed yet) and `AbilityManager.inverts_drain` (Liquid Ooze,
#   checked on the SEEDED battler — if it has Liquid Ooze, the SEEDER takes
#   damage instead of healing, the same "drained mon's own ability inverts
#   the drainer's heal" shape Giga Drain's own Liquid-Ooze check already
#   established). Magic Guard on the SEEDED battler blocks the entire tick
#   (checked on `battler`, i.e. the seeded mon, in source — reuses
#   `AbilityManager.blocks_indirect_damage`). Heal Block's own exclusion
#   branch is permanently moot (Heal Block is unimplemented/excluded).
@export var is_leech_seed: bool = false

# [D0] is_haze: Haze(114) — resets ALL 7 stat stages to exactly 0 for EVERY
#   battler currently on the field (both sides, doubles-aware), not just one
#   target — confirmed from source, NOT a single-target reset. Reuses Clear
#   Smog's own `is_clear_smog` reset primitive verbatim, just looped over
#   every live combatant instead of one. Source: `Cmd_normalisebuffs`
#   (battle_script_commands.c L7217-7224): `for (i = 0; i < gBattlersCount;
#   i++) TryResetBattlerStatChanges(i)` — the real primary dispatch for
#   Haze(114)'s own `BattleScript_EffectHaze`. A separate `MOVE_EFFECT_HAZE`
#   case exists in the additionalEffects switch (for a hypothetical move
#   using Haze's effect as a SECONDARY — Freezy Frost(686), see
#   `is_haze_on_hit` below) and calls the identical
#   `TryResetBattlerStatChanges` loop, confirming both dispatch paths are
#   the same underlying mechanism.
@export var is_haze: bool = false

# [D0] is_heal_bell: Heal Bell(215)/Aromatherapy(312) — cures every real
#   status1 condition for the ATTACKER'S ENTIRE PARTY (bench included, not
#   just the active battler), via `BattleParty.members`' own per-mon
#   `.status` field — confirmed sufficient with ZERO extension needed
#   (every bench `BattlePokemon` already holds a live `.status` field).
#   Source: `Cmd_healpartystatus` (battle_script_commands.c L8259-8340).
#   A REAL, confirmed asymmetry at this project's GEN_LATEST config
#   (`B_HEAL_BELL_SOUNDPROOF >= GEN_8`, "in Gen9 it always affects the
#   user"): the ATTACKER ITSELF and every OTHER party member (bench mons)
#   are cured UNCONDITIONALLY, bypassing Soundproof entirely — but the
#   ATTACKER'S DOUBLES PARTNER specifically remains gated by ITS OWN
#   Soundproof (only relevant for Heal Bell, a `sound_move`; Aromatherapy
#   is not a sound move, so this never blocks Aromatherapy). Confirmed via
#   direct read of `Cmd_healpartystatus`'s own 3-branch conditional (attacker
#   branch has an unconditional `>= GEN_8` OR; partner branch has no such
#   OR; the full-party loop's `ability = ABILITY_NONE` branch fires for
#   every non-attacker/non-partner slot at this config) — NOT assumed
#   uniform just because both moves share one effect. `is_sound_move` (the
#   pre-existing `sound_move` field) distinguishes the two.
@export var is_heal_bell: bool = false

# [D0] is_haze_on_hit / is_leech_seed_on_hit / is_heal_bell_on_hit: Freezy
#   Frost(686)/Sappy Seed(685)/Sparkly Swirl(687) — the 3 moves Bucket 4's
#   `M19-blocked-on-other-tier4` sub-group was gated on, now unblocked.
#   All 3 are plain `EFFECT_HIT` damage moves with a GUARANTEED (no
#   `.chance` field — a true primary-shaped secondary, Shield-Dust/Sheer-
#   Force/Serene-Grace-EXEMPT) additional effect reusing the 3 primitives
#   above VERBATIM — the identical "duplicate-and-substitute-free, dispatch
#   unconditional on damage > 0" shape `[Bucket 3 clusters 1-2]` already
#   established for Glitzy Glow/Baddy Bad's on-hit screens. Source:
#   Sappy Seed's `MOVE_EFFECT_LEECH_SEED` case (battle_script_commands.c
#   L2868-2874, same Grass-immune/already-seeded gate as the primary);
#   Freezy Frost's `MOVE_EFFECT_HAZE` case (L2861-2865, identical
#   `TryResetBattlerStatChanges` loop over every battler — confirmed the
#   damage ALSO resets the ATTACKER'S OWN stats, not just the target's);
#   Sparkly Swirl's `MOVE_EFFECT_AROMATHERAPY` case (L3259-3261, dispatches
#   the SAME `Cmd_healpartystatus`, which always operates on
#   `GetBattlerParty(gBattlerAttacker)` regardless of the `.self = TRUE`
#   flag on Sparkly Swirl's own data — heals the ATTACKER'S OWN party, even
#   though the move deals damage to an opponent).
@export var is_leech_seed_on_hit: bool = false
@export var is_haze_on_hit: bool = false
@export var is_heal_bell_on_hit: bool = false

# [D1] is_solar_beam is reused directly for Solar Blade(632) — see that
#   field's own doc comment. No new MoveData field needed; `category:
#   PHYS` on Solar Blade's own data entry (vs. Solar Beam's SPEC) is
#   sufficient, since the charge-turn-skip dispatch never reads category.
#   FLAGGED, not fixed this session: source's `EFFECT_SOLAR_BEAM` also
#   halves damage in rain/sand/hail/fog (`battle_util.c` L6177-6181,
#   `GetAttackerWeather`-gated) — this project's existing Solar Beam(76)
#   never implemented that half (only the charge-skip), so Solar Blade
#   ships with the SAME incomplete-but-consistent behavior rather than
#   expanding this session's scope to fix Solar Beam's own pre-existing
#   gap. A future session should build both halves together.

# [D1] ignores_redirection: Snipe Shot(691) — bypasses BOTH the Follow Me/
#   Rage Powder timer-based redirect AND the Lightning Rod/Storm Drain
#   ability-based redirect, at the SAME single gate this project's
#   existing `AbilityManager.bypasses_redirection` call site already
#   checks (`battle_manager.gd`'s `_phase_move_execution`, the
#   `not move.is_spread and move.power > 0 and not bypasses_redirection(...)`
#   condition guards BOTH nested redirect checks together). Source:
#   `IsAffectedByFollowMe` (battle_move_resolution.c L799-817) returns
#   FALSE for `effect == EFFECT_SNIPE_SHOT` (bypasses Follow Me/Rage
#   Powder) — the SAME early-exclusion list Propeller Tail/Stalwart's own
#   ability check sits in; `HandleMoveTargetRedirection`'s SEPARATE
#   Lightning-Rod/Storm-Drain block (L847-862) ALSO excludes
#   `cv->moveEffect != EFFECT_SNIPE_SHOT` explicitly — a genuinely
#   different source function from Propeller Tail/Stalwart's own bypass,
#   but this project's existing `bypasses_redirection` call site already
#   sits at the ONE chokepoint gating both nested checks, so extending
#   that one function with a move-level OR (rather than needing a second
#   call site) correctly covers both halves for free.
@export var ignores_redirection: bool = false

# [D1] is_hidden_power: Hidden Power(237) — type is IV-derived (6-bit
#   value from the LOW bit of HP/Atk/Def/Speed/SpAtk/SpDef IVs, in THAT
#   bit order — source: `GetDynamicMoveType`'s `EFFECT_HIDDEN_POWER` case,
#   battle_main.c L5851-5869), mapped into the 16 types with
#   `isHiddenPowerType=TRUE` in `types_info.h` (every real type except
#   Normal/Fairy) via `moveType = ((16-1) * typeBits) / 63`. **Power is
#   NOT IV-derived at this project's config**: `B_HIDDEN_POWER_DMG =
#   GEN_LATEST` (>= GEN_6) means the classic bit-parity power formula
#   (battle_util.c L6320-6331) is dead code here — power is a flat 60,
#   recorded directly in Hidden Power's own `.tres` data like any other
#   move, needing zero dispatch of its own. **A real ordering trap,
#   confirmed by directly checking rather than assumed**: source's
#   bit-packing order (HP, Atk, Def, SPEED, SpAtk, SpDef) does NOT match
#   this project's own `BattlePokemon.ivs` array order (HP, Atk, Def,
#   SpAtk, SpDef, SPEED, per `STAT_*` — Speed is LAST here, FOURTH in
#   source) — the same trap already documented for Nature
#   (`[M18.5h-1]`). The dispatch must index `ivs[STAT_SPEED]` explicitly
#   for bit 3, not a raw positional index. **A second real correction**:
#   `AbilityManager.effective_move_type` had no exclusion for Hidden
#   Power (it never needed one before this move existed) — source's own
#   `GetMoveAteType` returns early for `EFFECT_HIDDEN_POWER` before ANY
#   ability check runs (battle_main.c L5738), meaning Normalize/Pixilate/
#   Refrigerate/etc. must NEVER touch Hidden Power's own computed type;
#   `effective_move_type` now checks `move.is_hidden_power` first and
#   returns -1 (no ability-driven override) unconditionally.
@export var is_hidden_power: bool = false

# [D1 cheap clusters] weather_type: Sandstorm(201)/Rain Dance(240)/Sunny
#   Day(241)/Hail(258)/Snowscape(809) — the DamageCalculator.WEATHER_*
#   value this move sets via the existing, fully generic
#   `BattleManager.try_set_weather(weather_type, by_pokemon)` (built for
#   Drizzle/Drought/Sand Stream/Snow Warning, `[M17c]`). Source:
#   `Cmd_setfieldweather` -> `TryChangeBattleWeather(battler,
#   move.argument.weatherType, ABILITY_NONE)` — the SAME function
#   ability-triggered weather-setting already calls, confirming reuse is
#   exact. Snowscape maps to the SAME `WEATHER_HAIL` constant Hail/Snow
#   Warning already use — this project has only one Ice-weather state.
#   [Batch fix, 2026-07-09] CONFIRMED DESIGN DECISION (Rob): this project
#   uses Hail only, no separate Snow mechanic, permanently — real source's
#   genuinely different `BATTLE_WEATHER_SNOW` state (Ice-types +50%
#   Defense, no chip damage, vs. Hail's chip-only/no-boost) will NOT be
#   built. Formerly flagged as an open gap; now a closed scope decision,
#   not a deferred fix. Snow Warning/Snowscape's shared `WEATHER_HAIL`
#   mapping is therefore correct as-is, not a simplification awaiting
#   correction.
#   [Batch fix, 2026-07-09] `try_set_weather`'s Primal-weather block is now
#   built — see that function's own doc comment for the full citation
#   (refuses to overwrite an active Primordial Sea/Desolate Land/Delta
#   Stream unless the new setter is that SAME ability). Formerly flagged
#   as a gap shared by the already-shipped Drizzle/Drought/Sand Stream/
#   Snow Warning abilities; now closed for all of them at once, since the
#   fix lives in the one shared function every weather-setter already
#   calls.
@export var weather_type: int = 0

# [D1 cheap clusters] power_scales_with_user_hp / power_scales_with_target_hp:
#   Eruption(284)/Water Spout(323)/Dragon Energy(748) (user) and Wring
#   Out(378)/Crush Grip(462)/Hard Press(840) (target) — a plain
#   CONTINUOUS linear scale (`basePower = move.power * hp/maxHP`),
#   genuinely simpler than (and distinct from) `is_flail_power`'s
#   stepped/banded formula. No floor-to-1 clamp in source — a
#   very-low-HP user/target can legitimately compute to 0 base power.
#   Source: battle_util.c L6136-6137 (user)/L6192-6193 (target). Reuses
#   the existing `power_override` dispatch mechanism (`[M16b]` Rollout/
#   Magnitude precedent) via a new small static helper each.
@export var power_scales_with_user_hp: bool = false
@export var power_scales_with_target_hp: bool = false

# [D1 cheap clusters] steals_item_if_itemless: Thief(168)/Covet(343) — on
#   a successful hit, steals the target's held item, gated on the
#   ATTACKER currently holding none. Directly reuses `AbilityManager.
#   _try_steal_item` (the exact Pickpocket/Magician primitive, `[M17j]`)
#   verbatim via a new thin wrapper — item-general, NOT berry-specific
#   (a real, confirmed difference from `steals_and_eats_berry`'s Pluck/
#   Bug Bite: no Jaboca/Rowap exemption exists for Thief/Covet in
#   source). Source: battle_move_resolution.c L3487-3499
#   (`CanStealItem`'s own content — trainer-battle-type item-ownership
#   rules and Mega-Stone/species-locked-item checks — confirmed entirely
#   moot for this project, which models neither).
@export var steals_item_if_itemless: bool = false

# [D1 cheap clusters] is_lock_on: Mind Reader(170)/Lock-On(199) — sets a
#   2-tick per-attacker-target "next hit against this target always
#   connects" volatile (`BattlePokemon.sure_hit_target`/`sure_hit_turns`),
#   fails outright if the attacker already has one active (no overwrite).
#   Source: `Cmd_setalwayshitflag` (battle_script_commands.c L8089-8102):
#   `volatiles.lockOn = 2; volatiles.battlerWithSureHit = target+1` if
#   not already set, else fails. Decremented at end of turn
#   (battle_end_turn.c L68-69: `if (lockOn > 0 && --lockOn == 0)
#   battlerWithSureHit = 0`) — cleared after exactly one full extra turn,
#   matching "your NEXT move against this target is guaranteed." Also
#   cleared reciprocally the instant EITHER battler leaves the field
#   (battle_main.c L3131-3132/L3277-3278) — the FIFTH move/ability-based
#   volatile now using this project's established reciprocal-clear
#   shape. Confirmed from source (`CanMoveSkipAccuracyCalc`, battle_util.c
#   L10176) that this bypasses semi-invulnerability TOO, not just the
#   ordinary accuracy roll (a real, documented mechanic — Lock-On lets
#   the following hit connect against a Dug-in/Flying target) — inserted
#   in `StatusManager.check_accuracy` BEFORE the semi-invulnerable check,
#   not merely alongside No Guard.
@export var is_lock_on: bool = false

# [D1 cheap clusters] is_swagger: Swagger(207)/Flatter(260) — raises the
#   TARGET's stat (Swagger: Atk +2; Flatter: SpAtk +1) AND confuses the
#   target, in one move. **NOT a pure composition of the existing raise-
#   stat + try_apply_confusion dispatches**: source's own EFFECT_SWAGGER
#   case (battle_stat_change.c L147-156) checks Own Tempo FIRST, and if
#   present, redirects the ENTIRE move to `BattleScript_OwnTempoPrevents`
#   (a bare fail-message + `goto BattleScript_MoveEnd`, no
#   `trystatchanges` call at all) — Own Tempo blocks the STAT RAISE too,
#   not just the confusion, a real asymmetry a naive independent
#   composition would miss (try_apply_confusion's own Own-Tempo check
#   alone would still let the stat raise through). Implemented as its own
#   explicit early gate before either half. `stat_change_stat`/`amount`
#   reused for the raise (target-directed, `stat_change_self=false`,
#   positive amount — the same shape Decorate/Tearful Look's own foe-
#   targeting raises already use). Accuracy genuinely non-uniform within
#   this pair (Swagger 85 at GEN_7+, Flatter 100) — confirmed
#   individually, not assumed symmetric.
@export var is_swagger: bool = false

# [D1 cheap clusters] is_sucker_punch: Sucker Punch(389)/Thunderclap(837)
#   — fails if the target has already acted this turn, OR if the
#   target's own CHOSEN move is status-category. Directly reuses
#   `[M18j]`'s existing `_has_target_already_acted` turn-position helper
#   (built for Zoom Lens) with zero new tracking — just adds the target's
#   chosen-move-category check. Me First's own exemption
#   (`GetMoveEffect(defMove) != EFFECT_ME_FIRST`) is permanently moot —
#   Me First is unimplemented in this project (confirmed via grep).
#   Source: battle_move_resolution.c L1387-1394.
@export var is_sucker_punch: bool = false

# [D1 cheap clusters] is_stored_power: Stored Power(500)/Power Trip(644)
#   — `basePower = move.power + 20 * sum(positive stat stage MAGNITUDES
#   across all 7 stats, including Accuracy/Evasion)`. A real, easy-to-
#   misread detail confirmed directly from source rather than assumed:
#   `CountBattlerStatIncreases` (battle_util.c L5948-5961) SUMS each
#   positive stage's own magnitude (e.g. Atk+3 contributes 3, not 1), NOT
#   a count of how many distinct stats are raised — and passes
#   `countEvasionAcc=TRUE` for this effect specifically (Punishment's own
#   analogous formula, NOT part of this tier's scope, passes FALSE).
#   Source: battle_util.c L6240-6241. Reuses the existing `power_override`
#   dispatch mechanism via a new small static helper.
@export var is_stored_power: bool = false

# ── D2 batch — on-hit hazard/screen family (Stone Axe/Ceaseless Edge/Ice
# Spinner/Mortal Spin/Tidy Up/Defog) + ability-manipulation family (Role
# Play/Skill Swap/Worry Seed/Heart Swap) + the 3 flagged batch-fix items ──

# sets_stealth_rock_on_hit / sets_spikes_on_hit: Stone Axe(758)/Ceaseless
#   Edge(773) — EFFECT_STONE_AXE/EFFECT_CEASELESS_EDGE, a guaranteed on-hit
#   hazard set on the TARGET's own side (not the attacker's — the opposite
#   side from Bucket 3's Glitzy Glow/Baddy Bad screen-setters, matching
#   ordinary Stealth Rock(446)/Spikes(113)'s own target-side convention).
#   Source: battle_move_resolution.c, case EFFECT_STONE_AXE (L3592-3600)/
#   EFFECT_CEASELESS_EDGE (L3602-3618) — a MoveEnd-dispatch case keyed on
#   the move's own top-level `.effect`, NOT the standard `MOVE_EFFECT_*`/
#   `.chance` secondary-effect mechanism (there is no `.moveEffect` token
#   in either move's own `additionalEffects` block at all — only a bare
#   `.sheerForceOverride = TRUE`). Gated on the hazard not already being
#   maxed (Stealth Rock: not already up; Spikes: <3 layers) AND the hit
#   having actually landed AND the attacker still being alive — reuses the
#   exact layer-cap/set logic Spikes(113)/Stealth Rock(446)'s own pure-
#   status dispatch already has. FLAGGED, not fixed: source's own
#   `sheerForceOverride = TRUE` means Sheer Force should boost these two
#   moves' power even though they carry no true (chance>0) secondary in
#   this project's schema — this project's Sheer Force gate only checks
#   `secondary_chance > 0`, so it will NOT boost Stone Axe/Ceaseless Edge
#   as source does; a real, narrow, pre-existing-shape gap, out of scope
#   for this small hazard tier to fix.
@export var sets_stealth_rock_on_hit: bool = false
@export var sets_spikes_on_hit: bool = false

# Mortal Spin(794): NO new field needed. Confirmed from source to share the
#   LITERAL SAME `.effect = EFFECT_RAPID_SPIN` Rapid Spin(229) itself uses
#   (NOT a separate `EFFECT_MORTAL_SPIN`) — set directly via the existing
#   `is_rapid_spin` flag (clears one hazard from the ATTACKER's own side,
#   `[M16d]`) on Mortal Spin's own `gen_moves.py` entry, applied unmodified.
#   Its own distinguishing feature is a guaranteed 100%-chance Poison
#   secondary on top — reuses the existing generic `secondary_effect =
#   SE_POISON`/`secondary_chance = 100` fields, zero new mechanism. Source:
#   moves_info.h MOVE_MORTAL_SPIN.

# is_defog: Defog(432) — EFFECT_DEFOG, a pure status move (`.category =
#   DAMAGE_CATEGORY_STATUS`) confirmed BROADER than the D2 recon's own
#   framing: clears the TARGET's side's screens (Reflect/Light Screen/
#   Aurora Veil only in this project — source's own Mist/Safeguard clears
#   are permanently moot, neither implemented) via the same shape
#   `breaks_screens` (Brick Break, `[M16c]`) already establishes, reused
#   here against the DEFENDER's side instead of Brick Break's own
#   attacker-relative target; clears hazards from BOTH sides (source:
#   `DefogClearHazards`, looped over `NUM_BATTLE_SIDES`, at this
#   project's `B_DEFOG_EFFECT_CLEARING >= GEN_6` config); AND lowers the
#   TARGET's own evasion by 1 stage (source's own `additionalEffects`:
#   `STAT_CHANGE_EFFECT_MINUS, .evasion = 1`, no `.self` — a foe-targeting
#   drop, reuses the existing generic `stat_change_stat`/`amount`/`self`
#   fields directly). Source's own Fog-weather clear and GEN_8+ Terrain
#   clear are both permanently moot (neither Fog nor Terrain modeled in
#   this project). Source: battle_script_commands.c :: TryDefogClear
#   (L6755-6793), DefogClearHazards (L6733-6752).
@export var is_defog: bool = false

# is_tidy_up: Tidy Up(808) — EFFECT_TIDY_UP, a self-targeted status move
#   confirmed BROADER than the D2 recon's own "hazards + self stat-raise"
#   framing: source's `TryTidyUpClear` (battle_script_commands.c L6801-
#   6825) ALSO clears every Substitute currently on the FIELD (both
#   sides, any battler — a genuinely new finding, not previously flagged
#   anywhere), not just hazards. Clears hazards from BOTH sides (the same
#   `DefogClearHazards` function Defog itself calls), THEN clears every
#   battler's Substitute if no hazard was found to clear (source's own
#   `if (clearFound) return TRUE;` short-circuit — this project composes
#   both checks directly rather than mimicking the exact one-clear-per-
#   script-call iteration, since the end result after one full move use
#   is identical: everything clearable gets cleared). Self Atk+1/Speed+1
#   always applies regardless of what was cleared (source's own
#   `WillAnyStatChange() || TryTidyUpClear(FALSE)` gate — the move only
#   fails outright if NEITHER the stat raise NOR any clear would do
#   anything). Reuses the existing `stat_change_stat`/`amount` primary
#   pair plus `extra_stat_change_stats`/`amounts` multi-stat mechanism
#   (`[Bucket 3 multi-stat]`, the same shape Dragon Dance/Bulk Up already
#   use) for the self Atk+1/Speed+1 pair.
@export var is_tidy_up: bool = false

# is_role_play: Role Play(272) — EFFECT_ROLE_PLAY, the ATTACKER copies the
#   TARGET's current ability (the move-driven mirror of Trace's own
#   switch-in-driven copy, `[M17h]`) — `ignoresProtect = TRUE` AND
#   `ignoresSubstitute = TRUE` in source (a real asymmetry within this
#   4-move family: Skill Swap/Heart Swap do NOT ignore Protect, only
#   Substitute). Source: battle_script_commands.c :: Cmd_trycopyability
#   (L8997-9025) — fails if the attacker already holds this exact ability
#   (by ID; this project loads `AbilityData` ad hoc per call site so two
#   mons "holding the same ability" are typically separate Resource
#   instances, never compared by object identity), the target has no
#   ability, the attacker's OWN current ability is `cant_be_suppressed`,
#   or the target's ability is `cant_be_copied`. Reads/writes the RAW
#   `.ability` field throughout (matches Trace/Receiver/Mummy/Wandering
#   Spirit's own established precedent — suppression is never a copy-time
#   filter). AbilityShield's own separate block isn't modeled (no such
#   item in this project).
@export var is_role_play: bool = false

# is_skill_swap: Skill Swap(285) — EFFECT_SKILL_SWAP, a genuine
#   BIDIRECTIONAL ability swap between attacker and target, confirmed to
#   reuse the EXACT SAME primitive Wandering Spirit's own contact-
#   triggered swap already established (`[M17h]`) rather than merely a
#   similar one: gated on `cant_be_swapped` on BOTH sides independently
#   (source: `Cmd_tryswapabilities`, L9160-9195 — an ability-less
#   `.ability == null` battler is treated the same as `cant_be_swapped`,
#   matching source's own `ABILITY_NONE` carrying that flag). `ignores
#   Substitute = TRUE` in source but NOT `ignoresProtect` (blocked by
#   Protect normally, a real asymmetry from Role Play above).
@export var is_skill_swap: bool = false

# is_heart_swap: Heart Swap(391) — EFFECT_HEART_SWAP. Confirmed genuinely
#   NOT an ability move despite sharing this family's "ability-
#   manipulation" label — swaps all 7 stat STAGES bidirectionally between
#   attacker and target (source: `BattleScript_EffectHeartSwap`, one
#   `swapstatstages` call per stat — Atk/Def/Speed/SpAtk/SpDef/Evasion/
#   Accuracy, all 7), reusing Psych Up's own stage-array shape (`[M16e]`)
#   but as a genuine bidirectional SWAP rather than a one-directional
#   copy. `ignoresSubstitute = TRUE` in source but NOT `ignoresProtect`
#   (same asymmetry as Skill Swap, not Role Play). Correctly untouched by
#   any ability-exemption field (`cant_be_suppressed`/`cant_be_swapped`/
#   etc.) since no ability is involved at all.
@export var is_heart_swap: bool = false

# overwrite_target_ability_id: Worry Seed(388) — EFFECT_OVERWRITE_ABILITY,
#   confirmed via source to be the SAME underlying primitive Mummy/
#   Lingering Aroma's own ability-triggered overwrite conceptually shares
#   (both gated on `AbilityData.cant_be_overwritten`, the exact field
#   `[M17h]`'s own entry predicted "consumed by Skill-Swap/Entrainment-
#   style moves this project doesn't have" — Worry Seed is precisely that
#   consumer, confirming that prediction), but dispatched from a
#   genuinely different call site (`Cmd_tryoverwriteability`,
#   battle_script_commands.c L10627-10650, a move-driven fixed-target
#   overwrite — `.argument.overwriteAbility = ABILITY_INSOMNIA` for this
#   move specifically) rather than Mummy's contact-reactive one. Fails if
#   the target's ability is `cant_be_overwritten` OR the target already
#   holds this exact ability (no-op). Real accuracy check applies
#   (accuracy=100, NOT ignoresSubstitute/ignoresProtect — a fully normal
#   foe-targeting status move otherwise) and `magicCoatAffected = TRUE`
#   (reflectable by Magic Bounce — `bounceable = true` set on this move's
#   own data, `[M17n-9]`'s existing `move.bounceable` mechanism picks it
#   up with zero code changes). FLAGGED, not fixed: source's own script
#   also calls `trytoclearprimalweather`/`tryendneutralizinggas` after a
#   successful overwrite (in case the ability just stripped away was one
#   sustaining Primal weather or Neutralizing Gas) — a real, narrow,
#   out-of-scope edge case this project does not model.
@export var overwrite_target_ability_id: int = -1

# is_solar_beam_weather_halved: reused by DamageCalculator to halve
#   Solar Beam(76)/Solar Blade(632)'s power (`move.is_solar_beam`) in any
#   weather other than Sun/none/Strong Winds — see DamageCalculator.
#   calculate's own doc comment at the insertion point for the full
#   source citation. No new MoveData field needed (`is_solar_beam`
#   already covers both moves identically) — this comment exists purely
#   to document that the halving logic lives in DamageCalculator, not
#   here, so a future reader searching move_data.gd for "solar" finds a
#   pointer rather than nothing.

# ── D2 batch 2 — offense-stat-source-override family (Foul Play/Body
# Press/Photon Geyser) + per-mon TypeChart-override family (Freeze-Dry/
# Tar Shot/Foresight/Odor Sleuth) ──

# is_foul_play: Foul Play(492) — EFFECT_FOUL_PLAY, damage computed off the
#   TARGET's own Attack (or Sp. Attack — `IsBattleMovePhysical(move)`
#   gated, but Foul Play's own category is fixed Physical so only the
#   Attack branch is ever reached) stat AND stage, not the attacker's own.
#   Only the raw offense-stat SOURCE changes — type effectiveness, STAB,
#   ability gates all stay keyed on the ATTACKER as normal (confirmed:
#   `EFFECT_FOUL_PLAY` is absent from `SetDynamicMoveCategory`'s switch,
#   so no category swap occurs, unlike Photon Geyser below). Crit/Unaware
#   stage adjustments compose for free — they're applied to whichever
#   `atk_stage` variable holds after this override, matching source's own
#   `CalcAttackStat` (battle_util.c L6737-6748) ordering exactly (this
#   override happens before crit/Unaware's own stage-zeroing).
@export var is_foul_play: bool = false

# is_body_press: Body Press(704) — EFFECT_BODY_PRESS, damage computed off
#   the USER's own Defense stat AND stage instead of Attack (physical
#   category, confirmed fixed — the special-category branch in source is
#   dead code for this specific move since its own `.category` never
#   varies). Source's own Wonder Room edge case (uses the Defense stat
#   value but the Sp. Def stat's STAGE while Wonder Room is active) is
#   permanently moot — Wonder Room(472) is on Rob's own exclusion list,
#   unimplemented in this project entirely.
@export var is_body_press: bool = false

# is_photon_geyser: Photon Geyser(675) — EFFECT_PHOTON_GEYSER. **A real
#   hidden second effect, not just a raw-stat-lookup override**: this
#   move's own description ("User's highest attack stat determines its
#   category") is literal — source's `SetDynamicMoveCategory`
#   (battle_util.c L8975-8995) DYNAMICALLY SWAPS the move's WHOLE
#   category (Special→Physical) via `GetCategoryBasedOnStats`
#   (L9025-9039: compares the attacker's own STAGE-ADJUSTED Atk vs SpAtk;
#   ties go to SPECIAL, `spAttack >= attack`), which cascades into every
#   category-gated check downstream this project already has (Guts'
#   burn-halving, Choice item validity, any category-keyed ability) — not
#   merely which stat feeds the damage formula. Implemented in
#   `DamageCalculator.calculate` via the same shallow-duplicate-and-
#   substitute pattern already established for Hidden Power/M17n-6's
#   type mutation, just mutating `.category` instead of `.type` — every
#   existing `move.category` check downstream sees the swapped value for
#   free, zero changes needed to any of them. `.ignoresTargetAbility =
#   TRUE` in source — reuses the EXISTING `ignores_target_ability`
#   mechanism (`[Bucket 4 2-move sub-groups]`'s Sunsteel Strike/Moongeist
#   Beam) directly, zero new code for that half.
@export var is_photon_geyser: bool = false

# super_effective_vs_type: Freeze-Dry(573) — EFFECT_SUPER_EFFECTIVE_ON_ARG,
#   `.argument.type = TYPE_WATER`. Forces THAT SPECIFIC defending-type
#   component's multiplier to a flat 2.0 (super-effective) regardless of
#   the real chart value — an unconditional override, not a "fix 0→1"
#   pattern like `bypass_ghost_immunity`/`weaken_flying_se` (Water is
#   normally NEUTRAL to Ice in the real type chart, not resistant, so
#   this move's whole point is overriding that neutral matchup up to
#   Super Effective). Checked PER defending-type component (a dual-type
#   defender's OTHER type's own modifier is untouched), the same
#   per-component semantics `TypeChart.get_uq412`/`get_effectiveness`'s
#   existing override params already use — new `force_super_effective_
#   type` param added to both, mirroring `bypass_ghost_immunity`'s own
#   shape. Source: battle_util.c :: MulByTypeEffectiveness (L8061-8062).
#   General field (not Freeze-Dry-specific by name) since source's own
#   `.argument.type` is itself a general per-move config, in case a
#   future move reuses this effect with a different forced type.
#   Source's own `!ctx->isAnticipation` guard is permanently moot — this
#   project's Anticipation is a documented cosmetic no-op (`[M17c]`), no
#   real type-effectiveness-preview mode exists to exclude. **A real
#   secondary this move also carries, beyond the D2 recon's own "always
#   super-effective vs Water" framing**: a 10%-chance Freeze secondary
#   (`MOVE_EFFECT_FREEZE_OR_FROSTBITE`, resolving to plain STATUS_FREEZE
#   at this project's config, matching Tri Attack's own established
#   precedent for the identical simplification) — reuses the existing
#   generic `secondary_effect = SE_FREEZE`/`secondary_chance = 10`
#   fields, zero new mechanism.
@export var super_effective_vs_type: int = 0  # TypeChart.TYPE_NONE (0) = disabled

# is_tar_shot: Tar Shot(695) — EFFECT_TAR_SHOT. Confirmed a PER-MON
#   (not move-level) PERMANENT override, genuinely different in SHAPE
#   from Freeze-Dry's own per-component override above: a flat POST-
#   COMBINATION ×2.0 multiplier applied to the FULLY-COMBINED type
#   effectiveness value (both defending types already multiplied
#   together), gated on the ATTACKING move being Fire-type — source:
#   battle_util.c L8145-8146 (`ctx->moveType == TYPE_FIRE &&
#   volatiles.tarShot → modifier *= 2.0`), positioned AFTER both
#   `MulByTypeEffectiveness` calls, not per-defending-type-component like
#   Freeze-Dry. New `BattlePokemon.tar_shot_active: bool` volatile (no
#   turn counter — permanent until the target switches out, cleared via
#   the standard `_clear_volatiles` convention, no reciprocal-clear
#   needed since it isn't tied to a source battler leaving the field).
#   Confirmed via direct source read this can NEVER stack with/conflict
#   against Freeze-Dry's own override on the same hit: Freeze-Dry is
#   always Ice-type, and Tar Shot's own doubling is gated specifically on
#   TYPE_FIRE, so the two conditions are mutually exclusive by
#   construction (Freeze-Dry can never trigger Tar Shot's Fire-gate).
#   Guaranteed self... foe-targeting -1 Speed via the existing generic
#   `stat_change_stat`/`amount` fields (no `.chance` field in source's
#   own `additionalEffects` block — primary, not a true secondary).
@export var is_tar_shot: bool = false

# is_foresight: Foresight(193)/Odor Sleuth(316) — confirmed via direct
#   source read to share the LITERAL SAME `.effect = EFFECT_FORESIGHT`
#   (Odor Sleuth is not merely similarly-shaped, it is mechanically
#   identical — only the flavor name/contest data differ). Sets a
#   PERMANENT per-TARGET volatile (`setvolatile BS_TARGET,
#   VOLATILE_FORESIGHT`, `BattleScript_EffectForesight`,
#   data/battle_scripts_1.s L2165-2174) — fails if the target already has
#   it (checked at this project's GEN_LATEST config: `CONFIG_B_FORESIGHT_
#   FAIL >= GEN_5`), no turn counter, cleared only via the target's own
#   switch-out (standard `_clear_volatiles`). Two genuinely independent
#   effects, confirmed via two SEPARATE source checks: (1) Ghost-type
#   Normal/Fighting-immunity bypass — the LITERAL SAME per-defending-
#   type-component `bypass_ghost_immunity` gate Scrappy/Mind's Eye
#   already use (battle_util.c L8047-8052), OR'd in at the
#   `DamageCalculator.calculate` call site rather than threading a new
#   parameter through `TypeChart`'s functions (the effect is identical
#   regardless of whether it's attacker-ability-driven or defender-
#   volatile-driven). (2) Evasion-stage-ignore — confirmed via
#   `GetTotalAccuracy` (battle_util.c L10259-10261) that source computes
#   this as `buff = accStage` (skipping the evasion term entirely) when
#   `volatiles.foresight || volatiles.miracleEye` is true, which is
#   MATHEMATICALLY IDENTICAL to this project's own existing `eva_stage =
#   0` zeroing pattern (`ignores_defense_evasion_stages`'s own insertion
#   point) — same neutral-stage-reset shape, not a separate mechanism.
#   Miracle Eye is NOT implemented in this project and is NOT part of
#   this session's scope — confirmed it's a wholly separate condition in
#   source (Psychic-vs-Dark, not Normal/Fighting-vs-Ghost) for the
#   Ghost-bypass half, so no conflation risk; the evasion-ignore half's
#   own `|| volatiles.miracleEye` collapses correctly to just this
#   project's `foresight_active` since Miracle Eye simply doesn't exist
#   here. `ignoresSubstitute = TRUE` in source; `magicCoatAffected =
#   TRUE` at this project's GEN_LATEST config → `bounceable = true`.
@export var is_foresight: bool = false

# ── [D3 turn-order/event-tracker batch] Turn-order-manipulation family ──────
#
# is_after_you: After You(495) — pushes the target to act IMMEDIATELY NEXT
#   (right after the current actor), regardless of speed. Fails if the target
#   has already acted this turn. Source: battle_util.c ::
#   ChangeOrderTargetAfterAttacker (L10743-10784) — at this project's
#   GEN_LATEST config (B_AFTER_YOU_TURN_ORDER >= GEN_8), a target already
#   immediately-next is a trivial success (no reorder needed); this project's
#   own "move to _current_actor_index + 1" implementation reproduces that for
#   free by being a no-op when already there. Ignores Protect/Substitute
#   (`ignoresProtect`/`ignoresSubstitute` = TRUE).
@export var is_after_you: bool = false

# is_quash: Quash(511) — pushes the target to act LAST among all remaining
#   (not-yet-acted) battlers this turn. Fails if the target has already
#   acted. Source: battle_script_commands.c :: BS_TryQuash (L11762-11799) —
#   real source's exact reordering is speed-order-preserving in a 3+-battler
#   scenario at GEN_8+ config (`GetWhichBattlerFaster`-driven incremental
#   swap), a doubles-only nuance; this project implements the simpler
#   move-to-absolute-end behavior (matching source's own GEN_7- branch, and
#   observably identical to the GEN_8+ branch in singles, the primary
#   supported case) — flagged as a known simplification for 3+-remaining-
#   battler doubles scenarios, not silently assumed identical.
@export var is_quash: bool = false

# is_upper_hand: Upper Hand(846) — a damaging move (priority +3, contact,
#   guaranteed flinch via the existing SE_FLINCH secondary_effect) that only
#   CONNECTS if the target's own CHOSEN move (not yet executed) has an
#   ability-boosted priority in [1, 3], the target hasn't already acted this
#   turn, and the target's chosen move is not status-category. Re-checked
#   fresh at Upper Hand's own execution time using the SAME
#   AbilityManager.move_priority_bonus function this project's turn-order
#   sort already uses — NOT a raw-move.priority-only check — so an ability
#   that suppresses/alters priority before this point (e.g. Prankster,
#   Gale Wings) is correctly reflected. Source: battle_move_resolution.c,
#   case EFFECT_UPPER_HAND (L1403-1417) — `GetChosenMovePriority(battlerDef,
#   GetBattlerAbility(battlerDef))`, the identical function used for actual
#   turn-order sorting (battle_main.c L4722-4731). On failure the whole move
#   fails (no damage, no flinch) — the same "ButItFailed" shape this
#   project's existing Sucker Punch dispatch already establishes.
@export var is_upper_hand: bool = false

# is_instruct: Instruct(652) — forces the TARGET to immediately re-use its
#   own last_move_used against its own last-targeted opponent (approximated
#   in this project as the original Instruct user — exact in singles, a
#   known simplification in doubles where source tracks a real
#   backUpTarget). Does NOT cost the instructed move's own PP (a genuine
#   "called move", matching source's `jumptocalledmove TRUE` — the same
#   free-call shape this project's Metronome/Mirror Move already establish).
#   Fails if: no last_move_used yet; that move's own PP is at 0; that move is
#   two-turn, sets recharge, is a multi-hit-escalating move (Rollout/Ice
#   Ball), calls another move (Metronome/Mirror Move), is Bide (its own
#   multi-turn accumulation lock, source-flagged instructBanned
#   independently of the two_turn/is_recharge checks above), is Obstruct
#   specifically (source flags ONLY Obstruct + King's Shield among the
#   Protect family as instructBanned — Protect/Detect/Baneful Bunker/Silk
#   Trap/Burning Bulwark/Wide Guard/Quick Guard are NOT banned, a real,
#   move-specific data quirk, not a general Protect-family rule), or is a
#   rampage/Uproar lock (Thrash/Petal Dance/Outrage/Uproar); or if the target
#   is currently mid-Bide. Source: battle_script_commands.c :: BS_TryInstruct
#   (L13149-13195); the exclusion list re-derived directly against this
#   project's OWN currently-implemented `instructBanned`-flagged moves (all
#   23 confirmed covered — 21 via the pre-existing `two_turn`/`is_recharge`/
#   `is_rollout`/`is_bide` checks, Metronome/Mirror Move via their own
#   `is_metronome`/`is_mirror_move` flags, Obstruct via `protect_method`,
#   Thrash/Petal Dance/Outrage/Uproar via `is_rampage`/`is_uproar`) rather
#   than the source's full list or the project's own sparsely-populated
#   `BAN_INSTRUCT` bitflag (only 2 of these 23 moves currently carry it).
#   `ignoresSubstitute = TRUE`; Sky-Drop-target semi-invulnerable exclusion
#   is permanently moot (Sky Drop unimplemented).
@export var is_instruct: bool = false

# ── [D3 turn-order/event-tracker batch] "Event happened this turn/battle"
# tracker family ─────────────────────────────────────────────────────────
#
# is_lash_out: Lash Out(736) — power doubles if the USER'S OWN stat was
#   lowered this turn, by ANY source (move/ability/item alike) — the genuine
#   mirror of the already-shipped `stat_raised_this_turn` trigger
#   ([M19-stat-raised-trigger]), but for decreases and reusing the exact same
#   general chokepoint (StatusManager.apply_stat_change). Source:
#   battle_util.c, case EFFECT_LASH_OUT (L6308-6310) —
#   `gProtectStructs[battlerAtk].lashOutAffected`, set at
#   battle_stat_change.c L368 (the single shared stat-DECREASE-application
#   chokepoint, the decrease-side twin of SetStatChange's own increase-side
#   `statRaised` flag) and cleared for every battler at the start of each
#   turn (battle_main.c L5056).
@export var is_lash_out: bool = false

# is_retaliate: Retaliate(514) — power doubles if a Pokémon on the USER'S
#   OWN SIDE fainted during the PREVIOUS turn (not this turn) — a side-wide
#   (not per-mon) condition, confirmed via source to never look at the
#   opposing side. Source: battle_util.c, case EFFECT_RETALIATE (L6401-6406)
#   — `gSideTimers[atkSide].retaliateTimer == 1`; the timer is set to 2 on
#   ANY faint on that side (battle_util.c L11014/11021) and decremented once
#   per turn boundary (battle_main.c L3939-3940) — so a faint during turn N
#   reads as 2 (not yet doubled) if Retaliate is used later in that SAME
#   turn N, and reads as 1 (doubled) once turn N+1 begins.
@export var is_retaliate: bool = false

# is_rage_fist: Rage Fist(815) — power increases +50 per prior hit the user
#   has taken THIS BATTLE — a battle-LIFETIME counter (BattlePokemon.
#   times_hit), NOT a per-turn tracker like every other move in this family,
#   and confirmed via source to have no reset mechanism at all (survives
#   switch-out/switch-in, unlike every other volatile this project clears in
#   `_clear_volatiles`) — the same switch-persistent-per-party-slot shape
#   already established for `last_consumed_berry` ([M17n-7] Harvest).
#   Base 50, +50 per hit taken, capped at 350 total. Source: battle_util.c,
#   case EFFECT_RAGE_FIST (L6349-6351) —
#   `GetBattlerPartyState(battlerAtk)->timesGotHit`, incremented at the
#   general "took direct hit damage" chokepoint (battle_script_commands.c
#   L1685), unconditional on move category/contact.
@export var is_rage_fist: bool = false

# is_echoed_voice: Echoed Voice(497) — power scales with a FIELD-WIDE
#   (not per-mon, not per-side) consecutive-turn-use counter: `power * (1 +
#   counter)`, counter capped at 4 (so power ranges 40/80/120/160/200 —
#   the 200 cap is redundant at counter=4 but reproduced literally to match
#   source). The counter increments (capped at 4) once per turn boundary IF
#   Echoed Voice was used by ANYONE on the field that turn (gated only on
#   the move being attempted — not blocked by a pre-move canceler — NOT on
#   whether the hit actually connected), and resets to 0 the instant a turn
#   passes without any use. Source: battle_util.c, case EFFECT_ECHOED_VOICE
#   (L6264-6270); the counter itself lives in `gBattleStruct->
#   echoedVoiceCounter`, incremented/reset in HandleEndTurnVarious
#   (battle_end_turn.c L79-88), set-to-increment in
#   battle_move_resolution.c L4914-4916 (`if (!unableToUseMove)
#   incrementEchoedVoice = TRUE`).
@export var is_echoed_voice: bool = false

# ── [Delayed-effect family] Per-slot delayed scheduler ──────────────────────
#
# is_future_sight: Future Sight(248)/Doom Desire(353) — share the literal
#   same EFFECT_FUTURE_SIGHT. Cast schedules a hit that resolves 2 full
#   turns later against WHOEVER OCCUPIES the target's combatant slot at
#   that time (not necessarily the original target — a switch survives).
#   Fails at cast time if that slot already has one pending. NO accuracy
#   roll at cast or resolve time (confirmed from source — neither
#   BattleScript_EffectFutureSight nor BattleScript_MonTookFutureAttack
#   ever calls `accuracycheck`); resolution does a fresh type-
#   effectiveness check only (0x fizzles silently). Resolution is routed
#   through the existing `_do_damaging_hit` chokepoint (screens,
#   Substitute, Sturdy/Focus Band/Focus Sash, times_hit, Air Balloon, etc.
#   all apply for free, matching source's own DoMoveDamageCalc path).
#   Source: battle_move_resolution.c L1365-1372 (cast-time already-
#   pending fail check), L1620-1623 (schedule: counter=3, stores the
#   caster's slot+move), battle_end_turn.c L232-276 (HandleEndTurnFutureSight
#   — decrements once per end-of-turn, resolves at 0).
#
#   Cast-time-vs-resolve-time snapshot (a real Step-0 finding, not
#   assumed): source recomputes EVERYTHING at RESOLVE time, never cast
#   time — but the DATA SOURCE forks on whether the original caster is
#   still the live occupant of its own original slot. Still there → a
#   fully normal fresh damage calc (live stats/ability/item/stat stages,
#   fresh crit roll). Left (switched/fainted) → source temporarily
#   reconstructs the caster from PARTY data with ability/item forced to
#   NONE (DoFutureSightAttackDamageCalc, battle_util.c L7733-7763). This
#   project reproduces the majority of that distinction for FREE: a
#   caster that switched out already has stat_stages reset to 0 by the
#   existing `_switch_out_clear` (`[M9]`), so a benched caster's stale
#   boosts never leak into the delayed hit. The one disclosed gap: this
#   project does NOT additionally null the benched caster's ability/item
#   the way source does — a narrow, rare edge case (an ability/item that
#   passively boosts Sp.Atk while the mon sits on the bench) not worth
#   the extra struct-swap machinery source needs for its own layout.
@export var is_future_sight: bool = false

# is_wish: Wish(273) — schedules a heal 1 turn later (counter starts at 2,
#   decrementing once at the end of the CAST turn itself and once more at
#   the end of the next turn) targeting WHOEVER OCCUPIES THE CASTER'S OWN
#   slot when it resolves — a genuine switch survives (a different party
#   member can receive the heal). The heal amount is fixed at cast time
#   to `caster's own max HP / 2` (via `[GetConfig(B_WISH_HP_SOURCE) >=
#   GEN_5]`, satisfied at this project's GEN_LATEST config) — NOT the
#   eventual recipient's own max HP. Fails at cast time if already
#   pending on that slot. Fresh full-HP/heal-block check at resolve time.
#   This project has no Heal Block mechanic implemented at all (excluded,
#   see `[M19-rescope-followup]`'s Psychic Noise note) so that specific
#   resolve-time check is permanently moot here. Source: battle_script_
#   commands.c :: Cmd_trywish (L9029-9046, cast-time fail+schedule),
#   battle_end_turn.c :: HandleEndTurnWish (L282-310, resolve).
@export var is_wish: bool = false

# ── [Delayed-effect family] Per-mon volatile counter ─────────────────────────
#
# is_yawn: Yawn(281) — a per-mon volatile counter, MECHANICALLY IDENTICAL
#   in shape to the already-shipped disable_turns/encore_turns/
#   throat_chop_turns pattern — genuinely NOT part of the per-slot
#   scheduler family above despite the shared "delayed effect" framing;
#   confirmed via source this is a plain `gBattleMons[target].volatiles.
#   yawn` counter (2->1->0), not `gBattleStruct`-level state, so it's
#   already correctly cleared by the existing switch-out volatile-clear
#   plumbing if the target switches away mid-countdown — zero new switch/
#   faint handling needed. Cast-time: fails if the target already has a
#   pending yawn OR already has ANY status (checked once, up front).
#   Resolve-time (one turn later): fires a completely FRESH sleep-
#   infliction attempt via the existing `StatusManager.try_apply_status`
#   pipeline — which already re-derives every immunity (Insomnia/Vital
#   Spirit/Leaf Guard/already-statused/Uproar-awake) at that exact
#   moment, not locked in at cast time. Source: battle_script_commands.c
#   :: Cmd_setyawn (L9091-9116, cast-time), battle_end_turn.c (L915-935,
#   resolve-time decrement+inflict). Terrain-based blocks (Electric/Misty)
#   are permanently moot (Terrain is void for this project, `[M17d]`).
@export var is_yawn: bool = false

# ── [Delayed-effect family] Switch-in-triggered one-shot ─────────────────────
#
# is_healing_wish: Healing Wish(361) — the user faints to fully heal AND
#   cure the status of whoever NEXT switches into that slot, by ANY
#   method (voluntary, forced via Roar/Whirlwind, or faint-replacement —
#   all three confirmed to funnel through this project's shared switch-in
#   sites). Genuinely the THIRD mechanism shape in this family, distinct
#   from both the per-slot scheduler (Future Sight/Wish) and the per-mon
#   volatile (Yawn): a single per-slot BOOLEAN/kind flag with no counter
#   at all, consumed by the next switch-in event. UNLIKE Explosion/Self-
#   Destruct (`[M19-self-faint]`, which always faints unconditionally),
#   this move FAILS OUTRIGHT (no faint, no stored effect) if the user has
#   no valid Pokémon to switch to — checked BEFORE fainting, reusing the
#   existing `BattleParty.has_valid_switch_target()` (`[M9]`). A disclosed
#   simplification, confirmed with Rob before implementing: real source
#   at this project's Gen8+ config lets the stored effect PERSIST across
#   multiple switch-ins on that slot until one actually benefits (skipped
#   for an already-full-HP/no-status recipient) — this project always
#   consumes on the very next switch-in regardless, healing/curing only
#   if something is actually needed. Source: data/battle_scripts_1.s
#   L1100-1110 (cast: jumpifcantswitch/instanthpdrop/tryfaintmon/
#   storehealingwish), L1138-1151 (shared restore block with Lunar Dance
#   below — heals to full AND cures status), src/battle_switch_in.c
#   L189-232 (consumption at switch-in, incl. the Gen8+ CanBattlerBeHealed
#   persistence nuance this project deliberately simplifies away).
@export var is_healing_wish: bool = false

# is_lunar_dance: Lunar Dance(461) — mechanically identical to Healing
#   Wish above (same fail-if-no-switch-target gate, same faint-and-store-
#   on-slot shape, same simplified always-consume-next-switch-in
#   behavior) PLUS restores full PP to all 4 of the recipient's moves —
#   confirmed via the shared `BattleScript_EffectHealingWishRestore`
#   block both moves jump into, with Lunar Dance's own extra
#   `restoremovepp BS_SCRIPTING` line. Source: same citations as
#   is_healing_wish above, plus data/battle_scripts_1.s L1135-1137
#   (BattleScript_LunarDanceActivates's own `restoremovepp`).
@export var is_lunar_dance: bool = false

# ── [Psyshock/Psystrike] Defense-stat-source override ────────────────────────
#
# is_psyshock: Psyshock(473)/Psystrike(540) — share the literal same
#   EFFECT_PSYSHOCK. A Special-category move that computes damage using
#   the DEFENDER's Defense stat AND stage instead of Sp. Defense — the
#   defense-side mirror of the already-shipped Foul Play/Body Press
#   offense-side overrides (`[D2 batch 2]`), but genuinely simpler in
#   shape: unlike Foul Play/Body Press (which swap WHICH BATTLER's stat
#   is read), this stays on the SAME battler (the defender) and just
#   swaps WHICH COLUMN (Defense instead of Sp. Defense) — no cross-
#   battler pattern needed, just an added OR condition at the existing
#   category-based defense-stat-selection point. Confirmed NO category
#   swap occurs (unlike Photon Geyser) — STAB, ability triggers, and
#   secondary-effect gating all stay keyed on Special for every other
#   purpose. Wonder Room's stat-swap interaction is permanently moot
#   (unimplemented, same precedent as Body Press). Source: battle_util.c
#   :: CalcDefenseStat (L7021-7035) — `if (moveEffect == EFFECT_PSYSHOCK
#   || IsBattleMovePhysical(move))`.
@export var is_psyshock: bool = false

# ── [D1 easy bundle] Six small, mechanically-contained families ─────────────
#
# is_hit_escape: U-turn(369)/Volt Switch(521)/Flip Turn(740) — the
#   attacker gets a voluntary-style switch prompt after a hit that
#   CONNECTED (real HP damage OR a Substitute absorption —
#   INCLUDING_SUBSTITUTES in source), gated on the attacker still being
#   alive afterward (a recoil/contact-punish death correctly blocks it).
#   Reuses `_get_replacement_slot`'s own player-choice selection chain
#   (test queue → AI choice → deterministic first-available) — the SAME
#   one faint-replacement already uses — NOT Red Card's random pick,
#   since the user's own trainer chooses who comes in next, matching
#   real games. No-ops (damage still stands) with no valid bench
#   replacement. Source: battle_move_resolution.c :: MoveEndHitEscape
#   (L3905-3920).
@export var is_hit_escape: bool = false

# is_hit_switch_target: Circle Throw(509)/Dragon Tail(525) — forces the
#   DEFENDER out after a hit that dealt REAL HP damage, EXCLUDING a
#   Substitute absorption — the opposite of is_hit_escape's own
#   inclusive check, confirmed from source (`EXCLUDING_SUBSTITUTES` vs.
#   `INCLUDING_SUBSTITUTES`). Dispatches through the same RANDOM-
#   replacement machinery Roar/Whirlwind/Red Card already use (a
#   genuinely forced switch, not a player choice — confirmed via
#   source's `BattleScript_TryHitSwitchTarget`/`B_SWITCH_HIT`, the same
#   general forced-switch script Roar's own dispatch shares). Blocked by
#   Guard Dog (`blocks_forced_switch`, `[M17n-10]`); Suction Cups/
#   Ingrain-root checks are permanently moot (both unimplemented).
#   No-ops (damage still stands) with no valid replacement on the
#   defender's side. Source: battle_move_resolution.c ::
#   EFFECT_HIT_SWITCH_TARGET (L3517-3545).
@export var is_hit_switch_target: bool = false

# is_first_turn_only: Fake Out(252)/First Impression(623) — fails unless
#   this is the user's first ACTION since switching in (not the first
#   turn of the whole battle). Reuses the EXISTING `BattlePokemon.
#   switched_in_this_turn` flag directly — already set true at all 3
#   switch-in sites and reset to false at the start of every subsequent
#   turn (the exact same semantic Stakeout/Speed Boost already consume
#   it for) — zero new tracking state needed. A real, easy-to-miss
#   wrinkle found at Step 0: source ALSO fails if the move was reached
#   via a CALLED dispatch rather than genuinely selected that turn
#   (`gSpecialStatuses[...].backUpTarget`, set by Instruct's own
#   redirect) — since `switched_in_this_turn` alone stays true for the
#   mon's ENTIRE first turn back, Instruct could otherwise force a
#   second same-turn Fake Out. Reproduced by adding `is_first_turn_only`
#   to Instruct's own exclusion list directly (functionally equivalent
#   outcome to source's flag, different implementation shape). Source:
#   battle_move_resolution.c :: EFFECT_FIRST_TURN_ONLY (L1222-1224),
#   `IsBattlersFirstTurn`.
@export var is_first_turn_only: bool = false

# is_trick: Trick(271)/Switcheroo(415) — full BIDIRECTIONAL held-item
#   swap between attacker and defender (a genuinely new 4th direction
#   for the M17j item-transfer family, alongside Pickpocket/Magician's
#   one-way steals and Symbiosis's one-way give). Fails if both
#   Pokémon are itemless, or if EITHER side would either lose an item
#   its own species is form-locked by OR gain one it would be
#   form-locked by (checked via the shared
#   `AbilityManager.is_form_locked_by_item`, this project's own
#   Multitype-linkage model, `[M17n-4]`, standing in for source's
#   species-level `DoesSpeciesUseHoldItemToChangeForm` check — the ONE
#   relevant exclusion out of source's full `CanBattlerGetOrLoseItem`
#   list; Mail/E-Reader-Berry/Z-Crystals/Booster-Energy-Paradox/
#   Ogerpon-Masks are all permanently moot, corresponding to items/
#   species this project has never implemented). Re-derived from
#   source's own 4 `CanBattlerGetOrLoseItem` calls (both directions ×
#   both sides) after an initial 2-check version — only checking each
#   side's OWN currently-held item — was found to miss the "gains a
#   foreign form-locking item" half; see decisions.md's Multitype-Plate
#   fix entry. Blocked by Sticky Hold — checked ONLY on the TARGET
#   (source: `GetBattlerAbility(gBattlerTarget) == ABILITY_STICKY_HOLD`),
#   not the attacker. Substitute-blocked via the general Substitute
#   gate this move's own lack of `ignoresSubstitute` already routes
#   through. Source: battle_script_commands.c :: Cmd_tryswapitems
#   (L8874-8930).
@export var is_trick: bool = false

# is_revenge: Revenge(279)/Avalanche(419) — power doubles ONLY if the
#   user was hit BY THIS SPECIFIC TARGET earlier this same turn — a
#   real, narrow scoping confirmed from source (a per-(victim,attacker)-
#   pair bitmask, `revengeDoubled |= 1u << attackerId`, NOT a plain "was
#   I hit by anyone" bool). Genuinely distinct from Lash Out/Retaliate's
#   shipped D2-tracker-family mechanism — needs its own new per-mon "who
#   hit me this turn" list (`BattlePokemon.hit_by_this_turn`), set at
#   the same `_do_damaging_hit` chokepoint `times_hit`/`last_attacker`
#   already use, cleared every turn like its D2 siblings. Priority -4
#   (moves last), narratively consistent with checking "did my target
#   already hit me earlier this turn" — the target has almost always
#   already acted by the time a Revenge user's own turn comes. Source:
#   battle_util.c, case EFFECT_REVENGE (L6172-6174); set-site
#   battle_script_commands.c L1656-1657 (the same chokepoint Assurance's
#   own `assuranceDoubled` flag is set at, confirming both fire on ANY
#   damage taken, not move-category-restricted).
@export var is_revenge: bool = false

# is_stomping_tantrum: Stomping Tantrum(661)/Temper Flare(843) — power
#   doubles if the user's own PREVIOUS move failed (missed, was
#   blocked, had no effect) — a NEW flag distinct from `last_move_used`
#   (which tracks WHAT the last move was, not whether it succeeded).
#   Genuinely a 2-turn COUNTER, not a plain bool — set to 2 the same
#   turn a move fails, decremented once per turn boundary at the SAME
#   site `[D3 turn-order/event-tracker batch]`'s Retaliate timer uses
#   (a real correction applied to that tier alongside this one — see
#   this move's own decisions.md entry for the full timing-bug writeup).
#   Checked against `== 1` at power-computation time (one turn after the
#   failure — the SET turn's own tick doesn't count, matching
#   Retaliate's identical counter-of-2 shape and for the identical
#   underlying reason). Source: battle_util.c, case
#   EFFECT_STOMPING_TANTRUM (L6416-6418); set-sites
#   battle_move_resolution.c L1263-1265 (Protect-family-adjacent failure
#   paths) and L4248-4249 (`ShouldSetStompingTantrumTimer`, the general
#   failure/miss/no-effect gate); decrement battle_main.c L3933-3934
#   (the same per-battler action-reset function `stompingTantrumTimer`
#   and `retaliateTimer` both live in).
@export var is_stomping_tantrum: bool = false

# EFFECT_DOUBLE_POWER_ON_ARG_STATUS cluster (D1's last structured cluster) —
#   Hex(506)/Infernal Parade(772)/Venoshock(474)/Barb Barrage(767)/Smelling
#   Salts(265). Power doubles if the DEFENDER's status (checked at
#   power-computation time, strictly BEFORE this same hit's own accuracy
#   roll or any of its own secondary effects can apply a NEW status — by
#   construction of this project's pipeline, `_dmg_power_override` is
#   computed in `_phase_move_execution` before `_do_damaging_hit` runs at
#   all, matching source's own base-power-then-additionalEffects ordering)
#   matches `double_power_status_arg`. Comatose holders are treated as
#   having STATUS1_SLEEP for this check specifically, even though this
#   project's Comatose implementation (`[M17n-11]`) never actually sets a
#   real status — a real, source-confirmed proxy (see
#   `BattleManager._status_matches_double_power_arg`'s own doc comment).
#   Source: battle_util.c, case EFFECT_DOUBLE_POWER_ON_ARG_STATUS
#   (L6186-6191).
#
# is_double_power_on_status: gates the dispatch itself.
@export var is_double_power_on_status: bool = false

# double_power_status_arg: either a specific `BattlePokemon.STATUS_*` value
#   (Smelling Salts: STATUS_PARALYSIS only), or one of the two sentinels
#   below (Venoshock/Barb Barrage: STATUS_ARG_POISON_ANY; Hex/Infernal
#   Parade: STATUS_ARG_ANY) — mirrors source's `argument.status` field,
#   which is itself a bitmask (`STATUS1_PSN_ANY`/`STATUS1_ANY`) this
#   project's own single-value (not bitmask) status representation can't
#   directly copy, hence the sentinel approach. -1 = N/A (default, no
#   dispatch).
const STATUS_ARG_POISON_ANY: int = -2
const STATUS_ARG_ANY: int = -3
@export var double_power_status_arg: int = -1

# is_smelling_salts: Smelling Salts(265) ALSO cures the target's paralysis
#   on hit — a genuine two-mechanism composite, not pure reuse of Hex/
#   Venoshock's single mechanism (confirmed at Step 0, matching Barb
#   Barrage/Infernal Parade's own composite shape below, though via a
#   different second mechanism). Dispatched post-hit (`damage > 0`),
#   mirroring `is_sparkling_aria`'s exact shape/insertion point — "cure a
#   status FROM the target" still has no generic SE_* token, so this is
#   its own dedicated flag rather than a generalized mechanism, matching
#   that established precedent rather than building a second one.
#   A real, Smelling-Salts-only exception found at Step 0: source's OWN
#   power-double check (not just the cure) is suppressed if the hit would
#   be blocked by a live Substitute the move doesn't ignore — i.e. this is
#   the one move in the cluster where the power-double and the secondary
#   effect are coupled, not independent. Modeled in the same
#   `_dmg_power_override` block as the double itself (checking
#   `defender.substitute_hp > 0 and not move.ignores_substitute`), NOT as
#   a separate gate on the post-hit cure — the cure's own post-hit
#   dispatch is naturally already exempt from firing against a live,
#   non-ignored Substitute, since `_do_damaging_hit` only reaches this
#   project's post-hit dispatch block with `damage > 0` when the hit
#   landed on the real Pokémon, not an absorbing Substitute.
#   Source: src/battle_script_commands.c :: case MOVE_EFFECT_REMOVE_STATUS
#   (L3270-3289, the same generic effect `is_sparkling_aria`'s own doc
#   comment cites); the Substitute exception is battle_util.c L6188-6190,
#   part of the same EFFECT_DOUBLE_POWER_ON_ARG_STATUS case cited above.
@export var is_smelling_salts: bool = false

# [D4 bundle] is_sleep_talk: Sleep Talk(214) — reassigns `move` to a random
#   move from the ATTACKER's OWN moveset, reusing the exact "duplicate/
#   substitute `move`, fall through" insertion point Mirror Move/Metronome
#   already established (source confirms EFFECT_METRONOME/EFFECT_ASSIST/
#   EFFECT_NATURE_POWER/EFFECT_SLEEP_TALK/EFFECT_COPYCAT/EFFECT_ME_FIRST all
#   live in the SAME `calledMove = Get*Move()` switch,
#   battle_move_resolution.c L529-552). Excludes moves via
#   `ban_flags & BAN_SLEEP_TALK` AND `move.two_turn` (source:
#   `IsMoveSleepTalkBanned(...) || gBattleMoveEffects[...].twoTurnEffect`,
#   battle_move_resolution.c L5098-5111) — genuinely bypasses PP=0 and
#   choice-lock exclusions (`CheckMoveLimitations(..., ~(MOVE_LIMITATION_PP
#   | MOVE_LIMITATION_CHOICE_ITEM))`), which this project's flat
#   pool-scan-over-`attacker.moves` satisfies for free (no PP/choice-lock
#   filtering exists in that scan to begin with). The called move is PP-free
#   (PP deduction already happened against Sleep Talk's OWN slot before this
#   reassignment point is ever reached, same as Metronome's already-shipped
#   precedent). Source: battle_move_resolution.c, case EFFECT_SLEEP_TALK
#   (L546-548); GetSleepTalkMove (L5098-5127).
@export var is_sleep_talk: bool = false

# [D4 bundle] usable_while_asleep: a genuinely NEW small mechanism (not
#   previously built anywhere in this project) — Sleep Talk is the ONE move
#   in this session carrying it; Snore(173, not yet implemented) would be
#   the only other real-game holder. Lets `StatusManager.pre_move_check`'s
#   sleep block permit the move to execute WHILE STILL ASLEEP, instead of
#   the normal "stays asleep → can't move" block. Checked against the
#   ALREADY-CHOSEN move for this turn (Sleep Talk itself, before its own
#   later move-reassignment happens) — matches source's
#   `IsUsableWhileAsleepEffect(moveEffect)`, checked against the mon's own
#   chosen move's effect, not whatever it ends up calling.
#   Source: battle_util.c :: IsUsableWhileAsleepEffect (L10713-10723).
@export var usable_while_asleep: bool = false

# [D4 bundle] is_taunt: Taunt(269) — blocks the TARGET from selecting/
#   executing any STATUS-category move (`move.category == 2`) for a
#   duration, via a new `BattlePokemon.taunt_turns` counter reusing the
#   EXACT Disable/Encore/Throat-Chop turn-counter-volatile shape (checked
#   at EXECUTION time in `_phase_move_execution`'s early "chosen, then
#   fails" block, right alongside Assault Vest's own identical
#   status-category check — NOT a menu-selection-time filter, this project
#   has no such architecture). This means a status move ALREADY QUEUED for
#   this same turn IS still blocked if Taunt lands before it resolves,
#   matching source's own canceler-chain (execution-time) check exactly —
#   confirmed via source, not assumed. Duration is genuinely conditional,
#   NOT a flat constant: 4 turns if the target has ALREADY acted this turn
#   when hit, 3 turns if not (reuses the exact `_turn_order.find(...) <=
#   _current_actor_index` "has this mon acted yet" check `is_helping_hand`'s
#   own ally-already-moved gate already established). Blocked by Aroma Veil
#   (reuses the existing `blocked_by_aroma_veil`-adjacent check already
#   wired for Disable/Torment) and by Oblivious
#   (`B_OBLIVIOUS_TAUNT >= GEN_6`, `[M17n-1]`'s own precedent). `bounceable
#   = true` at this project's GEN_LATEST config (`magicCoatAffected =
#   B_UPDATED_MOVE_FLAGS >= GEN_5`) — reflectable by both Magic Bounce and
#   this same bundle's own Magic Coat.
#   Source: battle_util.c L1360-1380 (the block check); battle_script_
#   commands.c :: Cmd_settaunt (L8815-8845, infliction + duration formula).
@export var is_taunt: bool = false

# [D4 bundle] is_assurance: Assurance(372) — power doubles if the TARGET
#   was already hit THIS TURN by ANYONE, not specifically by the user —
#   confirmed a genuinely different trigger scope from Revenge's own
#   per-(victim,attacker)-PAIR semantic despite sharing the same underlying
#   tracker: source's `assuranceDoubled` is set on whichever battler took
#   ANY damage this turn (battle_script_commands.c L1562/L1657,
#   battle_util.c L8013), matching this project's own
#   `BattlePokemon.hit_by_this_turn` (built for Revenge, `[D1 easy
#   bundle]`) — `not defender.hit_by_this_turn.is_empty()` answers the
#   whole condition directly, zero new state needed.
#   Source: battle_util.c, case EFFECT_ASSURANCE (L6196-6198).
@export var is_assurance: bool = false

# [D4 bundle] is_magic_coat: Magic Coat(277) — a temporary, move-granted
#   version of Magic Bounce's own ability (`[M17n-9]`), confirmed via direct
#   source read to share the EXACT SAME dispatch chain
#   (`return TryMagicBounce(cv) || TryMagicCoat(cv);`,
#   battle_move_resolution.c L5157) — reflects the first foe-targeting
#   `move.bounceable` status move used against the user back at its own
#   user, for the rest of this same turn only. Sets a new
#   `BattlePokemon.magic_coat_active` volatile (self-targeted, matching
#   Protect's own single-turn-only shape — cleared every turn in
#   `_phase_priority_resolution`'s existing reset loop) consumed by
#   extending the EXISTING Magic Bounce swap condition
#   (`battle_manager.gd` ~L3106) with an OR, rather than a second parallel
#   swap — inherits that swap's already-tested "single non-recursive
#   bounce, even Magic-Bounce-vs-Magic-Bounce" guarantee for free, verified
#   by tracing source's own `MoveEndBouncedMove` bounce loop (never
#   re-checks pending-bounce state after a swap already fired). Cleared
#   immediately after firing so it can't reflect a SECOND status move later
#   the same turn. Priority +4, `ignoresProtect = TRUE`,
#   `mirrorMoveBanned = TRUE`.
#   Source: src/data/moves_info.h MOVE_MAGIC_COAT; src/battle_move_
#   resolution.c :: TryMagicCoat (L5175-5191), MoveEndBouncedMove
#   (L3142-3195).
@export var is_magic_coat: bool = false

# [D4 CHEAP bundle] requires_target_asleep: Dream Eater(138) — fails
#   OUTRIGHT (zero damage, not merely "skip the drain") against a
#   non-sleeping, non-Comatose target, confirmed via direct source read of
#   the move's own battle script rather than assumed: `jumpifstatus
#   BS_TARGET, STATUS1_SLEEP, BattleScript_HitFromAccCheck` /
#   `jumpifability BS_TARGET, ABILITY_COMATOSE, BattleScript_HitFromAccCheck`
#   / else `goto BattleScript_DoesntAffectTargetAtkString` — checked BEFORE
#   the accuracy roll, so a failure here never rolls accuracy at all.
#   Drain itself reuses the EXISTING generic `drain_percent` field (50%),
#   confirmed via source to be the SAME `EFFECT_ABSORB`/`EFFECT_DREAM_EATER`
#   shared drain-application chokepoint this project's Absorb/Mega Drain/
#   Giga Drain family already occupies (battle_move_resolution.c L2636) —
#   NOT the Volt Absorb/Water Absorb absorb-ability family the task's own
#   framing suggested checking; a real, source-verified correction, not an
#   assumption. Both `B_DREAM_EATER_LIQUID_OOZE` and `B_DREAM_EATER_
#   SUBSTITUTE` resolve to their GEN_5+ branches at this project's
#   GEN_LATEST config, meaning Liquid Ooze inversion and ordinary
#   Substitute-absorption BOTH already apply for free via that same shared
#   chokepoint and this project's general `went_to_sub` handling — no
#   extra code needed for either.
#   Source: data/battle_scripts_1.s :: BattleScript_EffectDreamEater
#   (L1614-1624); include/config/battle.h L149-150.
@export var requires_target_asleep: bool = false

# [D4 CHEAP bundle] is_torment: Torment(259) — see BattlePokemon.tormented's
#   own doc comment for the full mechanism (permanent target-side move-block,
#   reusing Blood Moon's cant_use_twice SHAPE but target- not self-inflicted).
#   This move's own infliction dispatch: fails if the target is already
#   tormented (Cmd_settorment's own already-true fail case) or blocked by
#   Aroma Veil (self OR ally) — reuses the existing `blocked_by_aroma_veil`
#   gate Disable/Encore/Taunt already established. `magicCoatAffected = TRUE`
#   at this project's GEN_LATEST config (bounceable via the existing Magic
#   Bounce/Magic Coat swap). Blocked by Substitute (no `ignoresSubstitute`
#   flag in source).
#   Source: data/moves_info.h MOVE_TORMENT (.magicCoatAffected =
#   B_UPDATED_MOVE_FLAGS >= GEN_5); data/battle_scripts_1.s ::
#   BattleScript_EffectTorment (L2453-2462); battle_script_commands.c ::
#   Cmd_settorment (L8795-8809).
@export var is_torment: bool = false

# [D4 CHEAP bundle] is_gyro_ball: Gyro Ball(360) — power from the speed
#   RATIO of target-to-user, reading each side's CURRENT effective speed
#   (post-stat-stage, post-Paralysis-halving/Quick-Feet-replacement,
#   post-weather-ability, post-item — StatusManager.effective_speed, the
#   same accessor turn-order sorting itself uses), NOT base speed — a
#   real Step-0 confirmation, not an assumption. Formula (confirmed via
#   direct source read, not folklore): `((25 * targetSpeed) / userSpeed) +
#   1`, capped at 150; userSpeed == 0 short-circuits to a flat power of 1
#   (division-by-zero guard, not part of the capped formula).
#   Source: battle_util.c, case EFFECT_GYRO_BALL (L6249-6263).
@export var is_gyro_ball: bool = false

# [D4 CHEAP bundle] is_electro_ball: Electro Ball(486) — CONFIRMED a
#   genuinely different, STEPPED/BANDED formula from Gyro Ball's continuous
#   one, not "same family, mirrored direction" (the exact assumption this
#   task's own prompt warned against) — re-derived directly from source
#   rather than trusted. Ratio = floor(userSpeed / targetSpeed) (the
#   INVERSE ratio direction from Gyro Ball — user-to-target, not
#   target-to-user), indexed directly (capped at the table's last index)
#   into a fixed table: ratio 0 → 40, 1 → 60, 2 → 80, 3 → 120, 4+ → 150.
#   Both sides read the same CURRENT effective speed accessor Gyro Ball
#   uses (StatusManager.effective_speed).
#   Source: battle_util.c, case EFFECT_ELECTRO_BALL (L6243-6248);
#   sSpeedDiffPowerTable (L6032): {40, 60, 80, 120, 150}.
@export var is_electro_ball: bool = false

# [D4 CHEAP bundle] is_snore: Snore(173) — a genuinely different shape from
#   Dream Eater's requires_target_asleep above: Snore has NO fail-if-not-
#   asleep gate of its own at all (confirmed via source — no dedicated
#   BattleScript_EffectSnore exists; it dispatches through the plain
#   generic EFFECT_HIT damaging-move script with a MOVE_EFFECT_FLINCH
#   secondary, identical in SHAPE to any other damage+flinch move). Its
#   ONLY special behavior is reusing the EXISTING `usable_while_asleep`
#   mechanism (Sleep Talk's own precedent, `[D4 bundle]`'s first session)
#   to bypass `StatusManager.pre_move_check`'s normal "stays asleep, can't
#   move" block — if used while genuinely awake, Snore behaves exactly like
#   an ordinary Normal-type special attack with a 30% flinch chance, no
#   restriction and no failure. Power 50 at this project's GEN_LATEST
#   config (`B_UPDATED_MOVE_DATA >= GEN_6`), `ignoresSubstitute = TRUE`
#   also at GEN_LATEST — reuses the existing generic `ignores_substitute`
#   field. `usable_while_asleep` itself already carries its own doc comment
#   citing `IsUsableWhileAsleepEffect` (battle_util.c L10714-10723), which
#   lists EFFECT_SNORE alongside EFFECT_SLEEP_TALK — confirmed the SAME
#   gate covers both moves, no new mechanism needed.
@export var is_snore: bool = false

# [D4 CHEAP bundle] is_endure: Endure(203) — dispatches through the LITERAL
#   SAME script AND `Cmd_setprotectlike` command as Protect/Detect
#   (`BattleScript_EffectProtect` and `BattleScript_EffectEndure` are the
#   same label), confirmed via direct source read — but `Cmd_setprotectlike`
#   ITSELF branches internally: `if (GetMoveEffect(gCurrentMove) ==
#   EFFECT_ENDURE)` sets ONLY `volatiles.endured = TRUE`, completely
#   bypassing `gProtectStructs[].protected` (this project's `protect_active`/
#   `protect_method`) — a real correction to this move's own first-draft
#   plan (which assumed Endure would reuse `protect_active` with an
#   `_is_protected_from` bypass case; that approach is NOT what source does
#   and was abandoned before implementing). Set `is_protect = TRUE` and
#   `protect_method = PROTECT_METHOD_ENDURE` — the is_protect dispatch
#   itself branches on this exact tag to set the SEPARATE
#   `BattlePokemon.endure_active` field instead of `protect_active`, so
#   Endure correctly never blocks the incoming hit, while still sharing the
#   SAME per-battler consecutive-use fail-chance ramp (`protect_consecutive`)
#   every other Protect-family move uses (source's own
#   `volatiles.consecutiveMoveUses++` is unconditional regardless of which
#   branch fires). The survive-lethal-hit chain in `_do_damaging_hit` checks
#   `endure_active` FIRST, before Sturdy, matching source's real priority
#   order (Endure → False Swipe → Sturdy → Focus Band → Focus Sash — this
#   bundle has no False Swipe(206), so only the Endure/Sturdy ordering is
#   newly relevant).
#   Source: data/battle_scripts_1.s L2146-2154; battle_script_commands.c ::
#   Cmd_setprotectlike (L6934-6957); battle_util.c L7962-7984 (the shared
#   survive-a-lethal-hit priority chain).
# (No new @export needed beyond is_protect/protect_method, both pre-existing.)

# [D4 CHEAP bundle] is_fell_stinger: Fell Stinger(390) — MoveEnd-phase
#   check: if the attacker's own hit (unabsorbed by Substitute) just KO'd
#   the defender this turn, raise the attacker's OWN Attack by 3 stages
#   (`B_FELL_STINGER_STAT_RAISE >= GEN_7` at this project's GEN_LATEST
#   config — NOT the Gen<7 value of 2, confirmed via source rather than
#   assumed a flat +1/+2 shape). Mirrors `AbilityManager.moxie_boost`'s own
#   shape (killer-lookup via `_last_attacker`/now also `_last_attacker_move`,
#   both already tracked at the same `_do_damaging_hit` chokepoint), checked
#   at the SAME `_phase_faint_check` insertion point Moxie already occupies
#   — already-maxed Attack is a natural no-op via the existing
#   `StatusManager.apply_stat_change` clamp, no explicit guard needed.
#   Source: battle_move_resolution.c, case EFFECT_FELL_STINGER
#   (L3579-3591); include/constants/config_changes.h L82.
@export var is_fell_stinger: bool = false

# [D4 CHEAP bundle] is_magnet_rise: Magnet Rise(506) — see BattlePokemon.
#   magnet_rise_turns's own doc comment for the full mechanism. Fails if the
#   user already has Magnet Rise, Ingrain, or Smack Down active.
@export var is_magnet_rise: bool = false

# [D4 CHEAP bundle] is_smack_down: Smack Down(479) — see BattlePokemon.
#   smack_down_active's own doc comment for the full mechanism. A
#   MoveEnd-phase secondary on a damaging hit (power 50, Rock-type,
#   Physical), gated on the hit actually connecting (unabsorbed by
#   Substitute) and the target still being alive. `damagesAirborne = TRUE`
#   reuses the EXISTING generic field (Gust/Twister/Thunder's own
#   precedent) to hit a Flying-semi-invulnerable target mid-Fly.
#   Source: battle_move_resolution.c, case EFFECT_SMACK_DOWN (L3547-3570).
@export var is_smack_down: bool = false

# [D4 CHEAP bundle] is_ingrain: Ingrain(182) — see BattlePokemon.
#   ingrain_active's own doc comment for the full 3-piece composite
#   mechanism (self-heal / self-ground / switch-block, both voluntary and
#   forced). Fails if the user is already rooted.
@export var is_ingrain: bool = false

# [D4 CHEAP bundle] is_aqua_ring: Aqua Ring(392) — see BattlePokemon.
#   aqua_ring_active's own doc comment for the full mechanism (end-of-turn
#   self-heal only, no grounding/switch-block component). Fails if the
#   user already has Aqua Ring active.
@export var is_aqua_ring: bool = false

# [D4 CHEAP bundle] is_payback: Payback(371) — power doubles if the TARGET
#   has already acted this turn (reuses the EXISTING `_has_target_already_
#   acted` position-tracking helper, `[M18j]` Zoom Lens's own precedent)
#   AND the target did NOT just switch in this turn (reuses the EXISTING
#   `switched_in_this_turn` flag, `[D1 easy bundle]` Fake Out's own
#   precedent) — confirmed via source this project's GEN_LATEST config
#   resolves `B_PAYBACK_SWITCH_BOOST >= GEN_5`, meaning a target that just
#   switched in does NOT count as "already acted" for Payback's own
#   doubling purposes even though switching in DOES set the general
#   turn-position tracking, a genuinely conditional (not flat "target
#   already moved") formula — re-derived from source rather than assumed.
#   Source: battle_util.c, case EFFECT_PAYBACK (L6273-6283);
#   include/config/battle.h L32.
@export var is_payback: bool = false

# [D4 bundle 3] is_do_nothing: Splash(150) — EFFECT_DO_NOTHING, confirmed
#   via source to genuinely do nothing beyond the animation/message (no
#   hidden gotcha, unlike several other seemingly-trivial moves this arc
#   has found real wrinkles on).
#   Source: data/battle_scripts_1.s :: BattleScript_EffectDoNothing (L1945-1952).
@export var is_do_nothing: bool = false

# [D4 bundle 3] is_refresh: Refresh(287) — cures the USER's own status, but
#   a REAL correction to a naive "cures any status" assumption: source's
#   `Cmd_curestatuswithmove` gates on `STATUS1_CAN_MOVE = POISON | BURN |
#   PARALYSIS | TOXIC_POISON | FROSTBITE` — explicitly EXCLUDES Sleep and
#   Freeze (the move's own flavor text — "heals poisoning, paralysis, or a
#   burn" — is literal, not incomplete). Fails if the user has none of
#   those specific statuses (Sleep/Freeze/no-status all fail identically).
#   Source: battle_script_commands.c :: Cmd_curestatuswithmove (L8758-8790);
#   include/constants/battle.h L196 (STATUS1_CAN_MOVE).
@export var is_refresh: bool = false

# [D4 bundle 3] is_purify: Purify(648) — cures the TARGET's status (ANY
#   status, unlike Refresh's narrower scope), fails OUTRIGHT with no cure
#   attempt at all if the target has no status at all
#   (`jumpifstatus BS_TARGET, STATUS1_ANY, ... else ButItFailed`). Only if
#   the cure actually happens does it THEN attempt a separate half-HP
#   self-heal on the ATTACKER — confirmed via source this heal is
#   genuinely conditional on the cure having occurred, not an independent
#   unconditional attempt (a real Step-0 confirmation, not an assumption).
#   `healingMove = TRUE` (Triage-eligible), `magicCoatAffected = TRUE`
#   (bounceable).
#   Source: data/battle_scripts_1.s :: BattleScript_EffectPurify (L771-783).
@export var is_purify: bool = false

# [D4 bundle 3] is_memento: Memento(262) — self-faint + -2/-2 Atk/SpAtk to
#   the target. Confirmed via source the STAT-DROP applies BEFORE the
#   self-faint (`trymovestatchanges` then `tryfaintmon`, in that order).
#   The stat-drop itself is gated by the SAME accuracy/Substitute/type-
#   immunity checks every other targeted status move already gets in this
#   project's shared foe_targeting block (a miss/Substitute/immunity
#   blocks the stat-drop) — but the self-faint is UNCONDITIONAL, since
#   Substitute protects the TARGET from a move's effects, not the
#   ATTACKER from its own move's self-consequence. Matches this move's
#   own well-established real-game behavior: the user always faints from
#   Memento, even when the stat-drop is itself blocked or prevented.
#   Source: data/battle_scripts_1.s :: BattleScript_EffectMemento (L117-121);
#   moves_info.h MOVE_MEMENTO's own additionalEffects (STAT_CHANGE_EFFECT_MINUS,
#   attack=2, spAtk=2).
@export var is_memento: bool = false

# [D4 bundle 3] hp_cost_stat_boost / hp_cost_divisor: the shared shape for
#   Belly Drum(187)/Fillet Away(796)/Clangorous Soul(703) — "pay HP, get a
#   stat boost." Confirmed genuinely NON-symmetric across the three despite
#   the shared shape (per this project's own standing convention of never
#   assuming symmetry within a family): all three gate on
#   `WillAnyStatChange() && Try*Hp(...)` — an AND, so the move hard-fails
#   with ZERO HP cost AND zero stat change unless BOTH the stat change
#   would do something AND the HP payment can be made (current_hp STRICTLY
#   greater than the fraction, not >=) — confirmed NOT "always pay HP,
#   sometimes no boost." Belly Drum's own `TryBellyDrum` has an EXTRA
#   Attack-specific `CompareStat(== MAX_STAGE)` pre-check (moot for the
#   other two, which are multi-stat and use a generic ability-prevention
#   flag instead — itself moot here since Clear-Body-style abilities only
#   block DECREASES, never self-targeted increases). Belly Drum's own
#   Attack delta is encoded as `STAT_CHANGE_FORCE_MAX` (=12 internally, NOT
#   a literal "set to +6") — composes correctly with Contrary/Simple via
#   this project's EXISTING generic stage-modifier pipeline for free, so
#   it's represented here as a plain `stat_change_amount = 12`, no new
#   mechanism needed. `hp_cost_divisor` is 2 for Belly Drum/Fillet Away
#   (half HP) and 3 for Clangorous Soul (a third).
#   Source: battle_move_resolution.c, cases EFFECT_BELLY_DRUM/
#   EFFECT_STAT_CHANGE_HALF_HP/EFFECT_CLANGOROUS_SOUL (L4696-4731);
#   TryBellyDrum/TryHalfHp/CutThirdOfHp (L5272-5327);
#   include/move.h L13 (STAT_CHANGE_FORCE_MAX).
@export var hp_cost_stat_boost: bool = false
@export var hp_cost_divisor: int = 0

# [D4 bundle 3] is_nightmare: Nightmare(171) — reuses Dream Eater's own
#   sleep/Comatose gate for infliction (fails if the target isn't asleep,
#   fails if already nightmared). Does NOT ignore Protect (a real
#   correction — `.ignoresProtect = B_UPDATED_MOVE_FLAGS < GEN_3` resolves
#   FALSE at this project's GEN_LATEST config, unlike most of this
#   bundle's self-targeted moves), and IS blocked by Substitute (no
#   ignoresSubstitute flag). See BattlePokemon.nightmare_active's own doc
#   comment for the recurring end-of-turn tick, which re-checks sleep
#   status EVERY turn rather than only at application.
#   Source: data/battle_scripts_1.s :: BattleScript_EffectNightmare
#   (L2114-2121); battle_end_turn.c :: HandleEndTurnNightmare (L610-633).
@export var is_nightmare: bool = false

# [D4 bundle 3] is_spite: Spite(180) — reduces the target's LAST-USED
#   move's PP by a flat 4 (this project's GEN_LATEST config), floored at 0.
#   Fails if the target has no last-used move (`last_move_used == null`),
#   if that move can no longer be found in the target's own moveset, or if
#   its PP is already 0. Confirmed no special "just switched in" edge case
#   is needed beyond what already exists: `last_move_used` is already
#   cleared on switch-out by `_switch_out_clear`, so a freshly-switched-in
#   target naturally reads null and correctly fails for free — the same
#   shape Payback's own switched-in exemption needed a DEDICATED flag for,
#   but Spite gets it automatically here. Ignores Substitute (own flag),
#   bounceable (`magicCoatAffected` at GEN5+).
#   Source: battle_script_commands.c :: Cmd_tryspiteppreduce (L8190-8250).
@export var is_spite: bool = false

# [D4 bundle 3] is_recycle: Recycle(278) — a REAL correction to an
#   initially-proposed reuse: restores `BattlePokemon.last_used_item`, a
#   NEW field genuinely BROADER than `last_consumed_berry` (Harvest/Cud
#   Chew's own berry-only tracker) — source's own `usedHeldItem` is set at
#   the SAME general item-removal chokepoint this project's `_consume_item`
#   already represents, for ANY item (berry or not), confirmed via direct
#   source read of `Cmd_removeitem`. Fails if nothing was ever consumed, or
#   if the user currently holds an item already. Source explicitly excludes
#   a popped Air Balloon from ever being remembered ("cannot be restored by
#   any means") — replicated since this project's own Air Balloon pop also
#   routes through `_consume_item`.
#   Source: battle_script_commands.c :: Cmd_tryrecycleitem (L9577-9603),
#   Cmd_removeitem (L6192-6224).
@export var is_recycle: bool = false

# [D4 bundle 3] is_facade: Facade(263) — doubles power if the user has
#   Burn/Poison/Toxic/Paralysis (confirmed NOT Sleep/Freeze, matching Guts'
#   own list minus Frostbite, which this project doesn't have). Also
#   bypasses burn's own Attack-halving — confirmed via source
#   (`GetBurnOrFrostBiteModifier`) this is a GENUINELY SEPARATE, independent
#   exemption from Guts', not conditioned on the doubling or on having
#   Guts (`B_BURN_FACADE_DMG >= GEN_6`, true at this project's GEN_LATEST
#   config, unconditionally skips the burn-halving check for this move).
#   Status is read live at hit-resolution time, no turn-start snapshot —
#   no same-turn-cure edge case exists.
#   Source: battle_util.c, case EFFECT_FACADE (L6393-6396);
#   GetBurnOrFrostBiteModifier (L7278-7292).
@export var is_facade: bool = false

# [D4 bundle 3] is_take_heart: Take Heart(778) — cures the USER's own
#   status (ANY status, matching Purify's scope not Refresh's narrower
#   one) AND raises Attack + Sp.Atk by 1 each — a REAL correction: this
#   project's own first-draft proposal assumed Sp.Atk/Sp.Def from general
#   series knowledge, but this reference's own data table
#   (moves_info.h MOVE_TAKE_HEART) explicitly encodes `attack=1, spAtk=1`,
#   confirmed via direct source read rather than trusted from memory. Gate
#   is `WillAnyStatChange() OR status1 != 0` — an OR, so it still succeeds
#   and cures status even when both stages are already at +6 (unlike the
#   HP-cost family's own AND-gated fail condition just above).
#   Source: battle_move_resolution.c, case EFFECT_TAKE_HEART (L4653-4680).
@export var is_take_heart: bool = false
