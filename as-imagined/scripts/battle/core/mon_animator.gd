class_name MonAnimator
extends RefCounted

# [M26B3-6c-1] Per-species BACK-sprite entry animation -- the left/right
# motion the player's own Pokemon makes while it is still pink, the instant
# it finishes emerging from its ball.
#
# Source: reference/pokeemerald_expansion/src/pokemon_animation.c, dispatched
# by `BattleAnimateBackSprite` (src/pokemon.c:5761), whose only battle call
# site is `SpriteCB_PlayerMonFromBall` (src/battle_main.c:2905).
#
# This class is deliberately a PURE state machine with zero scene/node
# dependencies -- `start()` seeds a state Dictionary, `step()` advances it
# exactly one GBA frame, and the three `godot_*` helpers convert the
# resulting GBA-space values into Godot-space ones. That keeps every motion
# unit-testable without a SceneTree, which matters more than usual here:
# this arc's own history is that the suite catches wrong VALUES while being
# blind to whether the motion looks right, so the values are what get
# tested and the look is what gets screenshotted.
#
# ---------------------------------------------------------------------
# THE NATURE DEPENDENCY -- easy to miss, and not in this item's own
# original roadmap sketch.
#
# `.backAnimId` does NOT name an animation. It names a SET of three, and
# which of the three plays depends on the Pokemon's NATURE:
#
#     animId = 3 * backAnimSet + gNaturesInfo[nature].backAnim
#         -- LaunchAnimationTaskForBackSprite, pokemon_animation.c:550-566
#
# `gNaturesInfo[].backAnim` is 0, 1 or 2 (pokemon.c:152+), distributed
# 8/9/8 across the 25 natures. So two Bulbasaur with different natures
# genuinely play different entry animations. This project has had real
# natures since [M18.5h-1], so this is reproduced rather than flattened.
#
# ---------------------------------------------------------------------
# TryFlipX IS A NO-OP HERE -- resolved from source, not guessed.
#
# Many of these functions bracket their body in `TryFlipX(sprite)`, which
# is `if (!sprite->sDontFlip) sprite->x2 *= -1;`. The naming reads
# backwards, so it is worth stating plainly: `Task_HandleMonAnimation`
# sets `sprite->sDontFlip = TRUE` explicitly at its state-0 setup, for
# BOTH the front and back battle paths. sDontFlip is only ever FALSE on
# the Summary Screen (`StartMonSummaryAnimation`'s own comment:
# "sDontFlip is expected to still be FALSE here, not explicitly cleared").
#
# Therefore, in battle:
#   - TryFlipX never negates x2                -> omitted entirely
#   - HandleSetAffineData never negates        -> == SetAffineData
#   - the three `if (!sDontFlip) ... else ...` scale branches inside
#     GrowStutter / HorizontalStretchFar / VerticalStretchBothEnds all
#     take the ELSE (`256 - ...`) form.
#
# This was flagged as an open screenshot question when B3-6c was scoped;
# it is closed here from source instead. Do not "fix" a sign back in.
#
# ---------------------------------------------------------------------
# GBA AFFINE SCALE IS INVERTED. 256 is identity, and a SMALLER value is a
# BIGGER sprite (the matrix maps screen->texture, not texture->screen).
# `godot_scale()` does the 256.0/value inversion in one place; the motion
# functions below store raw source values, so they read like source.
# Same inversion [M26B3-6a] already documented for the recall shrink.

# --- GBA frame timing -------------------------------------------------
# Source is 60fps-locked. Everything here steps in whole GBA frames; the
# CALLER owns the wall-clock accumulator (see `MonAnimator.Clock` below),
# so a 144Hz or 30Hz display advances the same number of frames per real
# second. That is the accumulator-based animation clock M26G4's own audit
# proposed as the fix for the discrete 1/60s steppers B3-6a/6b shipped --
# building it here retires that recommendation rather than leaving it for
# the polish pass.
const GBA_FRAME_SECONDS: float = 1.0 / 60.0

# --- Amplitude scaling ------------------------------------------------
# Source amplitudes are GBA pixels against a 240x160 screen; this project
# draws battle sprites at 4x. A literal 4x is the source-faithful figure
# and the default here.
#
# THIS IS THE TUNABLE. B3-6b already has direct evidence that a
# source-exact amplitude can read badly at 4x: the fly-out swing was
# ported exactly, measured a 181px diagonal lurch, and Rob reverted it.
# If these animations read as too violent, lower this ONE constant rather
# than editing individual motions -- every offset routes through it.
const AMPLITUDE_SCALE: float = 4.0

# --- enum BackAnim (include/pokemon_animation.h:5-32) -----------------
const BACK_ANIM_NONE := 0
const BACK_ANIM_H_VIBRATE := 1
const BACK_ANIM_H_SLIDE := 2
const BACK_ANIM_H_SPRING := 3
const BACK_ANIM_H_SPRING_REPEATED := 4
const BACK_ANIM_SHRINK_GROW := 5
const BACK_ANIM_GROW := 6
const BACK_ANIM_CIRCLE_COUNTERCLOCKWISE := 7
const BACK_ANIM_H_SHAKE := 8
const BACK_ANIM_V_SHAKE := 9
const BACK_ANIM_V_SHAKE_H_SLIDE := 10
const BACK_ANIM_V_STRETCH := 11
const BACK_ANIM_H_STRETCH := 12
const BACK_ANIM_GROW_STUTTER := 13
const BACK_ANIM_V_SHAKE_LOW := 14
const BACK_ANIM_TRIANGLE_DOWN := 15
const BACK_ANIM_CONCAVE_ARC_LARGE := 16
const BACK_ANIM_CONVEX_DOUBLE_ARC := 17
const BACK_ANIM_CONCAVE_ARC_SMALL := 18
const BACK_ANIM_DIP_RIGHT_SIDE := 19
const BACK_ANIM_SHRINK_GROW_VIBRATE := 20
const BACK_ANIM_JOLT_RIGHT := 21
const BACK_ANIM_SHAKE_FLASH_YELLOW := 22
const BACK_ANIM_SHAKE_GLOW_RED := 23
const BACK_ANIM_SHAKE_GLOW_GREEN := 24
const BACK_ANIM_SHAKE_GLOW_BLUE := 25

const BACK_ANIM_COUNT := 26

# --- gNaturesInfo[].backAnim (src/pokemon.c:152+) ---------------------
# Indexed by this project's own NATURE_* ids, which are in source's own
# enum order (BattlePokemon.NATURE_HARDY == 0 == source's NATURE_HARDY).
# Distribution is 8x variant 0, 9x variant 1, 8x variant 2.

