class_name FieldAudio
extends Node

## [M27R 7a-1] The one audio player for the overworld — SE, fanfares, and the
## BGM stub seam.
##
## The counterpart to `AudioMap`: that file is the CATALOGUE, this one is the
## MECHANISM. It resolves nothing by name itself beyond asking `AudioMap`.
##
## ⚠️ **IT RECORDS EVERY CUE WHETHER OR NOT IT CAN PLAY IT, AND THAT IS THE
## WHOLE TESTING STRATEGY.** Audio is the one subsystem where no assertion can
## express "does this sound right" — so the thing that IS testable is *which cue
## fired, when, and what it resolved to*. `cues` is appended on every call,
## including off-tree where no `AudioStreamPlayer` exists at all, which is what
## lets a bare `ScriptVM` test prove a script asked for the right sound with no
## scene, no tree and no audio device. Same shape as the M36 animation VM's own
## `sound_cues()` accumulator, and deliberately so.
##
## ⚠️ **NOTHING HERE MAY HALT, WARN LOUDLY, OR THROW ON A MISSING ASSET.** Two
## reasons, both load-bearing. `run_overworld_tests.sh` fails a run on any
## engine `ERROR:` line, so a missing BGM folder would turn the whole suite red.
## And more importantly: every one of these opcodes was a working no-op before
## this tier, so a missing sound must stay a no-op. **Turning a silent success
## into a halt would be a regression dressed as a feature.**


## Emitted when a fanfare finishes — or immediately (deferred) when one could
## not start at all.
##
## ⚠️ **THE "COULD NOT START" CASE IS NOT A CONVENIENCE, IT IS THE G5 RULE.**
## `docs/m27g_scope.md`'s own standing rule is that a `native` handler must
## await something that ALWAYS FINISHES — a suspended handler cannot be
## cancelled and pins the scene. `WaitFanfare` awaits this signal, so a fanfare
## with no asset behind it (`MUS_LEVEL_UP`, today) must still emit, or 4
## corridor scripts would hang forever on a sound nobody can hear.
signal fanfare_finished

## The same contract for `waitse`.
signal se_finished


## How many SEs can overlap. Source's m4a engine has real channel priority and
## DirectSound allocation; that is hardware accommodation and is deliberately
## NOT ported (`docs/m26_f1_recon.md`'s M36-S note says the same). Six voices is
## a Godot-side choice — enough that a menu blip never cuts a door sound.
const SE_VOICES := 6

## Fade applied by `fadeoutbgm`/`fadedefaultbgm`, in seconds. A feel value, not
## a ported constant: source's own fade speeds vary per call site and nothing
## depends on matching one — the same call `FADE_SECONDS` already makes for the
## warp fade.
const BGM_FADE_SECONDS := 0.6

## Every cue this player has been asked for, in order.
## `{"kind": "se"/"fanfare"/"bgm"/"bgm_fade", "name": String,
##   "path": String, "played": bool}`
var cues: Array[Dictionary] = []

## Why the last cue did not play, when it did not. Empty on a clean cue. Read by
## tests rather than pushed to the log, matching the `strict`/`last_diagnostic`
## seam `MapManager.preload_tilesets` already established for exactly this
## reason (a warning there would fail the suite).
var last_diagnostic := ""

var _se_pool: Array[AudioStreamPlayer] = []
var _se_next := 0
var _me: AudioStreamPlayer = null
var _bgm: AudioStreamPlayer = null
var _bgm_tween: Tween = null
## The track `fadedefaultbgm` returns to — the last real `playbgm`.
var _default_bgm := ""
var _live := false


func _ready() -> void:
	for i in SE_VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Se%d" % i
		add_child(p)
		# ⚠️ Every voice reports, not just the newest. `waitse` releases on the
		# first SE to end rather than on a specific one — source's own
		# `IsSEPlaying` is likewise a global question, not a per-voice one.
		p.finished.connect(func() -> void: se_finished.emit())
		_se_pool.append(p)
	_me = AudioStreamPlayer.new()
	_me.name = "Fanfare"
	add_child(_me)
	_me.finished.connect(_on_fanfare_finished)
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "Bgm"
	add_child(_bgm)
	_live = true


## `playse SE_*`. Returns true if a sound actually started.
func play_se(name: String) -> bool:
	var path := AudioMap.se_path(name)
	var stream := _load(path)
	var played := false
	if stream != null and _live:
		var voice := _se_pool[_se_next]
		_se_next = (_se_next + 1) % SE_VOICES
		voice.stream = stream
		voice.play()
		played = true
	_record("se", name, path, played)
	if not played:
		# Always resolves, so `waitse` cannot hang on a sound that never started.
		call_deferred("emit_signal", "se_finished")
	return played


## [M27R 7c] A species' cry, through the same SE pool.
##
## ⚠️ **THE SE POOL, NOT A DEDICATED CHANNEL.** Source plays cries on the same
## DirectSound voices as other effects, and giving them their own player would
## let a cry and an effect that source would have cut short overlap instead.
## Records into `cues` like everything else, so a headless test can assert a cry
## was requested without any audio device existing.
func play_cry(dex: int) -> bool:
	var path := AudioMap.cry_path(dex)
	var stream := _load(path)
	var played := false
	if stream != null and _live:
		var voice := _se_pool[_se_next]
		_se_next = (_se_next + 1) % SE_VOICES
		voice.stream = stream
		voice.play()
		played = true
	_record("cry", "dex_%d" % dex, path, played)
	if not played:
		# Same contract as `play_se`: always resolves, so a `waitmoncry` can
		# never hang on a cry that never started.
		call_deferred("emit_signal", "se_finished")
	return played


