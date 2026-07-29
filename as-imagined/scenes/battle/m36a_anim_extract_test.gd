extends Node

# [M36A] Data-integrity suite for the battle-animation extraction (Phase A of
# the Move Animation Engine -- scope of record docs/m26_f1_recon.md).
#
# What this asserts, and why each check exists rather than just "the files
# parse": the three extractors produce data the M36B VM will execute blind,
# so every cross-file REFERENCE is a place a silent extraction bug could hide
# -- a script naming a template that does not exist, a template naming a tag
# with no sheet, a frame table naming a sequence in the wrong translation
# unit. Those are checked here exhaustively (not by sampling), because they
# are exactly the failures that would otherwise surface much later as a move
# silently falling back to the generic effect.
#
# Deliberately NOT asserted: visual correctness of any sprite, or that a
# script "looks right" -- this is an extraction-integrity suite, not a
# rendering one. The behaviour side belongs to M36B/M36C.

var _pass := 0
var _fail := 0

const DATA_DIR := "res://data/battle_anims"
const SPRITE_DIR := "res://assets/sprites/battle_anims"

# Recon-verified upstream counts. These are the figures docs/m26_f1_recon.md
# was written against; if the reference clone is updated and these move, the
# suite should fail loudly rather than let the recon's own numbers go stale.
const EXPECTED_MOVE_EXPORTS := 941
const EXPECTED_GENERAL := 64
const EXPECTED_STATUS := 10
const EXPECTED_SPECIAL := 8
const EXPECTED_TAG_ROWS := 412       # 411 macro rows + 1 hand-written literal
const EXPECTED_SPRITE_FILES := 410   # minus the two explicit NULL rows
const ANIM_SPRITES_START := 10000

# The 12 opcodes the recon measured as >96% of all usage -- M36B implements
# these first, so their presence in the extracted program is load-bearing.
const CORE_OPCODES := [
	"createsprite", "delay", "createvisualtask", "waitforvisualfinish",
	"call", "return", "end", "goto", "monbg", "clearmonbg", "setalpha",
	"blendoff",
]

var _scripts: Dictionary = {}
var _tags: Dictionary = {}
var _templates: Dictionary = {}
var _frames: Dictionary = {}
var _sprite_index: Dictionary = {}