# Declared as a plain `const Array` rather than a PackedByteArray: a
# `PackedByteArray([...])` initialiser is a constructor CALL, which
# GDScript rejects in a `const` ("isn't a constant expression"). Same for
# SINE_TABLE below. A plain array literal is a real constant expression.
const NATURE_BACK_VARIANT: Array = [
	0, # HARDY
	2, # LONELY
	0, # BRAVE
	0, # ADAMANT
	0, # NAUGHTY
	1, # BOLD
	1, # DOCILE
	1, # RELAXED
	0, # IMPISH
	1, # LAX
	2, # TIMID
	0, # HASTY
	1, # SERIOUS
	0, # JOLLY
	0, # NAIVE
	2, # MODEST
	2, # MILD
	2, # QUIET
	2, # BASHFUL
	1, # RASH
	1, # CALM
	2, # GENTLE
	1, # SASSY
	2, # CAREFUL
	1, # QUIRKY
]

# --- sBackAnimationIds (pokemon_animation.c:403-428) ------------------
# BackAnim set -> its three nature variants, in source's own order.
# NOT uniformly "one family at three speeds": BACK_ANIM_GROW's third
# entry is ANIM_GROW_IN_STAGES, a structurally different animation, and
# BACK_ANIM_DIP_RIGHT_SIDE's order is twice/normal/fast rather than
# fast/normal/slow. Kept as an explicit per-entry table for that reason.
const BACK_ANIM_SETS: Dictionary = {
	BACK_ANIM_H_VIBRATE: ["h_vibrate_fastest", "h_vibrate_fast", "h_vibrate"],
	BACK_ANIM_H_SLIDE: ["h_slide_fast", "h_slide", "h_slide_slow"],
	BACK_ANIM_H_SPRING: ["h_spring_fast", "h_spring", "h_spring_slow"],
	BACK_ANIM_H_SPRING_REPEATED: ["h_rep_spring_fast", "h_rep_spring", "h_rep_spring_slow"],
	BACK_ANIM_SHRINK_GROW: ["shrink_grow_fast", "shrink_grow", "shrink_grow_slow"],
	BACK_ANIM_GROW: ["grow_twice", "grow", "grow_in_stages"],
	BACK_ANIM_CIRCLE_COUNTERCLOCKWISE: ["circle_ccw_long", "circle_ccw", "circle_ccw_slow"],
	BACK_ANIM_H_SHAKE: ["h_shake_fast", "h_shake", "h_shake_slow"],
	BACK_ANIM_V_SHAKE: ["v_shake_back_fast", "v_shake_back", "v_shake_back_slow"],
	BACK_ANIM_V_SHAKE_H_SLIDE: ["v_shake_h_slide_fast", "v_shake_h_slide", "v_shake_h_slide_slow"],
	BACK_ANIM_V_STRETCH: ["v_stretch_twice", "v_stretch", "v_stretch_slow"],
	BACK_ANIM_H_STRETCH: ["h_stretch_twice", "h_stretch", "h_stretch_slow"],
	BACK_ANIM_GROW_STUTTER: ["grow_stutter_twice", "grow_stutter", "grow_stutter_slow"],
	BACK_ANIM_V_SHAKE_LOW: ["v_shake_low_fast", "v_shake_low", "v_shake_low_slow"],
	BACK_ANIM_TRIANGLE_DOWN: ["triangle_down_twice", "triangle_down", "triangle_down_slow"],
	BACK_ANIM_CONCAVE_ARC_LARGE: ["arc_large_twice", "arc_large", "arc_large_slow"],
	BACK_ANIM_CONVEX_DOUBLE_ARC: ["convex_arc_twice", "convex_arc", "convex_arc_slow"],
	BACK_ANIM_CONCAVE_ARC_SMALL: ["arc_small_twice", "arc_small", "arc_small_slow"],
	BACK_ANIM_DIP_RIGHT_SIDE: ["h_dip_twice", "h_dip", "h_dip_fast"],
	BACK_ANIM_SHRINK_GROW_VIBRATE: ["sgv_fast", "sgv", "sgv_slow"],
	BACK_ANIM_JOLT_RIGHT: ["jolt_right_fast", "jolt_right", "jolt_right_slow"],
	BACK_ANIM_SHAKE_FLASH_YELLOW: ["flash_yellow_fast", "flash_yellow", "flash_yellow_slow"],
	BACK_ANIM_SHAKE_GLOW_RED: ["glow_red_fast", "glow_red", "glow_red_slow"],
	BACK_ANIM_SHAKE_GLOW_GREEN: ["glow_green_fast", "glow_green", "glow_green_slow"],
	BACK_ANIM_SHAKE_GLOW_BLUE: ["glow_blue_fast", "glow_blue", "glow_blue_slow"],
}

