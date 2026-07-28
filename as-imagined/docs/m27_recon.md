# M27 — Full RPG rescope: high-level scoping

> ⚠️ **SUPERSEDED 2026-07-28 by `docs/overworld_scope.md` (rev 10).** This file
> is kept as history only — do not scope or implement from it. Two of its
> claims are confirmed wrong (§2's "the contents are Hoenn", §3's "map DATA is
> AUTHORED"); both are corrected inline below and resolved in the merged
> document.


**Status: HIGH-LEVEL ONLY, by request.** Blocks and dependencies, no sub-tiers.
Each block below needs its own scoping session before implementation; this
document exists to decide *sequence and boundaries* first. 2026-07-28.

---

## 0. Executive summary

- **M27 is the largest remaining milestone and had essentially no scoping.**
  Its roadmap row is ~3,700 characters, but almost all of that is three items
  that received deep Step 0 treatment as *side effects of other work*
  (transitions/Mugshot, per-ball particles, shiny). The actual headline — the
  whole overworld game loop — was **one sentence**.
- **There is an abandoned prior attempt in the tree** that nobody has
  referenced since: `scenes/maps/pallettown.tscn` (§2). It quietly implies a
  technical direction, and should be an explicit decision rather than an
  inherited default.
- **The single most scope-shaping fact: this project is Kanto with an original
  story, so map/NPC/encounter DATA is AUTHORED, not ported — while the
  SYSTEMS are ported.** That inverts the usual balance of this project's
  milestones and is what makes M27 sizeable but not 940-maps sizeable (§3).
- Proposed decomposition: **seven blocks, M27A–M27G** (§4), with a real
  dependency spine and two boundary questions for Rob (§5).

---

## 1. Why this needed scoping

Every comparably-sized milestone here (M19 moves, M24 trainers, M26 battle UI)
got a dedicated recon document before implementation. M27 had none, and its
one-line description covers what is realistically as much work as the battle
engine. The three well-researched items in its row are all *late-stage polish
within* the milestone, which makes the row read as better-scoped than it is.

---

## 2. Current state

**Code: none.** No overworld scene, controller, map loader, NPC system or
script engine exists. `main.tscn` boots straight to battle setup.

**One abandoned experiment**, dated **26 June** — before essentially all the
battle-UI work: `scenes/maps/pallettown.tscn`, a Godot-4 `TileMapLayer` with a
`TileSetAtlasSource` over a hand-pulled `New_General_PalletTown_Metatiles.png`.
It is:

- **hand-painted**, not generated from reference map data;
- **collision-free** — zero physics layers, terrain sets or custom data;
- **referenced by nothing** — no code or scene loads it.

It is a spike, not a foundation. It nonetheless represents a real implied
choice (native Godot tilemaps + hand-authored maps + third-party metatile art),
and M27A should confirm or reject that deliberately.

**Data already extracted:** `data/wild_encounters.json` — 388 encounter
entries across 3 groups. ⚠️ **CORRECTED 2026-07-28: this paragraph originally
said "from the Hoenn dataset … the contents are Hoenn and this project is
Kanto." That is wrong, and Kanto is in fact the MAJORITY.** Verified by joining
each entry's `map` constant against every `data/maps/*/map.json`'s own `region`
field: **264 of 388 entries are `REGION_KANTO`**, 124 are `REGION_HOENN` (124
unique Kanto maps vs 116 Hoenn). The original claim came from filtering on an
`_FRLG` map-name suffix, which only 4 entries carry — Kanto's real encounter
maps are named plainly (`MAP_VIRIDIAN_FOREST`, `MAP_MT_MOON_1F`,
`MAP_CERULEAN_CAVE_1F`, `MAP_ROCK_TUNNEL_1F`, `MAP_DIGLETTS_CAVE_B1F` …). The
file being unloaded by the data pipeline is still true; its *contents* being
Hoenn is not. Rob's own overworld-scope document had the correct figure
("264 of 388") before this document was written.

**Existing partial UI:** M25h-1.4/1.5 already built real full-screen Bag and
Party views for the battle context. Those are a genuine head start on M27F,
not a duplicate to be rebuilt.

---

## 3. Reference scale, and why it doesn't transfer directly

| Area | Reference scale |
|---|---|
| Maps | **940** |
| `event_object_movement.c` | **12,245 lines** — 2nd-largest file in the whole source tree |
| `overworld.c` | 4,077 lines |
| Field script engine | **393 macros / 237 script commands** |
| `field_player_avatar.c` + `field_control_avatar.c` | ~3,700 lines |
| `party_menu.c` / `item_menu.c` | 8,620 / 3,030 lines |

The field script engine is comparable in size to the battle script engine this
project already ported. `event_object_movement.c` being second only to
`battle_script_commands.c` is the clearest signal that NPC movement is a real
subsystem, not a detail of the player controller.

**But the 940 maps, the Hoenn encounter tables and the Hoenn NPC scripts are
NOT ported** — this project is Kanto with an original story, the same reasoning
already recorded for trainers (`[M26B3-1]`: "this project's RPG trainer roster
will be *authored*, not ported"). So M27 ports **systems** and authors
**content**. Two consequences worth stating early:

1. Content-authoring throughput matters as much as engine correctness. Whatever
   map/script format is chosen will be used by hand, repeatedly.
2. The reference stops being a spec to reproduce and becomes a *design
   reference* — which is a different relationship to source than every prior
   milestone in this project, and worth naming so Step 0 expectations adjust.

---

## 4. Proposed high-level blocks

Dependency spine: **A → B → C → D**, with **E** needing all four, **F** needing
D, and **G** small and early.

### M27A — Map foundation — **SCOPED 2026-07-28, `docs/m27a_recon.md`**

⚠️ **§3's assumption is WRONG, and Rob's own overworld-scope document already
said so before this one was written** (`overworldscopedetailed.md` rev 9 §0:
"converting reference maps is the primary content strategy, not
hand-authoring"). M27A re-derived the same conclusion independently rather than
consulting it. §3 concluded that map DATA would be *authored*, reasoning from
the trainers precedent. **That is wrong for maps**: the reference contains
**421 Kanto-region maps** — Pallet
Town, Oak's Lab, Viridian, Pewter, Cerulean, Celadon — with complete layouts,
blockdata, tilesets, palettes, warps and connections, plus **62 FRLG
tilesets**. Kanto geometry is **importable**. The distinction that survives is
narrower than §3 states: *geometry and art* are importable, while *content and
meaning* (which NPC says what, rosters, encounter tables, story triggers) are
still authored — so M27A is largely a conversion pipeline, while M27C/M27D
remain authoring work. §3 is left as written per this file's own convention of
not rewriting history; read it with this correction.
Tile/metatile rendering, the map file format, collision, map loading, and
connections/warps between maps. Everything else stands on this. Includes
confirming or rejecting the `pallettown.tscn` direction (§2), and the
authored-vs-imported question from §3.

### M27B — Player avatar and movement
Grid-based movement, facing, walk/run animation, collision response, ledges,
and the surf/bike state machine. Source: `field_player_avatar.c` /
`field_control_avatar.c`.

### M27C — Map objects and NPCs
Object events, movement types and patterns, interaction ranges, and overworld
sprites. The largest single system by reference line count.

### M27D — Field script engine
The interpreter that makes objects *do* things: dialogue, flags and variables,
branching, giving items, starting battles. Needs its own architecture decision
up front — port a command interpreter, or express scripts natively in GDScript?
**Note the standing constraint**: the `dialogue_manager` addon was approved for
conversation/text presentation *only* and explicitly must not become the field
script engine.

### M27E — Encounters, battle handoff and return
Encounter triggering, trainer sightlines, the overworld→battle transition
(including the already-researched Mugshot effect), and — importantly — the
**battle→overworld return path**. That return is what finally unblocks
**M26D3-8** and retires this project's invented Win/Lose screen. See §5 for the
M29 boundary.

### M27F — Field UI and inventory
Shops, a real bag/inventory system (as opposed to the battle-only
`ItemManager`), out-of-battle item use, and the start menu. M25h-1.4/1.5's Bag
and Party screens are the starting point, not a rebuild.

### M27G — Player identity
Trainer name, gender and ID — none of which exist in any form today. Small, but
it **unblocks a placeholder already sitting in shipped code**: `[M26B3-3]`
hardcodes `_PLAYER_BACK_PIC = Leaf` explicitly awaiting "a future M27
player-character system". Cheap and early.

---

## 5. Boundary questions for Rob

**(1) M27E versus M29.** M29 ("Encounters & catching") already exists as its own
milestone covering catch-rate maths, Repel and roaming/static encounters. M27's
own row claims "encounter-triggering infra". The workable split is **M27 owns
the TRIGGER** (stepping into grass starts a battle; the transition; the return)
and **M29 owns the CONTENT and MECHANICS** (tables, rates, methods, catch
maths) — but that boundary is currently implied rather than stated, and the two
rows overlap as written.

**(2) What M27 explicitly does NOT include.** Neighbouring milestones already
claim: **M28** evolution, **M29** encounters/catching, **M30** move relearning,
**M31** breeding, **M32** HM field effects, **M33** PC storage and Pokédex,
**M34** save/load. Several are hard to build *without* touching M27 systems —
HM field effects (M32) in particular are field mechanics sitting outside this
milestone. Worth confirming those boundaries hold, or deliberately pulling some
in.

**(3) Save interaction.** M34 owns save/load, but the overworld is the first
system with persistent state that genuinely needs it (position, flags,
variables, inventory). M27D's flags/variables in particular have nowhere to
live. Either M27 defines the state shape and M34 serialises it, or some of M34
moves earlier.

---

## 6. Already-researched items that live inside M27

Recorded so a future session doesn't re-derive them:

- **Battle transitions / Mugshot** (→ M27E). Fully traced in CLAUDE.md's own
  M27 row: `DoesTrainerHaveMugshot` selection, the HBlank scanline effect, five
  palette variants, and the finding that it reuses the same 64×64 front pic —
  **no "portrait" asset concept exists anywhere in the reference**.
- **Per-ball send-out particles** (→ end of M27). Nine `particleAnimationFunc`s
  fully tabulated in `[M26B3-6a]`; unreachable until ball variety exists.
- **Shiny Pokémon** (→ M27, encounter-generation side). `TrainerPartyMon.is_shiny`
  is already parsed from real trainer data, but `BattlePokemon` has no field, no
  sprite variant loads, and `TryShinyAnimation` has no equivalent.
- **86 unpulled Kanto/FRLG trainer sprites** (`[M26B3-1]`) — a trivial flat copy,
  deliberately deferred until the Kanto roster is actually authored.

---

## 7. Recommended next step

Scope **M27A** on its own first. It carries the decision every other block
inherits — map format, tile rendering, collision, and authored-vs-imported —
and it is the one place where getting it wrong is expensive to undo. The
`pallettown.tscn` spike should be either adopted deliberately or retired
explicitly as part of that session.