## `playfanfare MUS_*`.
##
## ⚠️ **A FANFARE PAUSES THE MAP MUSIC AND RESUMES IT AFTER, which is behaviour
## a player notices** — source stops the map track for the jingle and restarts
## it, and letting the two overlap is immediately audible as wrong. Paused
## rather than faded so the track resumes where it left off, as source does.
func play_fanfare(name: String) -> bool:
	var path := AudioMap.me_path(name)
	var stream := _load(path)
	var played := false
	if _live:
		# ⚠️ **REPLACE, NEVER LAYER — source's `PlayFanfare` starts the new one
		# and the old one is gone.** Without the stop, asking for a fanfare that
		# cannot play leaves the PREVIOUS one running, and the very next
		# `waitfanfare` then blocks on the wrong jingle. `stop()` does not emit
		# `finished`, which is why the BGM un-pause below is explicit rather
		# than left to `_on_fanfare_finished`.
		_me.stop()
		if stream != null:
			if _bgm.playing:
				_bgm.stream_paused = true
			_me.stream = stream
			_me.play()
			played = true
		elif _bgm != null and _bgm.stream_paused:
			_bgm.stream_paused = false
	_record("fanfare", name, path, played)
	if not played:
		call_deferred("emit_signal", "fanfare_finished")
	return played


func is_fanfare_playing() -> bool:
	return _live and _me != null and _me.playing


## ⚠️ Exists for the SAME reason `is_fanfare_playing` does: `WaitSe` must not
## `await se_finished` unless a sound is genuinely in flight. `se_finished` is
## emitted on the FAILURE path (so a cue that never started still releases a
## waiter), which means a wait entered with nothing playing would suspend until
## the next failed cue — i.e. potentially forever. Checked, not assumed.
func is_se_playing() -> bool:
	if not _live:
		return false
	for v in _se_pool:
		if v.playing:
			return true
	return false


## `playbgm MUS_*`. ⚠️ **STUBBED BY DESIGN** — see `AudioMap.BGM_DIR`. The cue is
## recorded and the intended path is resolvable whether or not the asset exists,
## so the wiring is provable before Rob's folder lands.
func play_bgm(name: String) -> bool:
	var path := AudioMap.bgm_path(name)
	var stream := _load(path)
	var played := false
	if stream != null and _live:
		# Same track already running: do not restart it. Source does not either
		# — re-entering a Pokécentre mid-track would otherwise jump to the top.
		if _bgm.playing and _bgm.stream == stream:
			_record("bgm", name, path, true)
			return true
		_kill_fade()
		_bgm.stream = stream
		_bgm.volume_db = 0.0
		_bgm.stream_paused = false
		_bgm.play()
		played = true
	if not AudioMap.BGM.get(name, "").is_empty():
		_default_bgm = name
	_record("bgm", name, path, played)
	return played


## `fadeoutbgm speed`. Silence with no track queued behind it.
func fade_out_bgm() -> void:
	_record("bgm_fade", "", "", _fade_bgm_out())


## `fadedefaultbgm` — back to the map's own track. With no BGM assets this is
## indistinguishable from `fadeoutbgm`, which is honest rather than a shortcut:
## there is no default track to return TO yet. The name it would restore is
## recorded, so the seam is still observable.
func fade_default_bgm() -> void:
	var faded := _fade_bgm_out()
	_record("bgm_fade", _default_bgm, AudioMap.bgm_intent(_default_bgm), faded)


## Stop everything — a battle taking over, or a scene tearing down.
func stop_all() -> void:
	if not _live:
		return
	_kill_fade()
	for v in _se_pool:
		v.stop()
	_me.stop()
	_bgm.stop()


func _fade_bgm_out() -> bool:
	if not _live or _bgm == null or not _bgm.playing:
		return false
	_kill_fade()
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm, "volume_db", -60.0, BGM_FADE_SECONDS)
	_bgm_tween.tween_callback(_bgm.stop)
	return true


func _kill_fade() -> void:
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = null


func _on_fanfare_finished() -> void:
	if _bgm != null and _bgm.stream_paused:
		_bgm.stream_paused = false
	fanfare_finished.emit()


## ⚠️ `ResourceLoader.exists` FIRST, deliberately. A bare `load()` on a missing
## path pushes an engine ERROR, which fails the whole overworld suite — and a
## missing BGM folder is the EXPECTED state right now, not a fault. Same
## existence-check-as-a-question idiom as `ScriptVM._resolve_trade_held_item`.
func _load(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as AudioStream


func _record(kind: String, name: String, path: String, played: bool) -> void:
	cues.append({"kind": kind, "name": name, "path": path, "played": played})
	if played:
		last_diagnostic = ""
	elif path.is_empty():
		last_diagnostic = "%s '%s' is not mapped in AudioMap" % [kind, name]
	else:
		last_diagnostic = "%s '%s' -> %s (asset absent)" % [kind, name, path]