# --- Per-variant seed data --------------------------------------------
# "fn" is the shared step function; "d" seeds the source `sprite->data[]`
# slots that variant's own `Anim_*` setup function writes. Slot numbers
# match source exactly so each entry can be diffed against its own
# `Anim_*` body line by line.
const ANIM_SETUP: Dictionary = {
	# Anim_HorizontalVibrate{,_Fast,_Fastest} -- amplitude in d7 (ours;
	# source inlines it as a literal in three near-identical functions).
	"h_vibrate": {"fn": "h_vibrate", "d": {7: 6}},
	"h_vibrate_fast": {"fn": "h_vibrate", "d": {7: 9}},
	"h_vibrate_fastest": {"fn": "h_vibrate", "d": {7: 12}},

	# Anim_HorizontalSlide{,_Fast,_Slow}
	"h_slide": {"fn": "h_slide", "d": {0: 40}},
	"h_slide_fast": {"fn": "h_slide", "d": {0: 20}},
	"h_slide_slow": {"fn": "h_slide", "d": {0: 80}},

	# Anim_HorizontalSpring{,_Fast,_Slow}
	"h_spring": {"fn": "h_spring", "d": {7: 0, 6: 8, 5: 512, 4: 8}},
	"h_spring_fast": {"fn": "h_spring", "d": {7: 0, 6: 8, 5: 512, 4: 16}},
	"h_spring_slow": {"fn": "h_spring", "d": {7: 0, 6: 4, 5: 256, 4: 16}},

	# Anim_HorizontalRepeatedSpring{,_Fast,_Slow}
	"h_rep_spring": {"fn": "h_rep_spring", "d": {7: 0, 6: 8, 5: 512, 4: 8}},
	"h_rep_spring_fast": {"fn": "h_rep_spring", "d": {7: 0, 6: 8, 5: 512, 4: 16}},
	"h_rep_spring_slow": {"fn": "h_rep_spring", "d": {7: 0, 6: 4, 5: 256, 4: 16}},

	# Anim_ShrinkGrow{,_Fast,_Slow}
	"shrink_grow": {"fn": "shrink_grow", "d": {7: 3, 6: 8}},
	"shrink_grow_fast": {"fn": "shrink_grow", "d": {7: 5, 6: 8}},
	"shrink_grow_slow": {"fn": "shrink_grow", "d": {7: 3, 6: 4}},

	# Anim_Grow / Anim_Grow_Twice / Anim_GrowInStages
	"grow": {"fn": "grow", "d": {7: 0, 6: 4, 5: 1}},
	"grow_twice": {"fn": "grow", "d": {7: 0, 6: 8, 5: 2}},
	"grow_in_stages": {"fn": "grow_in_stages", "d": {7: 0, 6: 0, 5: 0}},

	# Anim_CircleCounterclockwise{,_Long,_Slow}
	# Source keeps rotation/data/speed in a small side pool (`sAnims`);
	# with one animation live at a time that pool is pure indirection, so
	# the three values are seeded straight into unused data slots here.
	"circle_ccw": {"fn": "circle_ccw", "d": {5: 512, 4: 6, 3: 24}},
	"circle_ccw_long": {"fn": "circle_ccw", "d": {5: 1024, 4: 6, 3: 24}},
	"circle_ccw_slow": {"fn": "circle_ccw", "d": {5: 512, 4: 3, 3: 12}},

	# Anim_HorizontalShake{,_Fast,_Slow}
	"h_shake": {"fn": "h_shake", "d": {0: 60, 7: 3}},
	"h_shake_fast": {"fn": "h_shake", "d": {0: 70, 7: 6}},
	"h_shake_slow": {"fn": "h_shake", "d": {0: 30, 7: 3}},

	# Anim_VerticalShakeBack{,_Fast,_Slow}
	"v_shake_back": {"fn": "v_shake_back", "d": {0: 60, 7: 3}},
	"v_shake_back_fast": {"fn": "v_shake_back", "d": {0: 70, 7: 6}},
	"v_shake_back_slow": {"fn": "v_shake_back", "d": {0: 30, 7: 3}},

	# Anim_VerticalShakeHorizontalSlide{,_Fast,_Slow} -- three separate
	# near-identical source functions; only the counter step and the y2
	# sine modulus differ, so they share one step fn here (d0/d7).
	"v_shake_h_slide": {"fn": "v_shake_h_slide", "d": {0: 48, 7: 128}},
	"v_shake_h_slide_fast": {"fn": "v_shake_h_slide", "d": {0: 64, 7: 96}},
	"v_shake_h_slide_slow": {"fn": "v_shake_h_slide", "d": {0: 24, 7: 128}},

	# Anim_VerticalStretchBothEnds{,_Twice,_Slow}
	"v_stretch": {"fn": "v_stretch", "d": {4: 1, 6: 30, 3: 60, 5: 0, 7: 0}},
	"v_stretch_twice": {"fn": "v_stretch", "d": {4: 2, 6: 20, 3: 70, 5: 0, 7: 0}},
	"v_stretch_slow": {"fn": "v_stretch", "d": {4: 1, 6: 40, 3: 40, 5: 0, 7: 0}},

	# Anim_HorizontalStretchFar{,_Twice,_Slow}
	"h_stretch": {"fn": "h_stretch", "d": {4: 1, 6: 30, 3: 60, 5: 0, 7: 0}},
	"h_stretch_twice": {"fn": "h_stretch", "d": {4: 2, 6: 20, 3: 70, 5: 0, 7: 0}},
	"h_stretch_slow": {"fn": "h_stretch", "d": {4: 1, 6: 40, 3: 40, 5: 0, 7: 0}},

	# Anim_GrowStutter{,_Twice,_Slow}
	"grow_stutter": {"fn": "grow_stutter", "d": {4: 1, 6: 30, 3: 60, 5: 0, 7: 0}},
	"grow_stutter_twice": {"fn": "grow_stutter", "d": {4: 2, 6: 20, 3: 70, 5: 0, 7: 0}},
	"grow_stutter_slow": {"fn": "grow_stutter", "d": {4: 1, 6: 40, 3: 40, 5: 0, 7: 0}},

	# Anim_VerticalShakeLowTwice{,_Fast,_Slow}
	"v_shake_low": {"fn": "v_shake_low", "d": {0: 40, 7: 6}},
	"v_shake_low_fast": {"fn": "v_shake_low", "d": {0: 56, 7: 9}},
	"v_shake_low_slow": {"fn": "v_shake_low", "d": {0: 24, 7: 6}},

	# Anim_TriangleDown{,_Fast,_Slow}. NOTE the set's first entry is
	# ANIM_TRIANGLE_DOWN_TWICE, which maps to Anim_TriangleDown_Fast --
	# a real name/id mismatch in source, preserved rather than tidied.
	"triangle_down": {"fn": "triangle_down", "d": {5: 2, 6: 1}},
	"triangle_down_twice": {"fn": "triangle_down", "d": {5: 2, 6: 2}},
	"triangle_down_slow": {"fn": "triangle_down", "d": {5: 1, 6: 1}},

	# Anim_ConcaveArcLarge{,_Twice,_Slow} / ConcaveArcSmall{...}
	"arc_large": {"fn": "concave_arc", "d": {6: 1, 7: 0, 5: 12, 4: 12, 3: 6}},
	"arc_large_twice": {"fn": "concave_arc", "d": {6: 2, 7: 0, 5: 12, 4: 12, 3: 8}},
	"arc_large_slow": {"fn": "concave_arc", "d": {6: 1, 7: 0, 5: 12, 4: 12, 3: 4}},
	"arc_small": {"fn": "concave_arc", "d": {6: 1, 7: 0, 5: 4, 4: 6, 3: 6}},
	"arc_small_twice": {"fn": "concave_arc", "d": {6: 2, 7: 0, 5: 4, 4: 6, 3: 8}},
	"arc_small_slow": {"fn": "concave_arc", "d": {6: 1, 7: 0, 5: 4, 4: 6, 3: 4}},

	# Anim_ConvexDoubleArc{,_Twice,_Slow}
	"convex_arc": {"fn": "convex_arc", "d": {6: 2, 7: 0, 5: 16, 4: 1, 3: 6}},
	"convex_arc_twice": {"fn": "convex_arc", "d": {6: 3, 7: 0, 5: 16, 4: 1, 3: 8}},
	"convex_arc_slow": {"fn": "convex_arc", "d": {6: 2, 7: 0, 5: 16, 4: 1, 3: 4}},

	# Anim_HorizontalDip{,_Twice,_Fast}. d7 is a FRAME COUNT, so the
	# "_Fast" variant's 90 is genuinely the LONGEST of the three -- a
	# source naming quirk, ported as-is rather than "corrected".
	"h_dip": {"fn": "h_dip", "d": {7: 60, 5: 8, 4: -32, 3: 1, 0: 0}},
	"h_dip_twice": {"fn": "h_dip", "d": {7: 30, 5: 8, 4: -32, 3: 2, 0: 0}},
	"h_dip_fast": {"fn": "h_dip", "d": {7: 90, 5: 8, 4: -32, 3: 1, 0: 0}},

	# Anim_ShrinkGrowVibrate{,_Fast,_Slow}. Source nudges y2 by +2 at
	# setup (`sprite->y2 += 2`) before the loop takes over.
	"sgv": {"fn": "sgv", "d": {6: 40, 7: 40}, "y2": 2},
	"sgv_fast": {"fn": "sgv", "d": {6: 40, 7: 80}, "y2": 2},
	"sgv_slow": {"fn": "sgv", "d": {6: 80, 7: 80}, "y2": 2},

	# Anim_JoltRight{,_Fast,_Slow} -- a 5-state machine, state in "jolt".
	"jolt_right": {"fn": "jolt_right", "d": {7: 2, 6: 8, 5: 12, 4: 2, 3: 0, 2: 1}},
	"jolt_right_fast": {"fn": "jolt_right", "d": {7: 4, 6: 12, 5: 16, 4: 4, 3: 0, 2: 2}},
	"jolt_right_slow": {"fn": "jolt_right", "d": {7: 0, 6: 6, 5: 6, 4: 2, 3: 0, 2: 1}},

	# Anim_ShakeFlashYellow{,_Fast,_Slow} -- d3 picks one of the three
	# sShakeYellowFlashData tables.
	"flash_yellow": {"fn": "flash_yellow", "d": {6: 0, 5: 0, 4: 0, 3: 1}},
	"flash_yellow_fast": {"fn": "flash_yellow", "d": {6: 0, 5: 0, 4: 0, 3: 0}},
	"flash_yellow_slow": {"fn": "flash_yellow", "d": {6: 0, 5: 0, 4: 0, 3: 2}},

	# Anim_ShakeGlow{Red,Green,Blue}{,_Fast,_Slow} -- d1 picks the colour.
	"glow_red": {"fn": "shake_glow", "d": {0: 20, 5: 0, 4: 1, 3: 0, 1: 0}},
	"glow_red_fast": {"fn": "shake_glow", "d": {0: 10, 5: 0, 4: 2, 3: 0, 1: 0}},
	"glow_red_slow": {"fn": "shake_glow", "d": {0: 80, 5: 0, 4: 1, 3: 0, 1: 0}},
	"glow_green": {"fn": "shake_glow", "d": {0: 20, 5: 0, 4: 1, 3: 0, 1: 1}},
	"glow_green_fast": {"fn": "shake_glow", "d": {0: 10, 5: 0, 4: 2, 3: 0, 1: 1}},
	"glow_green_slow": {"fn": "shake_glow", "d": {0: 80, 5: 0, 4: 1, 3: 0, 1: 1}},
	"glow_blue": {"fn": "shake_glow", "d": {0: 20, 5: 0, 4: 1, 3: 0, 1: 2}},
	"glow_blue_fast": {"fn": "shake_glow", "d": {0: 10, 5: 0, 4: 2, 3: 0, 1: 2}},
	"glow_blue_slow": {"fn": "shake_glow", "d": {0: 80, 5: 0, 4: 1, 3: 0, 1: 2}},
}