func _ready() -> void:
	if not _load_all():
		print("m36a_anim_extract_test: 0/1 passed")
		print("FAILED")
		get_tree().quit(1)
		return

	_test_script_program()
	_test_dispatch_tables()
	_test_tag_table()
	_test_templates()
	_test_frame_data()
	_test_sprite_files()
	_test_cross_references()

	var total := _pass + _fail
	print("m36a_anim_extract_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _load_all() -> bool:
	_scripts = _read_json(DATA_DIR + "/scripts.json")
	_tags = _read_json(DATA_DIR + "/tags.json")
	_templates = _read_json(DATA_DIR + "/templates.json")
	_frames = _read_json(DATA_DIR + "/frames.json")
	_sprite_index = _read_json(SPRITE_DIR + "/index.json")
	for pair in [["scripts", _scripts], ["tags", _tags],
			["templates", _templates], ["frames", _frames],
			["sprite index", _sprite_index]]:
		if (pair[1] as Dictionary).is_empty():
			print("FAIL  %s json missing or unparseable" % pair[0])
			return false
	return true


# ── A1: the extracted program ─────────────────────────────────────────────

func _test_script_program() -> void:
	var commands: Array = _scripts.get("commands", [])
	var labels: Dictionary = _scripts.get("labels", {})
	var exports: Array = _scripts.get("exports", [])

	_chk("scripts.json carries a non-empty command program", commands.size() > 0)
	_chk("scripts.json defines labels", labels.size() > 0)

	var move_exports := 0
	for name in exports:
		if (name as String).begins_with("gBattleAnimMove_"):
			move_exports += 1
	_chk("exactly %d gBattleAnimMove_ labels exported (got %d)"
			% [EXPECTED_MOVE_EXPORTS, move_exports],
			move_exports == EXPECTED_MOVE_EXPORTS)

	# Every label must point at a real index inside the program. An
	# off-by-one here would send the VM into another script's body.
	var bad_label := ""
	for name in labels:
		var idx: int = int(labels[name])
		if idx < 0 or idx > commands.size():
			bad_label = str(name)
			break
	_chk("every label indexes inside the command array (bad: '%s')" % bad_label,
			bad_label == "")

	# Every command must be a non-empty array whose head is a known opcode
	# name -- i.e. the extractor never emitted a malformed row.
	var signatures: Dictionary = _scripts.get("meta", {}).get(
			"opcode_signatures", {})
	_chk("opcode signature table is published for the VM",
			signatures.size() > 0)
	var bad_op := ""
	var bad_arity := ""
	for cmd in commands:
		if not (cmd is Array) or (cmd as Array).is_empty():
			bad_op = "<malformed row>"
			break
		var op: String = str((cmd as Array)[0])
		if not signatures.has(op):
			bad_op = op
			break
		# Row width must match the signature exactly (fields + variadic list).
		var expected: int = (signatures[op] as Array).size() + 1
		if (cmd as Array).size() != expected:
			bad_arity = "%s (%d vs %d)" % [op, (cmd as Array).size(), expected]
			break
	_chk("every command's opcode is in the signature table (bad: '%s')"
			% bad_op, bad_op == "")
	_chk("every command's field count matches its signature (bad: '%s')"
			% bad_arity, bad_arity == "")

	for op in CORE_OPCODES:
		_chk("core opcode '%s' is present in the signature table" % op,
				signatures.has(op))

	# Aliased labels are a real upstream property (None/MirrorMove/Pound share
	# one body); assert it survived rather than being silently de-duplicated.
	if labels.has("gBattleAnimMove_Pound") and labels.has("gBattleAnimMove_None"):
		_chk("aliased labels resolve to the same body (None == Pound)",
				int(labels["gBattleAnimMove_None"])
				== int(labels["gBattleAnimMove_Pound"]))

	# Spot-check one fully-known script end to end: Pound's exact opcode
	# sequence, verified by hand against data/battle_anim_scripts.s.
	if labels.has("gBattleAnimMove_Pound"):
		var at: int = int(labels["gBattleAnimMove_Pound"])
		var seq: Array[String] = []
		for i in range(at, mini(at + 9, commands.size())):
			seq.append(str((commands[i] as Array)[0]))
		var expected_pound: Array[String] = [
			"monbg", "setalpha", "playsewithpan", "createsprite",
			"createvisualtask", "waitforvisualfinish", "clearmonbg",
			"blendoff", "end",
		]
		_chk("Pound's opcode sequence matches source exactly (got %s)"
				% str(seq), seq == expected_pound)


func _test_dispatch_tables() -> void:
	var moves: Dictionary = _scripts.get("moves", {})
	var labels: Dictionary = _scripts.get("labels", {})

	_chk("move-id bindings extracted (%d)" % moves.size(), moves.size() > 900)
	_chk("general table has %d entries" % EXPECTED_GENERAL,
			(_scripts.get("general", {}) as Dictionary).size()
			== EXPECTED_GENERAL)
	_chk("status table has %d entries" % EXPECTED_STATUS,
			(_scripts.get("status", {}) as Dictionary).size()
			== EXPECTED_STATUS)
	_chk("special table has %d entries" % EXPECTED_SPECIAL,
			(_scripts.get("special", {}) as Dictionary).size()
			== EXPECTED_SPECIAL)

	# Every bound label must exist -- a dangling one means the VM would have
	# no program to run for that move.
	var dangling := ""
	for move_id in moves:
		if not labels.has(moves[move_id]):
			dangling = "%s -> %s" % [move_id, moves[move_id]]
			break
	_chk("every move binding names a defined label (bad: '%s')" % dangling,
			dangling == "")

	# Move ids are this project's own ids; check two known ones rather than
	# trusting the join blindly.
	_chk("move 53 binds to Flamethrower's script",
			str(moves.get("53", "")) == "gBattleAnimMove_Flamethrower")
	_chk("move 57 binds to Surf's script",
			str(moves.get("57", "")) == "gBattleAnimMove_Surf")


# ── A2: tags / templates / frames ─────────────────────────────────────────

func _test_tag_table() -> void:
	var tags: Dictionary = _tags.get("tags", {})
	_chk("tag table has %d rows (got %d)" % [EXPECTED_TAG_ROWS, tags.size()],
			tags.size() == EXPECTED_TAG_ROWS)

	var null_rows := 0
	var bad_index := ""
	var indices := {}
	for name in tags:
		var row: Dictionary = tags[name]
		if row.get("gfx") == null:
			null_rows += 1
		var idx: int = int(row.get("index", -1))
		if idx < 0 or idx >= 413:
			bad_index = str(name)
		indices[idx] = true
	_chk("exactly 2 explicit NULL rows survive (UNAVAILABLE_1/2), got %d"
			% null_rows, null_rows == 2)
	_chk("every tag index is inside the ANIM_TAG space (bad: '%s')" % bad_index,
			bad_index == "")
	_chk("tag indices are unique (%d distinct)" % indices.size(),
			indices.size() == tags.size())

	# The hand-written SAP_DRIP_2 row is the one upstream asymmetry: its
	# palette registers under a DIFFERENT tag. Assert it survived extraction,
	# because a "tidying" refactor would silently normalise it away.
	if tags.has("ANIM_TAG_SAP_DRIP_2"):
		_chk("SAP_DRIP_2's palette_tag is the asymmetric ANIM_TAG_SAP_DRIP",
				str((tags["ANIM_TAG_SAP_DRIP_2"] as Dictionary)
					.get("palette_tag", "")) == "ANIM_TAG_SAP_DRIP")


func _test_templates() -> void:
	var templates: Dictionary = _templates.get("templates", {})
	_chk("templates extracted (%d, recon expected ~1,148)" % templates.size(),
			templates.size() > 1100)

	var oam_decoded := 0
	var with_callback := 0
	for name in templates:
		var t: Dictionary = templates[name]
		var oam: Dictionary = t.get("oam", {})
		if oam.has("width") and oam.has("height"):
			oam_decoded += 1
		if t.get("callback") != null:
			with_callback += 1
	_chk("most templates decode a real OAM size (%d/%d)"
			% [oam_decoded, templates.size()],
			oam_decoded > int(templates.size() * 0.9))
	_chk("most templates name a sprite callback (%d/%d)"
			% [with_callback, templates.size()],
			with_callback > int(templates.size() * 0.9))

	# One known template checked field by field.
	if templates.has("gFlamethrowerFlameSpriteTemplate"):
		var f: Dictionary = templates["gFlamethrowerFlameSpriteTemplate"]
		_chk("Flamethrower's flame template uses ANIM_TAG_SMALL_EMBER",
				str((f.get("tile_tag", {}) as Dictionary).get("name", ""))
				== "ANIM_TAG_SMALL_EMBER")
		_chk("Flamethrower's flame template callback is AnimToTargetInSinWave",
				str(f.get("callback", "")) == "AnimToTargetInSinWave")
		_chk("Flamethrower's flame template is 32x32",
				int((f.get("oam", {}) as Dictionary).get("width", 0)) == 32
				and int((f.get("oam", {}) as Dictionary).get("height", 0)) == 32)


func _test_frame_data() -> void:
	var anims: Dictionary = _frames.get("anims", {})
	var affine: Dictionary = _frames.get("affine", {})
	_chk("frame sequences extracted (%d)" % anims.size(), anims.size() > 200)
	_chk("affine sequences extracted (%d)" % affine.size(), affine.size() > 200)

	# Keys are file-qualified because two static symbols genuinely collide
	# across translation units; a flat namespace would have dropped one.
	var qualified := true
	for key in anims:
		if not (key as String).contains("::"):
			qualified = false
			break
	_chk("frame-sequence keys are file-qualified ('file.c::symbol')", qualified)

	var frame_entries := 0
	for key in anims:
		for entry in (anims[key] as Array):
			if entry is Dictionary and (entry as Dictionary).has("tile"):
				frame_entries += 1
	_chk("ANIMCMD_FRAME entries extracted (%d, source has 784)"
			% frame_entries, frame_entries == 784)


# ── A3: the pulled sprites ────────────────────────────────────────────────

func _test_sprite_files() -> void:
	var sprites: Dictionary = _sprite_index.get("sprites", {})
	_chk("sprite index lists %d sheets (got %d)"
			% [EXPECTED_SPRITE_FILES, sprites.size()],
			sprites.size() == EXPECTED_SPRITE_FILES)

	var dir := DirAccess.open(SPRITE_DIR)
	_chk("%s exists and is openable" % SPRITE_DIR, dir != null)
	if dir == null:
		return

	var on_disk := 0
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			on_disk += 1
		filename = dir.get_next()
	dir.list_dir_end()
	_chk("PNG count on disk matches the index (%d vs %d)"
			% [on_disk, sprites.size()], on_disk == sprites.size())

	# Every indexed sheet must load, be non-empty, carry index-0 transparency,
	# and be tile-aligned -- tile alignment is what makes ANIMCMD_FRAME's
	# tile offsets addressable at all.
	var checked := 0
	var bad_load := ""
	var bad_align := ""
	var bad_geom := ""
	for tag in sprites:
		var e: Dictionary = sprites[tag]
		var path: String = "%s/%s" % [SPRITE_DIR, e.get("file", "")]
		var res: Resource = load(path)
		if res == null or not (res is Texture2D):
			bad_load = str(tag)
			break
		var tex := res as Texture2D
		var size := tex.get_size()
		if int(size.x) % 8 != 0 or int(size.y) % 8 != 0 or size.x <= 0:
			bad_align = str(tag)
			break
		if int(size.x) != int(e.get("width", -1)) \
				or int(size.y) != int(e.get("height", -1)):
			bad_geom = "%s (%dx%d vs indexed %sx%s)" % [tag, int(size.x),
					int(size.y), e.get("width"), e.get("height")]
			break
		checked += 1
	_chk("every indexed sheet loads as a Texture2D (bad: '%s')" % bad_load,
			bad_load == "")
	_chk("every sheet is 8px tile-aligned (bad: '%s')" % bad_align,
			bad_align == "")
	_chk("every sheet's real size matches the index (bad: '%s')" % bad_geom,
			bad_geom == "")
	_chk("all %d sheets were geometry-checked" % checked,
			checked == sprites.size())

	# The five assembled composites must carry exactly the tile count their
	# tag's VRAM size declares -- the assertion that catches a mis-assembly.
	var tags: Dictionary = _tags.get("tags", {})
	var composite_checked := 0
	for tag in sprites:
		if not tags.has(tag):
			continue
		var row: Dictionary = tags[tag]
		if str(row.get("gfx_kind", "")) != "composite":
			continue
		composite_checked += 1
		var declared: int = int(row.get("size", 0)) / 32
		var have: int = int((sprites[tag] as Dictionary).get("tiles", -1))
		_chk("composite %s holds >= its declared %d tiles (has %d)"
				% [tag, declared, have], have >= declared)
	_chk("all 5 build-time composites were assembled and checked",
			composite_checked == 5)

	# Transparency: sample a handful rather than decoding 410 images, but
	# require the sample to be uniform.
	var sampled := 0
	for tag in ["ANIM_TAG_IMPACT", "ANIM_TAG_SMALL_EMBER", "ANIM_TAG_SPARK",
			"ANIM_TAG_ICE_CUBE", "ANIM_TAG_FLOWER"]:
		if not sprites.has(tag):
			continue
		var tex := load("%s/%s" % [SPRITE_DIR,
				(sprites[tag] as Dictionary).get("file", "")]) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		_chk("%s uses palette index 0 as transparent" % tag,
				img != null and img.get_pixel(0, 0).a == 0.0)
		sampled += 1
	_chk("transparency sample covered 5 sheets", sampled == 5)


# ── Cross-file integrity: the checks that matter most for M36B ────────────

func _test_cross_references() -> void:
	var commands: Array = _scripts.get("commands", [])
	var labels: Dictionary = _scripts.get("labels", {})
	var templates: Dictionary = _templates.get("templates", {})
	var tags: Dictionary = _tags.get("tags", {})
	var sprites: Dictionary = _sprite_index.get("sprites", {})
	var anims: Dictionary = _frames.get("anims", {})
	var affine: Dictionary = _frames.get("affine", {})
	var anim_tables: Dictionary = _frames.get("anim_tables", {})
	var affine_tables: Dictionary = _frames.get("affine_tables", {})

	# 1. Every createsprite names a template that exists; every jump names a
	#    label that exists. These two are what a fallback check will consult.
	var missing_template := ""
	var missing_label := ""
	var jump_ops := {"call": 1, "goto": 1, "jumpifcontest": 1}
	for cmd in commands:
		var row: Array = cmd
		var op: String = str(row[0])
		if op.begins_with("createsprite") and row.size() > 1:
			var tname: String = str(row[1])
			if not templates.has(tname):
				missing_template = tname
				break
		elif jump_ops.has(op) and row.size() > 1:
			if not labels.has(str(row[1])):
				missing_label = str(row[1])
				break
		elif op == "choosetwoturnanim" and row.size() > 2:
			if not labels.has(str(row[1])) or not labels.has(str(row[2])):
				missing_label = "%s / %s" % [row[1], row[2]]
				break
	_chk("every createsprite names an extracted template (missing: '%s')"
			% missing_template, missing_template == "")
	_chk("every jump target names a defined label (missing: '%s')"
			% missing_label, missing_label == "")

	# 2. Every template's tile tag resolves to a pulled sheet (or to one of
	#    the two legitimately-empty NULL rows).
	var missing_sheet := ""
	var resolved := 0
	for name in templates:
		var t: Dictionary = templates[name]
		var tag_name: Variant = (t.get("tile_tag", {}) as Dictionary).get("name")
		if tag_name == null:
			continue  # tileTag 0: the invisible "controller sprite" idiom
		var tag: String = str(tag_name)
		if not tags.has(tag):
			continue  # non-ANIM_TAG tile tags (ball/status sheets, etc.)
		if (tags[tag] as Dictionary).get("gfx") == null:
			continue  # UNAVAILABLE_1/2
		if not sprites.has(tag):
			missing_sheet = "%s -> %s" % [name, tag]
			break
		resolved += 1
	_chk("every template's ANIM_TAG resolves to a pulled sheet (missing: '%s')"
			% missing_sheet, missing_sheet == "")
	_chk("template->sheet resolution covered %d templates" % resolved,
			resolved > 900)

	# 3. Every anims/affineAnims key on a template resolves into frames.json,
	#    and every table entry resolves to a real sequence. This is the chain
	#    the renderer walks per sprite.
	var missing_table := ""
	var missing_seq := ""
	for name in templates:
		var t: Dictionary = templates[name]
		var akey: Variant = t.get("anims_key")
		if akey != null and not anim_tables.has(str(akey)):
			missing_table = "%s -> %s" % [name, akey]
			break
		var fkey: Variant = t.get("affine_anims_key")
		if fkey != null and not affine_tables.has(str(fkey)):
			missing_table = "%s -> %s (affine)" % [name, fkey]
			break
	for key in anim_tables:
		for entry in (anim_tables[key] as Array):
			if not anims.has(str(entry)):
				missing_seq = str(entry)
				break
		if missing_seq != "":
			break
	for key in affine_tables:
		for entry in (affine_tables[key] as Array):
			if not affine.has(str(entry)):
				missing_seq = str(entry) + " (affine)"
				break
		if missing_seq != "":
			break
	_chk("every template's frame table resolves (missing: '%s')"
			% missing_table, missing_table == "")
	_chk("every frame-table entry resolves to a sequence (missing: '%s')"
			% missing_seq, missing_seq == "")

	# 4. The end-to-end chain for one real move: Flamethrower's script ->
	#    its flame template -> its tag -> its sheet -> its frame sequence.
	if labels.has("FlamethrowerCreateFlames"):
		var at: int = int(labels["FlamethrowerCreateFlames"])
		var row: Array = commands[at]
		var ok: bool = str(row[0]) == "createsprite" \
				and str(row[1]) == "gFlamethrowerFlameSpriteTemplate"
		_chk("Flamethrower's subroutine creates the flame sprite", ok)
		if ok:
			var t: Dictionary = templates[str(row[1])]
			var tag: String = str((t.get("tile_tag", {}) as Dictionary)
					.get("name", ""))
			_chk("...whose tag has a pulled sheet on disk",
					sprites.has(tag)
					and FileAccess.file_exists("%s/%s" % [SPRITE_DIR,
						(sprites[tag] as Dictionary).get("file", "")]))
			var akey: String = str(t.get("anims_key", ""))
			_chk("...and whose frame table resolves to a real sequence",
					anim_tables.has(akey)
					and anims.has(str((anim_tables[akey] as Array)[0])))
