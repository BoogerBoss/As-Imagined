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
@export var strike_count: int = 1   # number of hits; defaults to 1
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
@export var healing_move: bool = false
@export var ignores_protect: bool = false
@export var ignores_substitute: bool = false
@export var thaws_user: bool = false
@export var critical_hit_stage: int = 0   # 0–3; added to base crit stage
@export var always_critical_hit: bool = false

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

@export var secondary_effect: int = 0   # SE_* constant above
@export var secondary_chance: int = 0   # 0 = guaranteed; 1–100 = % roll

# ── Stat change effect ──────────────────────────────────────────────────────
# Source: src/data/moves_info.h :: additionalEffects → STAT_CHANGE_EFFECT_PLUS/MINUS
# stat_change_stat: -1 = no stat change; else BattlePokemon.STAGE_* index.
# stat_change_amount: positive = raise, negative = lower (e.g. +2 for Swords Dance, -1 for Growl).
# stat_change_self: true = applies to the attacker (Swords Dance); false = applies to the opponent.
@export var stat_change_stat: int = -1
@export var stat_change_amount: int = 0
@export var stat_change_self: bool = false

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