# --- Lookup tables ported verbatim ------------------------------------

# sTriangleDownData (pokemon_animation.c) -- {x, y, timer} per leg.
const TRIANGLE_DOWN_DATA: Array = [
	[1, 1, 12], [-2, 0, 12], [1, -1, 12], [0, 0, 0],
]

# sVerticalShakeData -- {amplitude-or-sentinel, duration}. The first
# column is read as u8, so -1/-2 are the sentinels 255/254.
const V_SHAKE_SENTINEL_END := 255   # (u8)-1 -> animation is finished
const V_SHAKE_SENTINEL_ZERO := 254  # (u8)-2 -> hold at zero amplitude
const V_SHAKE_DATA: Array = [
	[6, 30], [V_SHAKE_SENTINEL_ZERO, 15], [6, 30], [V_SHAKE_SENTINEL_END, 0],
]

# sShakeYellowFlashData_{Fast,Normal,Slow} -- {isYellow, time}; time 255
# ((u8)-1) terminates.
const FLASH_YELLOW_DATA: Array = [
	[ # Fast
		[0, 1], [1, 2], [0, 15], [1, 1], [0, 15], [1, 1], [0, 15], [1, 1],
		[0, 1], [1, 1], [0, 1], [1, 1], [0, 1], [1, 1], [0, 1], [1, 1],
		[0, 1], [1, 1], [0, 1], [0, 255],
	],
	[ # Normal
		[0, 5], [1, 1], [0, 15], [1, 4], [0, 2], [1, 2], [0, 2], [1, 2],
		[0, 2], [1, 2], [0, 2], [1, 2], [0, 2], [0, 255],
	],
	[ # Slow
		[0, 1], [1, 1], [0, 20], [1, 1], [0, 20], [1, 1], [0, 20], [1, 1],
		[0, 1], [0, 255],
	],
]

# ShakeGlow_Blend's own sColors[], expanded from GBA RGB555 to 8-bit.
const SHAKE_GLOW_COLORS: Array = [
	Color8(255, 0, 0),   # SHAKEGLOW_RED
	Color8(0, 255, 0),   # SHAKEGLOW_GREEN
	Color8(0, 0, 255),   # SHAKEGLOW_BLUE
]
const FLASH_YELLOW_COLOR := Color8(255, 255, 0)  # RGB_YELLOW

