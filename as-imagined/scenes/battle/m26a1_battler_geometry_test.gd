extends Node

# [M26A1 / 3:2 Phase 2] Battler geometry, derived from source rather than
# tuned by eye.
#
# `sBattlerCoords` (`src/battle_anim_mons.c`) defines exact battler screen
# coordinates on the GBA's 240x160 canvas. At a uniform 5x canvas (1200x800)
# placing a battler is arithmetic, so this suite asserts the arithmetic
# actually landed and keeps landing.
#
# ⚠️ **THE REAL SUBJECT HERE IS DRIFT, NOT PLACEMENT.** Getting six nodes
# right once is easy; the failure this project has actually suffered is a
# node quietly moving afterwards. `m25h1_bottom_region_test`'s own section 9
# records a `PlayerHealthGroupD1` whose `offset_bottom` was changed by an
# editor GUI drag with nothing to catch it, and Phase 0 of the 3:2 conversion
# found `m25h1_bottom_region_test` itself sitting red at 40/41 for two days
# because the battle suites are not in the routine overworld sweep. So every
# assertion below compares the SCENE against the GENERATED TABLE, which is
# the only pairing an editor drag can break.
#
# [Deliberately NOT tested here] whether the derived positions LOOK right.
# They are source-exact by construction; whether source's composition reads
# well at this sprite scale is a screenshot question for Rob, and the plan
# (`docs/m26a1_3to2_plan.md` Phase 2) is explicit that a derived position
# looking wrong is a finding to record, not a number to nudge.

const GBA := Vector2(240.0, 160.0)
const SINGLES_SCENE := "res://scenes/battle/battle_screen_singles.tscn"
const DOUBLES_SCENE := "res://scenes/battle/battle_screen_doubles.tscn"

# Which node draws which battler position. Mirrors `NODE_MAP` in
# `scripts/gen_battler_coords.py`; if the two ever disagree the per-node
# anchor assertions below fail, which is the intended outcome.
# ⚠️ The trainer sprites are included deliberately. They share their
# battler's box (a trainer portrait stands where the battler will stand), and
# `m26_trainer_category_party_test` already asserts the two AGREE -- but that
# is a relative claim, so both drifting together would satisfy it. Pinning
# them here against the table makes the position absolute.
const SINGLES_NODES := {
	"PlayerSprite0": "B_POSITION_PLAYER_LEFT",
	"OpponentSprite0": "B_POSITION_OPPONENT_LEFT",
	"PlayerTrainerSprite": "B_POSITION_PLAYER_LEFT",
	"OpponentTrainerSprite": "B_POSITION_OPPONENT_LEFT",
}
const DOUBLES_NODES := {
	"PlayerSprite0": "B_POSITION_PLAYER_LEFT",
	"PlayerSprite1": "B_POSITION_PLAYER_RIGHT",
	"OpponentSprite0": "B_POSITION_OPPONENT_LEFT",
	"OpponentSprite1": "B_POSITION_OPPONENT_RIGHT",
	"PlayerTrainerSprite": "B_POSITION_PLAYER_LEFT",
	"OpponentTrainerSprite": "B_POSITION_OPPONENT_LEFT",
}

