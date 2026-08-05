# M36-S Recon: SFX & Audio Surface

**Scope of this document:** M36-S ("SFX & audio surface"), the one M36
sub-tier never actually investigated before now — every other M36 phase
(A-H) has real scoping; M36-S existed only as a name on the roadmap. This is
Step 0 for it: real source citations, no implementation.

**Wider framing, confirmed directly (not assumed):** this project ships
**zero audio of any kind** anywhere — no music, no SFX, no cries. Confirmed
via `grep -rln "AudioStreamPlayer" scripts/ scenes/` returning zero hits
project-wide, and via the M36 VM's own code comments (`anim_script_vm.gd`,
`anim_behaviors.gd`), which explicitly document every sound opcode as a
"structured no-op ... audio is M36-S." This recon is therefore scoping the
very first audio work this project has ever done, not just one move-effects
tier.

---

## TL;DR

1. **Format verdict:** every sound in the reference engine — music AND
   sound effects alike, no distinction — is a compiled **tracker "song"**
   (the GBA's "Sappy"/m4a engine), never a standalone playable clip. The
   checked-in source tree **does** contain real, human-readable **MIDI
   files** for every SFX (something earlier phases' "just flat-copy it"
   assumption would not have predicted) — but a raw `.mid` played back with
   a generic soundfont gets the right notes/rhythm and the **wrong
   instrument timbre**, because the real timbre comes from GBA-native
   instrument samples (`voicegroups`) this project's own audio stack has no
   equivalent for. There is no single file per SFX to just copy, the way
   sprites/tiles/fonts worked in every prior M36 phase.
2. **Real scale:** **147 distinct `SE_*` sound constants** referenced from
   move-animation scripts (129 move-specific `SE_M_*` + 18 shared/generic),
   across **~3,546 real call sites** — an average reuse factor of ~24×,
   matching the same "one asset, many moves" pattern M36's own sprite-tag
   pull already found. Move-SFX coverage is **orthogonal to M36's own
   779/845-move playability figure** — every sound opcode has always been a
   zero-cost no-op, so a move's visual playability says nothing about
   whether its SFX exists; this is a wholly separate, unstarted axis.
3. **Cries verdict: mechanically SIMPLER than move SFX, not harder** —
   contrary to the intuitive "386 species vs. a few hundred effects, so
   cries are the bigger job" framing. Cries are real, standalone, per-species
   `.wav` files (both in the reference source tree, 1,161 of them, **and** in
   the vendored Essentials pack, 655 of them, name-keyed exactly the way
   this project's existing sprite pulls already key by species). Move SFX,
   by contrast, need a from-scratch two-layer synth (MIDI notes + GBA
   instrument samples) to render at all from the reference tree alone.
   **Recommendation: cries and move-SFX are two structurally different
   problems and should be two separate milestone items — but if only one
   ships first, cries are the cheaper, more source-faithful one.**
4. **Proposed phasing:** see §4. Headline recommendation — skip trying to
   synthesize the reference tree's own MIDI+voicegroup data at all; pull
   real, already-playable audio from the Essentials pack instead (§2.3),
   the same asset-sourcing move every other M36-S-adjacent asset decision in
   this project has already made once a "vendored, ready-to-use" option
   exists (Fonts, in `M26D1`; Databox/HUD art, in `M26B1`/`M26B2`).

---

## 1. Reference facts

### 1.1 The opcode(s) that trigger a sound in a move animation

Grepped `data/battle_anim_scripts.s` directly — did not assume the opcode
name in advance.

```
   3126  playsewithpan
    258  loopsewithpan
     95  waitplaysewithpan
     61  panse
      6  playse
```
(`grep -oE '\bplaysewithpan|loopsewithpan|waitplaysewithpan|panse|playse\b' data/battle_anim_scripts.s | sort | uniq -c`)

Five distinct move-animation sound opcodes, **~3,546 real call sites**
total. Representative lines (`data/battle_anim_scripts.s:24,41,59,60,71`):

```
	playsewithpan SE_M_SKETCH, SOUND_PAN_TARGET
	loopsewithpan SE_M_PSYBEAM, SOUND_PAN_TARGET, 20, 3
	playsewithpan SE_M_TELEPORT, SOUND_PAN_ATTACKER
	waitplaysewithpan SE_M_MINIMIZE, SOUND_PAN_ATTACKER, 48
	waitplaysewithpan SE_M_JUMP_KICK, SOUND_PAN_ATTACKER, 22
```

Distinct sound constants actually referenced from this corpus, counted
directly (`grep -oE 'SE_[A-Z0-9_]+' data/battle_anim_scripts.s | sort -u`):
**147 total** — **129** are move-specific `SE_M_*` constants, **18** are
shared/generic constants also used by menu/overworld/contest systems
(`SE_BALL_OPEN`, `SE_BALL_THROW`, `SE_BANG`, `SE_FALL`, `SE_SHINY`,
`SE_SUCCESS`, etc. — confirmed these are the *only* non-`SE_M_` hits, no
overworld-music or cry constant leaks into this corpus).

Cross-checked against `include/constants/songs.h`: **130** `SE_M_*`
constants are *defined* there (of 269 total `SE_*` defines in the whole
file) — 129 of the 130 are actually used somewhere in the battle-anim
corpus, meaning essentially the entire move-SFX namespace is exercised.
Sample definitions (`include/constants/songs.h:125-134,212`):

```c
#define SE_M_THUNDERBOLT            118 // SE_W085
#define SE_M_THUNDERBOLT2           119 // SE_W085B
#define SE_M_HARDEN                 120 // SE_W231
#define SE_M_NIGHTMARE              121 // SE_W171
...
#define SE_M_SKETCH                 205 // SE_W166
```

The `// SE_W###[B/C]` trailing comment on every one is itself a real,
load-bearing fact — see §1.2.

### 1.2 What format the underlying audio actually is — and the twist

**Every `SE_*` constant, move-SFX or otherwise, is a "song" in this
engine's own terms — literally the same asset type as background music.**
Confirmed directly in `sound/song_table.inc:1-33`:

```
	.equiv MUSIC_PLAYER_BGM,0
	.equiv MUSIC_PLAYER_SE1,1
	.equiv MUSIC_PLAYER_SE2,2
	.equiv MUSIC_PLAYER_SE3,3
	...
gSongTable::
	song mus_dummy, MUSIC_PLAYER_BGM, 0
	song se_use_item, MUSIC_PLAYER_SE1, 1
	song se_pc_login, MUSIC_PLAYER_SE1, 1
	...
```

There is no separate "sound effect" asset kind at the engine level — a
sound effect is just a very short song dispatched to one of three dedicated
SE playback channels instead of the BGM channel. `sound/song_table.inc` has
**610 total `song` entries**.

**The `SE_W###` naming convention in songs.h's own comments is the real
clue**: each move SFX resolves to a real `.mid` file, checked into
`sound/songs/midi/`. Confirmed directly:

```
$ ls sound/songs/midi | wc -l
531
$ ls sound/songs/midi | grep -c "^se_m"
132
```

A real one, `se_m_sketch.mid`, is a genuine, tiny, standard-format MIDI
file (159 bytes — `MThd` header confirmed via a raw hex dump). **This is
the part earlier M36 phases' own recon would have gotten wrong by
assumption**: the naive expectation for GBA-era assets (established by
every earlier phase — sprites are indexed PNGs, tilesets are raw tile
data) would be "there's a compiled binary blob and nothing human-readable."
For move SFX, that's false — there's a real, standard, directly-parseable
MIDI file for (almost) every one.

**But a MIDI file alone is not a playable sound.** MIDI encodes *notes and
timing*, not *timbre*. The real GBA instrument sound comes from a
completely separate layer: **voicegroups** (`sound/voice_groups.inc`, 195
`.include` lines pulling in per-song instrument-mapping tables), which map
each MIDI "program"/channel to either:

- a **direct sound sample** — a real, checked-in 8-bit PCM `.wav` file
  under `sound/direct_sound_samples/` (107 files: `sc88pro_*.wav`,
  `ethnic_flavours_*.wav`, `bicycle_bell.wav`, etc. — real Sound Canvas
  synth-instrument recordings, confirmed via `file`: `RIFF ... WAVE audio,
  Microsoft PCM, 8 bit, mono`), pitch-shifted per note by the playback
  engine, or
- a **programmable wave sample** — a raw 32-byte GB-style wavetable entry
  under `sound/programmable_wave_samples/` (25 `.pcm` files).

So rendering `se_m_sketch.mid` into real audio means: parse the MIDI note
events, look up which instrument that MIDI's own voicegroup declares, find
that instrument's real WAV/PCM sample, and resample/mix it at the right
pitch for the right duration — i.e., build a small real-time synthesizer
(a "mini Sappy player"), not run a file-format decoder. `mid2agb`
(`tools/mid2agb/`, real checked-in C++ source, confirmed buildable) exists
in this tree and does the *opposite* direction — MIDI → compiled GBA
tracker bytecode for the ROM build — it does not render audio either.

**A real emulator binary already sits in this reference tree**
(`reference/pokeemerald_expansion/tools/mgba/`, a real mGBA build used for
this project's own ROM regression tests) — meaning "build the full ROM and
capture real audio output from a running emulator" is a technically real
option available from this exact checkout, at the cost of standing up a
full GBA toolchain build and an audio-capture pass, a materially bigger
lift than anything else in this document.

**Verdict, stated plainly:** the source tree is *not* devoid of
human-readable audio data (some prior-phase pattern-matching might predict
"opaque binary blob, give up") — but it is also *not* a simple flat-copy
case (the same pattern-matching's other extreme). It's a genuine two-layer
compiled-instrument-music format requiring real synthesis work to become
listenable, distinct from every asset class M36's earlier phases pulled.

### 1.3 Cries — a real, separate, and genuinely simpler subsystem

Cries do **not** go through the song/`SE_*` system at all. Confirmed
directly, `src/sound.c:380-395` (`PlayCryInternal`):

```c
void PlayCryInternal(enum Species species, s8 pan, s8 volume, u8 priority, u8 mode)
{
    ...
    length = 210;
    ...
    pitch = 15360;
    ...
    switch (mode) {
    case CRY_MODE_NORMAL: break;
    case CRY_MODE_DOUBLES: length = 20; release = 225; break;
    case CRY_MODE_ENCOUNTER: release = 225; pitch = 15600; chorus = 20; volume = 90; break;
    ...
```

Cries are indexed by `enum Species` directly against `gCryTable`
(`sound/cry_tables.inc:1-10`, one `cry Cry_<Species>` entry per species,
gated by feature flags like `P_MODIFIED_MEGA_CRIES`), and each cry is a
**single real, standalone `.wav` sample** (`sound/direct_sound_samples/cries/`)
compressed via `wav2agb` at build time (`audio_rules.mk:22`:
`$(WAV2AGB) -b -c -l 1 --no-pad $< $@`) — **not** composed from a MIDI
file plus an instrument voicegroup. Playback applies a real-time
pitch/release/chorus envelope on TOP of that one sample (varying by mode —
double-battle cries are short and dry, encounter cries add chorus/pitch),
but there is exactly one playable asset per cry, not a note-sequence-plus-
timbre pair.

**Count**: `sound/direct_sound_samples/cries/` holds **1,161 real,
decodable WAV files** (`file`-confirmed: `RIFF ... WAVE audio, Microsoft
PCM, 8 bit, mono`, sample rates varying per species, e.g. Bulbasaur at
13,379 Hz, Abra at 10,512 Hz) — more than 386 because it includes Mega
Evolution/regional/other-form variants (`abomasnow_mega.wav`,
`absol_mega_z.wav`, etc.), gated in the actual game by the
`P_MODIFIED_MEGA_CRIES` config flag.

**This directly contradicts the intuitive framing that cries are the
"bigger, harder" problem because there are 386+ of them.** They are
individually the *easier* asset — a real WAV file per entry, same shape as
every sprite pull this project has already done successfully — whereas
move SFX (fewer files, ~130) are the *harder* one, because none of them is
directly playable without building real synthesis. Scale and difficulty
are not correlated the way the naive framing suggests.

### 1.4 The two vendored, non-reference asset packs

**`assets/Emerald UI Pack 1.2/`: zero audio, confirmed.** Full recursive
search for any audio extension (`wav`/`ogg`/`mp3`/`mid`/`flac`/`m4a`)
across the entire pack returned zero hits. It is a pure graphics reskin
pack (also confirmed no `Fonts/` directory in an earlier M26D1 recon) —
not relevant to M36-S at all.

**`assets/Essentials_v19.1/`: real, substantial, immediately-usable
audio.** `Audio/` has 4 real subdirectories — `SE/` (198 top-level files),
`SE/Anim/` (411 files), `SE/Cries/` (1,965 files), `BGM/` (73), `BGS/` (0),
`ME/` (66). Filtering out the harmless leftover Windows `:Zone.Identifier`
alternate-data-stream artifacts and `.import` sidecars (858 of each,
confirmed by count — these are leftovers from a browser download on
Windows/WSL, not real data; a future asset-pull script targeting this pack
should exclude `*:Zone.Identifier` explicitly) gives real counts:

| Subdirectory | Real files | Format |
|---|---|---|
| `Audio/SE/Anim/` | 137 | 146 `.ogg` + `.mp3` mixed |
| `Audio/SE/Cries/` | 655 | `.wav` |
| `Audio/SE/` (top-level, misc battle/menu SE) | 66 | `.ogg`/`.wav` |
| `Audio/BGM/` | 73 | (music, out of scope here) |
| `Audio/ME/` | 66 | (jingles, out of scope here) |

**Cries: legibly, directly name-mapped.** Every one of the 655 real files
is named as a literal ALL-CAPS species identifier — `BULBASAUR.wav`,
`CHARIZARD.wav` (confirmed via direct `file` check: real `RIFF ... WAVE
audio, Microsoft PCM, 8 bit, mono`). This maps almost for free onto this
project's own existing `data/species_name_to_id.json` bridge (built by
`scripts/gen_species_name_map.py`, from the M27K session) — a future pull
script would need only case-normalization, the same shape as every
existing `gen_*_sprites.py` name-resolution step.

**Move SFX: partially legible, mixed convention — same shape as the real
game's own "shared effect, reused across many moves" pattern.** Sampled
`Audio/SE/Anim/`'s real file list directly. A meaningful fraction are
literal move names: `Acupressure.mp3`, `Comet Punch.mp3`, `Defense
Curl.mp3`, `Dizzy Punch.mp3`, `Flail.mp3`, `Follow Me.mp3`, `Harden.mp3`,
`Lock On.mp3`, `Lovely Kiss.mp3`, `Lucky Chant.mp3`, `Mega Punch.mp3`,
`Metronome.mp3`, `Natural Gift.mp3`, `Present - Heal.mp3`, `Weatherball.mp3`,
`Wring Out.mp3`. The rest are **generic, type/action-themed effects reused
across many moves** — `Fire1.ogg`…`Fire6.ogg`, `Ice2/5/8.ogg`,
`Earth1/3/4/5.ogg`, `Explosion1-7.ogg`, `Blow1/3/4/5/6/7.ogg`,
`Paralyze1/3.ogg`, `Poison.ogg`, `Confuse.ogg`, `Damage1.ogg`,
`Collapse1.ogg` — mirroring exactly the real reference engine's own
`SE_M_TAKE_DOWN`-reused-five-times pattern found in §1.1. This means a
future pull script cannot do a pure 1:1 filename match the way cries can —
it would need a real per-move mapping decision (RPG Maker's own
"Animation" system assigns a generic SE to most moves and a bespoke one to
a handful), the same design shape as the M15-era `gen_moves.py`
name-resolution work, not a new kind of problem.

**No Ruby source exists in this pack to check the real intended mapping
against** — it ships as a compiled `Game.exe` + binary `.rxdata`
distribution, so any future per-move-to-SE-file mapping would need to be
inferred by ear/by convention rather than read out of a data file the way
`gen_trainer_data.py` reads `trainers.party` directly.

### 1.5 M36's own existing VM hooks — already correctly shaped to receive sound

Checked `scripts/battle/anim/anim_script_vm.gd` and
`scripts/battle/anim/anim_behaviors.gd` directly, per the task's own
suspicion that M36 might already be shaped for this. **It is, and more
thoroughly than expected.**

`anim_script_vm.gd`'s own class-doc comment (lines 25-32) states the
design intent directly:

```
# Deliberately NOT reproduced (each a no-op that records what it saw):
# ...
# - sound opcodes: M36-S. The SE id and pan are recorded per cue so the audio
#   pass is pure asset work.
```

The dispatcher (`_execute`, lines 403-412) records every sound opcode into
a `_sound_cues: Array[Dictionary]` accumulator rather than dropping it:

```gdscript
	"playse":
		_sound_cues.append({"se": int(cmd[1]), "pan": 0})
		_pc += 1
	"playsewithpan", "setpan", "waitplaysewithpan", "loopsewithpan", \
	"panse", "panse_adjustnone", "panse_adjustall":
		_sound_cues.append({"op": op, "args": cmd.slice(1)})
		_pc += 1
```

exposed publicly via `sound_cues() -> Array[Dictionary]` (line 302).

**Even more surprising: the `createsoundtask` dispatch already
distinguishes cry-family sound tasks by TIMING, not just recording them
uniformly.** `anim_behaviors.gd:625-634`:

```gdscript
	"SoundTask_PlaySE1WithPanning": _sound_immediate,
	"SoundTask_PlaySE2WithPanning": _sound_immediate,
	"SoundTask_PlayCryHighPitch": _sound_immediate,
	"SoundTask_PlayDoubleCry": _sound_cry_wait,
	"SoundTask_PlayNormalCry": _sound_cry_wait,
	"SoundTask_PlayCryWithEcho": _sound_cry_wait,
	"SoundTask_PlayDynamaxCry": _sound_cry_wait,
	"SoundTask_WaitForCry": _sound_cry_wait,
	"SoundTask_AdjustPanningVar": _sound_immediate,
```

with the class's own doc comment (lines 2585-2591) explaining why:

```
# ── Sound tasks: structured no-ops (audio is M36-S) ───────────────────────
#
# These still matter to TIMING even with no audio. Upstream most are
# single-frame, but the cry tasks block a script until the cry finishes --
# and with no cry playing, "finished" is immediate after their two warm-up
# frames. Reproducing that distinction keeps script pacing right rather than
# collapsing every sound cue to zero cost.
```

**Consequence for scope/cost**: the VM-level "where does a sound trigger
happen, and does the animation need to wait for it" plumbing is **already
built and already correct** — this genuinely shrinks M36-S's own remaining
work to real asset acquisition + a consumer that reads `sound_cues()` and
plays something, exactly as the class comment promises. No VM/opcode
changes are needed to add real audio.

### 1.6 What Godot itself offers (no new framework needed)

Godot 4 ships `AudioStreamPlayer` (non-positional) and `AudioStreamPlayer2D`
(positional, relevant for L/R pan — this project's SFX opcodes already
carry `SOUND_PAN_ATTACKER`/`SOUND_PAN_TARGET`/explicit-pan arguments, which
would map naturally onto `AudioStreamPlayer2D`'s panning), with native
`AudioStream` resource support for `.wav`, `.ogg`, and `.mp3` — covering
every format both vendored packs and any hand-converted reference audio
would need. No third-party audio plugin or custom playback engine is
required; the engine-side half of a future build is "instance a player
node per cue, feed it a `Resource`," nothing more exotic.

---

## 2. Real scale

- **147 distinct sound constants** used across move-animation scripts
  (129 move-specific, 18 shared/generic), **~3,546 real call sites** —
  a ~24× average reuse factor, i.e. the dominant pattern is "one
  effect asset reused across many moves," not "one bespoke sound per move."
  Confirmed examples of heavy reuse: `SE_M_TAKE_DOWN` (5 call sites in the
  scripts sampled alone), `SE_M_SWAGGER2` (3), `SE_M_DOUBLE_SLAP`/
  `SE_M_DOUBLE_TEAM` (2 each).
- **Move-SFX scope is orthogonal to M36's playability tracking.** Every
  sound opcode has been a zero-cost no-op since M36B; a move being
  "playable" in the 779/845 sense says nothing about whether real audio
  exists for it. There is no partial-progress figure to report here — this
  axis is at 0% regardless of M36's own visual-port percentage.
- **Cries: 1,161 real files in the reference tree, 655 in the Essentials
  pack** (a subset — Essentials ships base-form cries only, no Mega/regional
  variants) — both are directly decodable, name/species-keyed WAV.
- **Reasonable estimate, not exhaustively cross-referenced**: since sound
  opcodes never gate visual playability, essentially every one of the ~130
  `SE_M_*` effects belongs to a move whose animation *already plays
  visually* today (the 92.2%-playable figure is a near-ceiling on "how much
  of the SFX surface would have a home to attach to if built right now").
  A precise per-move cross-reference (which of the 129 `SE_M_*` constants
  map to which of the 717 already-`.tres`-implemented moves) was not run
  this session — it is straightforward (join on move name via the already-
  extracted `SE_M_*` list and `data/move_name_to_id.json`) but was judged
  unnecessary for a scoping-level estimate; flag it as the first concrete
  step of a future implementation session rather than treating this
  estimate as exact.

---

## 3. Cries: in scope for M36-S, or a separate milestone?

**Recommendation: separate milestone, or at minimum a clearly separated
sub-tier — not folded into M36-S's own scope.**

Reasoning:

- **Different asset shape.** Move SFX need real synthesis work (§1.2)
  or a pull from a differently-organized vendored pack (§1.4, requiring
  per-move mapping judgment). Cries need neither — they're a flat,
  name-keyed WAV pull, structurally identical to every sprite pull this
  project has already shipped successfully (`gen_pokemon_sprites.py`,
  `gen_trainer_portraits.py`).
- **Different consumer.** Move SFX plug into the M36 animation VM's
  already-built `sound_cues()` hook (§1.5) — a battle-animation-engine
  concern, matching M36-S's own name. Cries play on send-out/faint/
  overworld-encounter — a battle-*flow* and (eventually) overworld concern,
  with **no dependency on the M36 VM at all**. Building cries inside
  "M36-S" would put a non-M36 feature inside an M36 sub-tier for no
  structural reason.
- **Different real scale.** 386-1,161 files vs. ~130 distinct effects —
  bundling them risks the larger, cheaper item (cries) drowning out
  scoping attention for the smaller, harder item (move SFX), or vice versa.

If Rob prefers to ship cries first as a quick, low-risk, high-visible-payoff
win (real send-out cries in a battle would be a much bigger felt change than
silent SFX), that argues *for* doing cries as its own separate,
soonest-shippable item — not for folding it into M36-S.

---

## 4. Proposed phasing

| Phase | Scope | Est. relative cost |
|---|---|---|
| **S1 — Engine plumbing** | A generic `SfxPlayer` consumer reading `AnimScriptVM.sound_cues()`, mapping an `SE_*`-equivalent id (or, more practically, a move-name key) to a Godot `AudioStream` Resource and instancing an `AudioStreamPlayer2D` with the right pan. No real audio files yet — verify with 1-2 placeholder tones. | Low — the VM side is already built (§1.5); this is new Godot-side code only. |
| **S2 — Move-SFX asset pull, Essentials-sourced** | Pull `Essentials_v19.1/Audio/SE/Anim/` into the project (excluding `:Zone.Identifier`/`.import` cruft), build the real per-move name→file mapping (a hybrid of literal-name matches and a hand-curated generic-effect table, mirroring the reference engine's own reuse pattern), wire into S1's consumer. | Medium — asset pull is cheap; the mapping decision (which of ~130 generic move families gets which of the reused files) is real, judgment-driven work, not automation. |
| **S3 — Cries (separate item, not part of M36-S proper)** | Pull `Essentials_v19.1/Audio/SE/Cries/` (655 files, ALL-CAPS species names), resolve via `data/species_name_to_id.json`, wire into send-out/faint. | Low — pure flat pull + existing name-bridge reuse, same shape as every prior sprite pull. |
| **S4 (stretch, not recommended near-term)** | Reference-tree-sourced move SFX via a real MIDI+voicegroup mini-synth, for the effects Essentials doesn't cover well or for higher GBA-authenticity. | High — genuinely new synthesis-engine work, the only path in this document requiring novel DSP code. |

S1+S2+S3 together are the realistic near-term scope; S4 is flagged as a
possible future upgrade path, not a recommended starting point.

---

## 5. Open decisions for Rob

1. **Cries: fold into M36-S, or split into their own milestone (M36-S-cries
   / a new number)?** *Recommendation: split.* Different asset shape,
   different consumer, different real scale (§3) — bundling them risks
   scope confusion in both directions.
2. **Move-SFX source: Essentials pack pull (S2) vs. a from-scratch
   MIDI+voicegroup synth against the reference tree (S4)?**
   *Recommendation: Essentials pack (S2).* It's real, already-playable
   audio requiring only a name-mapping decision — the same kind of
   judgment call this project already makes routinely for asset pulls
   (e.g. Emerald UI Pack's border-variant key-color quirks in M26C6). A
   from-scratch synth is a materially larger, novel engineering
   undertaking with no precedent anywhere else in this project's asset
   pipeline.
3. **For moves where Essentials' own SE naming is ambiguous or has no
   clear generic-family match** (a real, expected case given RPG Maker's
   different move roster and animation-authoring conventions) — is a
   silent, no-audio fallback acceptable indefinitely, or should those
   specific moves be flagged for a future S4-style bespoke pull?
   *Recommendation: silent fallback is fine* — this project's own
   "graceful fallback" philosophy for M36's visual layer (a move with no
   ported behavior plays the generic hit effect rather than nothing) has
   an exact SFX analogue: a move with no confident SFX mapping plays no
   sound rather than a wrong one, revisited later if ever.
4. **Pan fidelity**: the reference engine's `SOUND_PAN_ATTACKER`/
   `SOUND_PAN_TARGET`/explicit-value pan arguments are real per-call-site
   data already captured by `sound_cues()`. Is faithfully reproducing
   attacker/target-side stereo panning worth the small extra
   `AudioStreamPlayer2D`-positioning work in S1, or is a flat, unpanned
   playback acceptable for a first cut? *Recommendation: build it now* —
   the data is already there for free, and it is cheap relative to
   everything else in this document.

---

## Sources cited directly this session

- `reference/pokeemerald_expansion/data/battle_anim_scripts.s` (opcode/constant grep)
- `reference/pokeemerald_expansion/include/constants/songs.h` (SE_M_*/SE_* enum, lines 125-134, 212)
- `reference/pokeemerald_expansion/sound/song_table.inc` (gSongTable, MUSIC_PLAYER_* channels)
- `reference/pokeemerald_expansion/sound/voice_groups.inc` (voicegroup includes)
- `reference/pokeemerald_expansion/sound/direct_sound_samples/` + `.../cries/` (real WAV file inspection via `file`)
- `reference/pokeemerald_expansion/sound/programmable_wave_samples/`
- `reference/pokeemerald_expansion/sound/cry_tables.inc` (gCryTable)
- `reference/pokeemerald_expansion/src/sound.c` (`PlayCryInternal`, lines 380-420ish)
- `reference/pokeemerald_expansion/audio_rules.mk` (wav2agb/mid2agb build rules)
- `reference/pokeemerald_expansion/tools/mid2agb/` (real checked-in C++ source, confirmed buildable, MIDI→GBA-bytecode direction only)
- `reference/pokeemerald_expansion/tools/mgba/` (real checked-in mGBA emulator binary, used for this project's own ROM tests)
- `as-imagined/assets/Emerald UI Pack 1.2/` (full recursive audio-extension search, zero hits)
- `as-imagined/assets/Essentials_v19.1/Audio/` (SE/Anim, SE/Cries, top-level SE, BGM, ME — direct file listing and `file`-format checks)
- `as-imagined/scripts/battle/anim/anim_script_vm.gd` (lines 25-32, 302-303, 403-412 — sound_cues())
- `as-imagined/scripts/battle/anim/anim_behaviors.gd` (lines 625-634, 2585-2601 — createsoundtask dispatch, _sound_cry_wait)
- `as-imagined/data/species_name_to_id.json`, `as-imagined/data/move_name_to_id.json` (existing name-resolution bridges, referenced not re-derived)