# gSineTable (src/trig.c) -- 320 entries of Q_8_8, peak 256 at index 64.
# Embedded verbatim rather than computed: 150 of the 320 entries differ
# from a naive round(sin(i*PI/128)*256), so a recomputed table would
# quietly diverge from source. Same precedent as [M20]'s own 211-entry
# EXP_SCALING_FACTORS port.
# The 64 entries past index 255 exist so Cos can index `[i + 64]`.
const SINE_TABLE: Array = [
	0, 6, 12, 18, 25, 31, 37, 43, 49, 56, 62, 68, 74, 80, 86, 92,
	97, 103, 109, 115, 120, 126, 131, 136, 142, 147, 152, 157, 162, 167, 171, 176,
	181, 185, 189, 193, 197, 201, 205, 209, 212, 216, 219, 222, 225, 228, 231, 234,
	236, 238, 241, 243, 244, 246, 248, 249, 251, 252, 253, 254, 254, 255, 255, 255,
	256, 255, 255, 255, 254, 254, 253, 252, 251, 249, 248, 246, 244, 243, 241, 238,
	236, 234, 231, 228, 225, 222, 219, 216, 212, 209, 205, 201, 197, 193, 189, 185,
	181, 176, 171, 167, 162, 157, 152, 147, 142, 136, 131, 126, 120, 115, 109, 103,
	97, 92, 86, 80, 74, 68, 62, 56, 49, 43, 37, 31, 25, 18, 12, 6,
	0, -6, -12, -18, -25, -31, -37, -43, -49, -56, -62, -68, -74, -80, -86, -92,
	-97, -103, -109, -115, -120, -126, -131, -136, -142, -147, -152, -157, -162, -167, -171, -176,
	-181, -185, -189, -193, -197, -201, -205, -209, -212, -216, -219, -222, -225, -228, -231, -234,
	-236, -238, -241, -243, -244, -246, -248, -249, -251, -252, -253, -254, -254, -255, -255, -255,
	-256, -255, -255, -255, -254, -254, -253, -252, -251, -249, -248, -246, -244, -243, -241, -238,
	-236, -234, -231, -228, -225, -222, -219, -216, -212, -209, -205, -201, -197, -193, -189, -185,
	-181, -176, -171, -167, -162, -157, -152, -147, -142, -136, -131, -126, -120, -115, -109, -103,
	-97, -92, -86, -80, -74, -68, -62, -56, -49, -43, -37, -31, -25, -18, -12, -6,
	0, 6, 12, 18, 25, 31, 37, 43, 49, 56, 62, 68, 74, 80, 86, 92,
	97, 103, 109, 115, 120, 126, 131, 136, 142, 147, 152, 157, 162, 167, 171, 176,
	181, 185, 189, 193, 197, 201, 205, 209, 212, 216, 219, 222, 225, 228, 231, 234,
	236, 238, 241, 243, 244, 246, 248, 249, 251, 252, 253, 254, 254, 255, 255, 255,
]


# --- GBA trig ---------------------------------------------------------
# `Sin`/`Cos` (src/trig.c:515-524). The index is wrapped into the table's
# own 256-entry period rather than indexed raw: a handful of source call
# sites can pass a negative index (`Anim_GrowInStages`'s
# `Sin(data[7] - scale, 64)`, `SetHorizontalDip`'s u16 round-trip of a
# negative Sin result), which on hardware reads out of bounds. Wrapping
# is identical to source for every in-range index and gives the
# mathematically correct value instead of garbage for the rest.
static func sin_g(index: int, amplitude: int) -> int:
	return (amplitude * int(SINE_TABLE[posmod(index, 256)])) >> 8


static func cos_g(index: int, amplitude: int) -> int:
	return (amplitude * int(SINE_TABLE[posmod(index, 256) + 64])) >> 8


# --- Selection --------------------------------------------------------

## Which of a set's three variants a given nature plays.
static func variant_for_nature(nature: int) -> int:
	if nature < 0 or nature >= NATURE_BACK_VARIANT.size():
		return 0
	return NATURE_BACK_VARIANT[nature]


## The concrete variant key for a (back anim set, nature) pair, or "" when
## the species has no back animation at all.
static func anim_key_for(back_anim_id: int, nature: int) -> String:
	if not BACK_ANIM_SETS.has(back_anim_id):
		return ""
	return BACK_ANIM_SETS[back_anim_id][variant_for_nature(nature)]


# --- State ------------------------------------------------------------

## Seed a fresh animation state. Returns an empty Dictionary when the
## species has no back animation (BACK_ANIM_NONE), which callers should
## treat as "play nothing" rather than as an error.
static func start(back_anim_id: int, nature: int) -> Dictionary:
	var key := anim_key_for(back_anim_id, nature)
	if key == "":
		return {}
	var setup: Dictionary = ANIM_SETUP[key]
	var st := {
		"key": key,
		"fn": setup["fn"],
		"d": [0, 0, 0, 0, 0, 0, 0, 0],
		"x2": 0,
		"y2": int(setup.get("y2", 0)),
		"sx": 256,          # GBA affine, 256 == identity, INVERTED
		"sy": 256,
		"rot": 0,           # GBA angle, 65536 == full turn
		"blend_coeff": 0,   # 0..16, matching BlendPalette's own coeff
		"blend_color": Color(1, 1, 1, 1),
		"jolt": 0,          # JoltRight sub-state
		"frames": 0,
		"done": false,
	}
	# Task_HandleMonAnimation clears data[0] and data[2..7] but leaves
	# data[1] holding sDontFlip (TRUE == 1). The ShakeFlashYellow family
	# genuinely reads that slot as an x-offset seed, so it starts at 1 and
	# oscillates +/-1 -- an odd but real source behaviour, not a bug here.
	st["d"][1] = 1
	for slot in setup["d"]:
		st["d"][slot] = setup["d"][slot]
	return st


## Advance exactly one GBA frame. No-op once `done`.
static func step(st: Dictionary) -> void:
	if st.is_empty() or st["done"]:
		return
	st["frames"] = int(st["frames"]) + 1
	match String(st["fn"]):
		"h_vibrate": _h_vibrate(st)
		"h_slide": _h_slide(st)
		"h_spring": _h_spring(st)
		"h_rep_spring": _h_rep_spring(st)
		"shrink_grow": _shrink_grow(st)
		"grow": _grow(st)
		"grow_in_stages": _grow_in_stages(st)
		"circle_ccw": _circle_ccw(st)
		"h_shake": _h_shake(st)
		"v_shake_back": _v_shake_back(st)
		"v_shake_h_slide": _v_shake_h_slide(st)
		"v_stretch": _v_stretch(st)
		"h_stretch": _h_stretch(st)
		"grow_stutter": _grow_stutter(st)
		"v_shake_low": _v_shake_low(st)
		"triangle_down": _triangle_down(st)
		"concave_arc": _concave_arc(st)
		"convex_arc": _convex_arc(st)
		"h_dip": _h_dip(st)
		"sgv": _sgv(st)
		"jolt_right": _jolt_right(st)
		"flash_yellow": _flash_yellow(st)
		"shake_glow": _shake_glow(st)
		_:
			push_error("MonAnimator: unknown step fn %s" % st["fn"])
			st["done"] = true