# ⚠️ **DELIBERATE DIVERGENCE FROM `sBattlerCoords`, Rob's call, 2026-08-10.**
# The player battler in SINGLES was repositioned and enlarged by hand in the
# editor to sit correctly against the (separately, also by-eye) positioned
# player base-platform art -- source's own (72, 80) at the standard 320px box
# did not read right on this project's own canvas/base art. This is exactly
# the "a derived position looking wrong is a finding to record, not a number
# to nudge" case this file's own header comment anticipated -- recorded here
# as a real, pinned override rather than left as silent drift.
#
# `BattlerCoords.SINGLES["B_POSITION_PLAYER_LEFT"]` stays the literal source
# value untouched -- `_test_table_matches_source_values` below still enforces
# that -- only these two SINGLES nodes are checked against this override
# instead of the table. Opponent side, and both sides in doubles, are
# unaffected and still fully source-derived.
const SINGLES_PLAYER_OVERRIDE_NODES := ["PlayerSprite0", "PlayerTrainerSprite"]
const SINGLES_PLAYER_OVERRIDE_ANCHOR := Vector2(0.2370833, 0.598125)
const SINGLES_PLAYER_OVERRIDE_HALF_BOX := 178.5

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_canvas_is_a_uniform_gba_multiple()
	_test_table_matches_source_values()
	_test_singles_battlers_match_the_table()
	_test_doubles_battlers_match_the_table()
	_test_sprite_boxes_are_square_and_source_sized()
	_test_offsets_are_symmetric_about_the_anchor()
	_test_singles_does_not_use_the_right_positions()
	_test_singles_player_override()

	var total := _pass + _fail
	print("m26a1_battler_geometry_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % label)


# ── 1. The canvas invariant ───────────────────────────────────────────────
#
# ⚠️ **THIS ASSERTION REPLACED A REFACTOR, AND THE REASONING IS WORTH
# KEEPING.** The 3:2 plan originally proposed rewriting
# `AnimStage.pixel_scale()` from a float to a per-axis `Vector2`, to match
# `_weather_stage_scale()` and remove the 12.5% anisotropy the 4:3 canvas
# forced. Reading the code killed that plan: `pixel_scale()` has exactly ONE
# production consumer (`AnimBehaviors._scale`), and it scales ANIMATION
# OFFSETS. A uniform float keeps a diagonal offset at 45 degrees and a
# circular orbit circular; per-axis would skew both. Weather fills the screen
# so per-axis is right THERE; animations preserve shape so a float is right
# HERE. Neither was ever broken -- the recon said so and I misread it.
#
# The genuine hazard is the CANVAS silently ceasing to be a uniform GBA
# multiple, which is what made the two disagree in the first place. So that
# is what gets pinned. If someone sets a non-3:2 resolution this fails
# immediately and loudly, and whoever did it has to re-decide the mapping
# rather than inherit a silent 12.5% squash on 779 move animations.
func _test_canvas_is_a_uniform_gba_multiple() -> void:
	var w: float = float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var h: float = float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var sx: float = w / GBA.x
	var sy: float = h / GBA.y

	_chk("the canvas scales GBA identically on both axes (no anisotropy to choose sides on)",
			is_equal_approx(sx, sy))
	_chk("the canvas is exactly 5x GBA (1200x800)", is_equal_approx(sx, 5.0))
	# Pinned separately from the ratio: a 600x400 canvas is also uniform 2.5x
	# and would satisfy the check above while halving everything on screen.
	_chk("viewport is 1200x800", is_equal_approx(w, 1200.0) and is_equal_approx(h, 800.0))
	# M26A1 recorded choosing "keep" and the setting was simply absent, so
	# intent and config disagreed until the 3:2 conversion. Now explicit.
	_chk("stretch aspect is explicitly 'keep', so letterboxing preserves the visible world area",
			str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "keep")


# ── 2. The generated table still carries source's real numbers ────────────
#
# Guards the PARSE, not the placement. A generator that silently matched
# nothing would emit an empty table, and every per-node assertion below would
# then compare (0,0) against (0,0) and pass. These four values are read
# straight out of `sBattlerCoords` and are the discriminator that makes the
# rest of this suite mean something.
func _test_table_matches_source_values() -> void:
	_chk("singles PLAYER_LEFT is source's (72, 80)",
			BattlerCoords.SINGLES.get("B_POSITION_PLAYER_LEFT") == Vector2i(72, 80))
	_chk("singles OPPONENT_LEFT is source's (176, 40)",
			BattlerCoords.SINGLES.get("B_POSITION_OPPONENT_LEFT") == Vector2i(176, 40))
	_chk("doubles PLAYER_RIGHT is source's (90, 84)",
			BattlerCoords.DOUBLES.get("B_POSITION_PLAYER_RIGHT") == Vector2i(90, 84))
	_chk("doubles OPPONENT_RIGHT is source's (152, 32)",
			BattlerCoords.DOUBLES.get("B_POSITION_OPPONENT_RIGHT") == Vector2i(152, 32))
	_chk("both tables carry all four battler positions",
			BattlerCoords.SINGLES.size() == 4 and BattlerCoords.DOUBLES.size() == 4)
	# ⚠️ The two tables are genuinely different data, not one table reused.
	# A generator bug that emitted the singles block twice would leave every
	# other assertion here green, because singles is checked first.
	_chk("the doubles table is not a copy of the singles table",
			BattlerCoords.SINGLES.get("B_POSITION_PLAYER_LEFT")
			!= BattlerCoords.DOUBLES.get("B_POSITION_PLAYER_LEFT"))


# ── 3-4. Scene nodes sit where the table says ─────────────────────────────

func _check_scene_against_table(scene_path: String, nodes: Dictionary, table: Dictionary) -> void:
	var instance: Node = (load(scene_path) as PackedScene).instantiate()
	for node_name in nodes:
		# The two overridden SINGLES nodes are checked separately, against the
		# override, not the table -- see `_test_singles_player_override`.
		if scene_path == SINGLES_SCENE and node_name in SINGLES_PLAYER_OVERRIDE_NODES:
			continue
		var pos_key: String = nodes[node_name]
		var sprite: Control = instance.get_node("BattleStage/%s" % node_name) as Control
		_chk("%s exists" % node_name, sprite != null)
		if sprite == null:
			continue
		var want: Vector2 = BattlerCoords.anchor_for(table, pos_key)
		# A point anchor: left==right and top==bottom, with the box carried
		# entirely by the offsets. Asserted rather than assumed, because a
		# stretched anchor pair would still place the node plausibly while
		# making it resize with the canvas.
		#
		# ⚠️ **THIS ASSERTION CAN ONLY CATCH A *STRETCHED* PAIR, NEVER AN
		# INVERTED ONE, AND THE REASON COST A FALSE "VACUOUS GUARD" VERDICT.**
		# Godot's anchor setter pushes the opposite anchor to preserve
		# `left <= right`, so a `.tscn` written with `anchor_left = 0.32`
		# above `anchor_right = 0.30` loads with BOTH at 0.30 -- the
		# inconsistent state is simply unrepresentable. An injection that
		# edits one side of a point anchor therefore proves nothing: it is
		# normalised away before any assertion sees it, and the suite comes
		# back green looking exactly like a guard that does not work.
		#
		# To break this suite deliberately, move BOTH sides together, which
		# is also what a real editor drag does. That injection is confirmed
		# to fail the position assertion below, and only that one.
		_chk("%s is a POINT anchor (left==right, top==bottom)" % node_name,
				is_equal_approx(sprite.anchor_left, sprite.anchor_right)
				and is_equal_approx(sprite.anchor_top, sprite.anchor_bottom))
		_chk("%s sits at %s x scale, i.e. anchor (%.4f, %.4f)" % [node_name, pos_key, want.x, want.y],
				absf(sprite.anchor_left - want.x) < 0.0005
				and absf(sprite.anchor_top - want.y) < 0.0005)
	instance.queue_free()


func _test_singles_battlers_match_the_table() -> void:
	_check_scene_against_table(SINGLES_SCENE, SINGLES_NODES, BattlerCoords.SINGLES)


func _test_doubles_battlers_match_the_table() -> void:
	_check_scene_against_table(DOUBLES_SCENE, DOUBLES_NODES, BattlerCoords.DOUBLES)


# ── 5. The sprite box ─────────────────────────────────────────────────────
#
# ⚠️ **SQUARE IS THE LOAD-BEARING HALF.** A battler sprite is 64x64 on
# hardware, so the box is kept square and in PIXELS rather than expressed as
# anchors -- a proportional box would distort on any future aspect change,
# and a non-square battler is wrong in a way correct positioning does not
# rescue. Before this phase the six boxes were 312, 292 and 131 pixels
# depending on which node you looked at, none of them derived from anything.
func _test_sprite_boxes_are_square_and_source_sized() -> void:
	var expect: float = BattlerCoords.GBA_SPRITE_SIZE * 5.0
	for entry in [[SINGLES_SCENE, SINGLES_NODES], [DOUBLES_SCENE, DOUBLES_NODES]]:
		var instance: Node = (load(entry[0] as String) as PackedScene).instantiate()
		for node_name in (entry[1] as Dictionary):
			# Overridden separately -- its box is deliberately NOT 5x GBA. See
			# `_test_singles_player_override`.
			if entry[0] == SINGLES_SCENE and node_name in SINGLES_PLAYER_OVERRIDE_NODES:
				continue
			var sprite: Control = instance.get_node("BattleStage/%s" % node_name) as Control
			if sprite == null:
				continue
			var w: float = sprite.offset_right - sprite.offset_left
			var h: float = sprite.offset_bottom - sprite.offset_top
			_chk("%s box is square" % node_name, is_equal_approx(w, h))
			_chk("%s box is 5x the GBA's own 64x64 sprite (%d px)" % [node_name, int(expect)],
					absf(w - expect) < 0.5)
		instance.queue_free()


# ── 6. The box is CENTRED on the anchor ───────────────────────────────────
#
# `sBattlerCoords` is the sprite's CENTRE, so the offsets must be symmetric.
# Asymmetric offsets would still put the box near the right place and would
# put the sprite's centre somewhere source never specified -- which is
# exactly the class of drift that produced the pre-Phase-2 layout.
func _test_offsets_are_symmetric_about_the_anchor() -> void:
	for entry in [[SINGLES_SCENE, SINGLES_NODES], [DOUBLES_SCENE, DOUBLES_NODES]]:
		var instance: Node = (load(entry[0] as String) as PackedScene).instantiate()
		for node_name in (entry[1] as Dictionary):
			var sprite: Control = instance.get_node("BattleStage/%s" % node_name) as Control
			if sprite == null:
				continue
			_chk("%s offsets are symmetric, so the anchor is the sprite's centre" % node_name,
					is_equal_approx(sprite.offset_left, -sprite.offset_right)
					and is_equal_approx(sprite.offset_top, -sprite.offset_bottom))
		instance.queue_free()


# ── 7. Singles uses only the two LEFT positions ───────────────────────────
#
# ⚠️ **The singles table's `_RIGHT` entries are REAL DATA and are deliberately
# unused.** Source reaches them through move animations that borrow a second
# slot, not through battler placement. A singles battler placed at (48, 40)
# or (112, 80) would look entirely plausible on screen and be wrong, so this
# pins that neither singles node sits on one.
func _test_singles_does_not_use_the_right_positions() -> void:
	var instance: Node = (load(SINGLES_SCENE) as PackedScene).instantiate()
	var forbidden: Array = [
		BattlerCoords.anchor_for(BattlerCoords.SINGLES, "B_POSITION_PLAYER_RIGHT"),
		BattlerCoords.anchor_for(BattlerCoords.SINGLES, "B_POSITION_OPPONENT_RIGHT"),
	]
	for node_name in SINGLES_NODES:
		var sprite: Control = instance.get_node("BattleStage/%s" % node_name) as Control
		if sprite == null:
			continue
		var here := Vector2(sprite.anchor_left, sprite.anchor_top)
		var clashes := false
		for f in forbidden:
			if here.distance_to(f as Vector2) < 0.0005:
				clashes = true
		_chk("%s is not placed on a singles _RIGHT coordinate" % node_name, not clashes)
	instance.queue_free()


# ── 8. The deliberate SINGLES player override ─────────────────────────────
#
# Pinned separately from the generic source-derived checks above -- this is
# the "looking-wrong finding" this suite's header comment says gets recorded
# rather than silently nudged. Still a drift guard: an editor drag away from
# THIS anchor now fails here, same as any other node failing against the
# table.
func _test_singles_player_override() -> void:
	var instance: Node = (load(SINGLES_SCENE) as PackedScene).instantiate()
	for node_name in SINGLES_PLAYER_OVERRIDE_NODES:
		var sprite: Control = instance.get_node("BattleStage/%s" % node_name) as Control
		_chk("%s exists" % node_name, sprite != null)
		if sprite == null:
			continue
		_chk("%s is a POINT anchor (left==right, top==bottom)" % node_name,
				is_equal_approx(sprite.anchor_left, sprite.anchor_right)
				and is_equal_approx(sprite.anchor_top, sprite.anchor_bottom))
		_chk("%s sits at the deliberate override anchor (%.4f, %.4f)"
				% [node_name, SINGLES_PLAYER_OVERRIDE_ANCHOR.x, SINGLES_PLAYER_OVERRIDE_ANCHOR.y],
				absf(sprite.anchor_left - SINGLES_PLAYER_OVERRIDE_ANCHOR.x) < 0.0005
				and absf(sprite.anchor_top - SINGLES_PLAYER_OVERRIDE_ANCHOR.y) < 0.0005)
		var w: float = sprite.offset_right - sprite.offset_left
		var h: float = sprite.offset_bottom - sprite.offset_top
		_chk("%s box is square" % node_name, is_equal_approx(w, h))
		_chk("%s box is the deliberate override size (%d px)" % [node_name, int(SINGLES_PLAYER_OVERRIDE_HALF_BOX * 2)],
				absf(w - SINGLES_PLAYER_OVERRIDE_HALF_BOX * 2) < 0.5)
	instance.queue_free()