# --- Godot-space conversion -------------------------------------------

## Sprite offset in Godot pixels. Scaled by AMPLITUDE_SCALE -- see that
## constant's own note before changing anything here.
static func godot_offset(st: Dictionary) -> Vector2:
	if st.is_empty():
		return Vector2.ZERO
	return Vector2(int(st["x2"]), int(st["y2"])) * AMPLITUDE_SCALE


## Scale multiplier to apply ON TOP of the sprite's resting scale.
## Inverts GBA affine (256 == identity, smaller value == bigger sprite).
static func godot_scale(st: Dictionary) -> Vector2:
	if st.is_empty():
		return Vector2.ONE
	var sx := int(st["sx"])
	var sy := int(st["sy"])
	# Source can never reach 0 here for any battle-path animation (every
	# affine value stays comfortably positive once sDontFlip's own sign
	# flip is out of the picture), but a divide-by-zero would be a hard
	# crash rather than a visual glitch, so it is guarded rather than
	# assumed.
	if sx == 0 or sy == 0:
		return Vector2.ONE
	return Vector2(256.0 / float(sx), 256.0 / float(sy))


## Rotation in radians.
static func godot_rotation(st: Dictionary) -> float:
	if st.is_empty():
		return 0.0
	return float(int(st["rot"])) / 65536.0 * TAU


## Blend strength 0..1 for the `_BLEND_SHADER_CODE` mix() shader that
## [M26B3-6a] built for the recall/emerge pink. BlendPalette's own coeff
## is 0..16, where 16 fully REPLACES the channel.
static func godot_blend_amount(st: Dictionary) -> float:
	if st.is_empty():
		return 0.0
	return clampf(float(int(st["blend_coeff"])) / 16.0, 0.0, 1.0)


# --- Motion functions -------------------------------------------------
# Each is a direct port of its source counterpart. Source line references
# are to src/pokemon_animation.c. TryFlipX calls are omitted throughout
# (no-op in battle -- see this file's own header note).

# Anim_HorizontalVibrate{,_Fast,_Fastest}
static func _h_vibrate(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] > 40:
		st["done"] = true
		st["x2"] = 0
	else:
		var sign_: int = 1 if (d[2] & 1) == 0 else -1
		st["x2"] = sin_g((d[2] * 128 / 40) % 256, d[7]) * sign_
	d[2] += 1


# HorizontalSlide
static func _h_slide(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] > d[0]:
		st["done"] = true
		st["x2"] = 0
	else:
		st["x2"] = sin_g((d[2] * 384 / d[0]) % 256, 6)
	d[2] += 1


# HorizontalSpring
static func _h_spring(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[7] > d[5]:
		st["x2"] = 0
		st["done"] = true
		st["sx"] = 256
		st["sy"] = 256
	else:
		st["x2"] = sin_g(d[7] % 256, d[4])
		d[7] += d[6]
		st["sx"] = 256 + sin_g(d[7] % 128, 96)
		st["sy"] = 256


# HorizontalRepeatedSpring -- identical to HorizontalSpring except the
# xScale index/amplitude (`(d7 % 64) * 2` at 128, vs `d7 % 128` at 96).
static func _h_rep_spring(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[7] > d[5]:
		st["x2"] = 0
		st["done"] = true
		st["sx"] = 256
		st["sy"] = 256
	else:
		st["x2"] = sin_g(d[7] % 256, d[4])
		d[7] += d[6]
		st["sx"] = 256 + sin_g((d[7] % 64) * 2, 128)
		st["sy"] = 256


# ShrinkGrow
static func _shrink_grow(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] > (128 / d[6]) * d[7]:
		st["sx"] = 256
		st["sy"] = 256
		st["y2"] = 0
		st["done"] = true
	else:
		var y_scale: int = sin_g(d[4], 32) + 256
		var pos_y: int = 0
		if y_scale > 256:
			pos_y = (256 - y_scale) / 8
		st["y2"] = -pos_y
		st["sx"] = sin_g(d[4], 48) + 256
		st["sy"] = y_scale
		d[2] += 1
		d[4] = (d[4] + d[6]) & 0xFF


# Grow
static func _grow(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[7] > 255:
		if d[5] <= 1:
			st["done"] = true
			st["sx"] = 256
			st["sy"] = 256
		else:
			d[5] -= 1
			d[7] = 0
	else:
		d[7] += d[6]
		if d[7] > 256:
			d[7] = 256
		var scale: int = sin_g(d[7] / 2, 64)
		st["sx"] = 256 - scale
		st["sy"] = 256 - scale


# Anim_GrowInStages -- the one member of BACK_ANIM_GROW's set that is a
# structurally different animation rather than a speed variant.
static func _grow_in_stages(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[6] > 0:
		d[6] -= 1
		if d[5] != 3:
			var scale: int = (8 * d[6]) / 20
			scale = sin_g(d[7] - scale, 64)
			st["sx"] = 256 - scale
			st["sy"] = 256 - scale
		return
	var v: int = 0
	if d[5] == 3:
		if d[7] > 63:
			d[7] = 64
			st["sx"] = 256
			st["sy"] = 256
			st["done"] = true
		v = cos_g(d[7], 64)
	else:
		v = sin_g(d[7], 64)
		if d[7] > 63:
			d[5] = 3
			d[6] = 10
			d[7] = 0
		else:
			if v > 48 and d[5] == 1:
				d[5] = 2
				d[6] = 20
			elif v > 16 and d[5] == 0:
				d[5] = 1
				d[6] = 20
	# Source applies both of these unconditionally, including on the frame
	# that ends the animation (where v resolves to 0, so they land on
	# identity anyway). Kept unguarded to match.
	d[7] += 2
	st["sx"] = 256 - v
	st["sy"] = 256 - v


# CircleCounterclockwise
static func _circle_ccw(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] > d[5]:
		st["x2"] = 0
		st["y2"] = 0
		st["done"] = true
	else:
		var index: int = (d[2] + 192) % 256
		st["x2"] = -cos_g(index, d[4] * 2)
		st["y2"] = sin_g(index, d[4]) + d[4]
	d[2] += d[3]


# HorizontalShake
static func _h_shake(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] > 2304:
		st["done"] = true
		st["x2"] = 0
	else:
		st["x2"] = sin_g(d[2] % 256, d[7])
	d[2] += d[0]


# VerticalShakeBack
static func _v_shake_back(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] > 2304:
		st["done"] = true
		st["y2"] = 0
	else:
		st["y2"] = sin_g((d[2] + 192) % 256, d[7]) + d[7]
	d[2] += d[0]


# Anim_VerticalShakeHorizontalSlide{,_Fast,_Slow}
static func _v_shake_h_slide(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] > 2048:
		st["done"] = true
		d[6] = 0
		return
	var div_case: int = (d[2] / 512) % 4
	match div_case:
		0: st["x2"] = (d[2] % 512) / 32
		1: st["x2"] = -(d[2] % 512 * 16) / 512 + 16
		2: st["x2"] = -(d[2] % 512 * 16) / 512
		3: st["x2"] = (d[2] % 512) / 32 - 16
	st["y2"] = sin_g(d[2] % d[7], 4)
	d[2] += d[0]


# VerticalStretchBothEnds. The `!sDontFlip` xScale branch is skipped --
# battle always takes the `256 + Sin(index2, 16)` form.
static func _v_stretch(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[5] > d[6]:
		st["y2"] = 0
		d[5] = 0
		st["sx"] = 256
		st["sy"] = 256
		if d[4] <= 1:
			st["done"] = true
		else:
			d[4] -= 1
			d[7] = 0
		return
	var index1: int = 0
	var index2: int = (d[5] * 128) / d[6]
	var cmp1: int = d[6] / 4
	var cmp2: int = cmp1 * 3
	if d[5] >= cmp1 and d[5] < cmp2:
		d[7] += 51
		index1 = d[7] & 0xFF
	var amplitude: int = d[3]
	st["sx"] = 256 + sin_g(index2, 16)
	st["sy"] = 256 - sin_g(index2, amplitude) - sin_g(index1, amplitude / 5)
	d[5] += 1


# HorizontalStretchFar. Same `else` branch selection as above.
static func _h_stretch(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[5] > d[6]:
		d[5] = 0
		st["sx"] = 256
		st["sy"] = 256
		if d[4] <= 1:
			st["done"] = true
		else:
			d[4] -= 1
			d[7] = 0
		return
	var index1: int = 0
	var index2: int = (d[5] * 128) / d[6]
	var cmp1: int = d[6] / 4
	var cmp2: int = cmp1 * 3
	if d[5] >= cmp1 and d[5] < cmp2:
		d[7] += 51
		index1 = d[7] & 0xFF
	var amplitude: int = d[3]
	st["sx"] = 256 - sin_g(index2, amplitude) - sin_g(index1, amplitude / 5 * 2)
	st["sy"] = 256
	d[5] += 1


# GrowStutter. Same `else` branch selection as above.
static func _grow_stutter(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[5] > d[6]:
		st["y2"] = 0
		d[5] = 0
		st["sx"] = 256
		st["sy"] = 256
		if d[4] <= 1:
			st["done"] = true
		else:
			d[4] -= 1
			d[7] = 0
		return
	var index1: int = 0
	var index2: int = (d[5] * 128) / d[6]
	var cmp1: int = d[6] / 4
	var cmp2: int = cmp1 * 3
	if d[5] >= cmp1 and d[5] < cmp2:
		d[7] += 51
		index1 = d[7] & 0xFF
	var amplitude: int = d[3]
	st["sx"] = 256 - sin_g(index1, amplitude / 5 * 2) - sin_g(index2, amplitude)
	st["sy"] = 256 - sin_g(index1, amplitude / 5) - sin_g(index2, amplitude)
	d[5] += 1


# VerticalShakeLowTwice
static func _v_shake_low(st: Dictionary) -> void:
	var d: Array = st["d"]
	# d[5] walks the table and stops on its own sentinel row, so it cannot
	# run past the end in practice; guarded anyway because an out-of-range
	# index here would be a hard crash mid-battle rather than a glitch.
	if d[5] < 0 or d[5] >= V_SHAKE_DATA.size():
		st["done"] = true
		st["y2"] = 0
		return
	var row: Array = V_SHAKE_DATA[d[5]]
	var amp: int = row[0]
	if amp != V_SHAKE_SENTINEL_END:
		amp = d[7]
	var duration: int = row[1]
	var eased: int = 0
	if row[0] != V_SHAKE_SENTINEL_ZERO:
		eased = (duration - d[6]) * amp / duration if duration != 0 else 0
	if amp == V_SHAKE_SENTINEL_END:
		st["done"] = true
		st["y2"] = 0
		return
	st["y2"] = sin_g((d[2] + 192) % 256, eased) + eased
	if d[6] == duration:
		d[5] += 1
		d[6] = 0
	else:
		d[2] += d[0]
		d[6] += 1


# TriangleDown
static func _triangle_down(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] == 0:
		d[3] = 0
	# Same reasoning as _v_shake_low's guard: the final table row's zero
	# timer ends the animation before d[3] can walk off the end.
	if d[3] < 0 or d[3] >= TRIANGLE_DOWN_DATA.size():
		st["done"] = true
		return
	if TRIANGLE_DOWN_DATA[d[3]][2] / d[5] == d[2]:
		d[3] += 1
		d[2] = 0
	if TRIANGLE_DOWN_DATA[d[3]][2] / d[5] == 0:
		d[6] -= 1
		if d[6] == 0:
			st["done"] = true
		else:
			d[2] = 0
	else:
		var amplitude: int = d[5]
		st["x2"] = int(st["x2"]) + TRIANGLE_DOWN_DATA[d[3]][0] * amplitude
		st["y2"] = int(st["y2"]) + TRIANGLE_DOWN_DATA[d[3]][1] * d[5]
		d[2] += 1


# ConcaveArc -- shared by BACK_ANIM_CONCAVE_ARC_LARGE and _SMALL.
static func _concave_arc(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[7] > 255:
		if d[6] <= 1:
			st["done"] = true
			st["x2"] = 0
			st["y2"] = 0
		else:
			d[7] = d[7] % 256
			d[6] -= 1
		return
	st["x2"] = -sin_g(d[7], d[5])
	var y: int = sin_g((d[7] + 192) % 256, d[4])
	if y > 0:
		y = -y
	st["y2"] = y + d[4]
	d[7] += d[3]


# ConvexDoubleArc
static func _convex_arc(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[7] > 256:
		if d[6] <= d[4]:
			st["done"] = true
		else:
			d[4] += 1
			d[7] = 0
		st["x2"] = 0
		st["y2"] = 0
		return
	if d[7] > 159:
		if d[7] > 256:
			d[7] = 256
		st["y2"] = -sin_g(d[7] % 256, 8)
	elif d[7] > 95:
		st["y2"] = sin_g(96, 6) - sin_g((d[7] - 96) * 2, 4)
	else:
		st["y2"] = sin_g(d[7], 6)
	var pos_x: int = -sin_g(d[7] / 2, d[5])
	if d[4] % 2 == 0:
		pos_x *= -1
	st["x2"] = pos_x
	d[7] += d[3]


# Anim_HorizontalDip{,_Twice,_Fast} + SetHorizontalDip + SetPosForRotation
static func _h_dip(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] > d[7]:
		st["sx"] = 256
		st["sy"] = 256
		st["rot"] = 0
		st["x2"] = 0
		st["y2"] = 0
		d[0] += 1
		if d[3] <= d[0]:
			st["done"] = true
			return
		d[2] = 0
	else:
		var index: int = sin_g((d[2] * 128) / d[7], d[5])
		d[6] = -(index << 8)
		# SetPosForRotation(sprite, index, d[4], 0)
		var amp_x: int = -d[4]
		var x_adder: int = cos_g(index, amp_x)
		var y_adder: int = sin_g(index, amp_x)
		st["x2"] = x_adder + d[4]
		st["y2"] = y_adder
		st["sx"] = 256
		st["sy"] = 256
		st["rot"] = d[6]
	d[2] += 1


# ShrinkGrowVibrate
static func _sgv(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] > d[7]:
		st["y2"] = 0
		st["sx"] = 256
		st["sy"] = 256
		st["done"] = true
		d[2] += 1
		return
	var index: int = ((d[2] % d[6]) * 256 / d[6]) % 256
	var sin_y: int = 0
	if d[2] % 2 == 0:
		d[4] = sin_g(index, 32) + 256
		d[5] = sin_g(index, 32) + 256
		sin_y = sin_g(index, 32)
	else:
		d[4] = sin_g(index, 8) + 256
		d[5] = sin_g(index, 8) + 256
		sin_y = sin_g(index, 8)
	st["y2"] = sin_y / 8
	st["sx"] = d[4]
	st["sy"] = d[5]
	d[2] += 1


# JoltRight + JoltRight_0.._3 -- a 5-state machine, state held in "jolt".
static func _jolt_right(st: Dictionary) -> void:
	var d: Array = st["d"]
	var x: int = int(st["x2"])
	match int(st["jolt"]):
		0:
			x -= d[2]
			if x <= -d[6]:
				x = -d[6]
				d[7] = 2
				st["jolt"] = 1
		1:
			x += d[7]
			d[7] += 1
			if x >= 0:
				st["jolt"] = 2
		2:
			x += d[7]
			d[7] += 1
			if x > d[6]:
				x = d[6]
				st["jolt"] = 3
		3:
			if d[3] >= d[5]:
				st["jolt"] = 4
			else:
				x += d[4]
				d[4] *= -1
				d[3] += 1
		4:
			x -= 2
			if x <= 0:
				x = 0
				st["done"] = true
	st["x2"] = x


# ShakeFlashYellow + SetShakeFlashYellowPos
static func _flash_yellow(st: Dictionary) -> void:
	var d: Array = st["d"]
	var table: Array = FLASH_YELLOW_DATA[d[3]]
	# SetShakeFlashYellowPos -- reads d[1], which Task_HandleMonAnimation
	# left holding sDontFlip (1). Yields a +/-1px shake.
	st["x2"] = d[1]
	if d[0] > 1:
		d[1] *= -1
		d[0] = 0
	else:
		d[0] += 1
	if d[6] >= table.size() or table[d[6]][1] == 255:
		st["x2"] = 0
		st["blend_coeff"] = 0
		st["done"] = true
		return
	if d[4] == 1:
		st["blend_color"] = FLASH_YELLOW_COLOR
		st["blend_coeff"] = 16 if table[d[6]][0] == 1 else 0
		d[4] = 0
	if table[d[6]][1] == d[5]:
		d[4] = 1
		d[5] = 0
		d[6] += 1
	else:
		d[5] += 1


# Anim_ShakeGlow{Red,Green,Blue}{,_Fast,_Slow} + ShakeGlow_Blend/_Move
static func _shake_glow(st: Dictionary) -> void:
	var d: Array = st["d"]
	if d[2] % 2 == 0:
		# ShakeGlow_Blend
		if d[2] > 127:
			st["blend_coeff"] = 0
			st["done"] = true
		else:
			d[6] = sin_g(d[2], 12)
			st["blend_color"] = SHAKE_GLOW_COLORS[d[1]]
			st["blend_coeff"] = d[6]
	# Unguarded by `done` deliberately: source calls Blend and Move from the
	# same frame body, so the frame on which Blend finishes the animation
	# still runs Move once.
	if d[2] >= (128 - d[0] * d[4]) / 2:
		# ShakeGlow_Move
		if d[3] < d[4]:
			if d[5] > d[0]:
				d[3] += 1
				if d[3] < d[4]:
					d[5] = 0
				st["x2"] = 0
			else:
				var sign_: int = 1 - (d[3] % 2 * 2)
				st["x2"] = sign_ * sin_g((d[5] * 384 / d[0]) % 256, 6)
				d[5] += 1
	d[2] += 1


# --- Wall-clock driver ------------------------------------------------

## Accumulator that converts real elapsed seconds into whole GBA frames.
##
## Every discrete stepper B3-6a/6b shipped ties one step to one
## `create_timer`, which quantises UP to a frame boundary and runs ~10%
## slow at 144Hz (and half-speed at 30Hz). M26G4's own audit proposed
## exactly this accumulator as the fix. Holding the remainder across
## calls means the animation lasts the same wall-clock time at any
## refresh rate, and a slow frame catches up rather than dropping motion.
class Clock extends RefCounted:
	var _accum: float = 0.0

	## Frames elapsed since the last call, given a real delta in seconds.
	func advance(delta: float) -> int:
		_accum += delta
		var frames := int(_accum / GBA_FRAME_SECONDS)
		if frames > 0:
			_accum -= float(frames) * GBA_FRAME_SECONDS
		return frames

	func reset() -> void:
		_accum = 0.0
