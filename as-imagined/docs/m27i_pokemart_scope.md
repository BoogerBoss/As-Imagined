# M27I — `pokemart` scope

**Recon only, 2026-08-09. Nothing built. Scope of record for whenever this is
picked up.**

`pokemart` is the last unimplemented opcode the 32-map corridor reaches. Two
uses — Viridian Mart and Pewter Mart — and both currently halt the clerk's
script mid-conversation.

---

## 0. The headline: it is three problems, not one

Every prior sizing of this item, including my own in the M27R plan, has read it
as "needs a shop UI". Measured, the UI is the **third** of three blockers and
not obviously the largest:

| | blocker | why it is invisible until you look |
|---|---|---|
| **1** | **The stock lists are not in the compiled corpus** | `PewterCity_Mart_Items` compiles to `[release, end]`. A shop UI built today would open onto an empty shelf. |
| **2** | **17 of the 20 stock items have no `.tres`** | Per this project's own two-layer rule, the file's absence *is* "we do not implement this". Only Potion, Poké Ball and Full Heal exist. |
| **3** | The buy/sell screen | Real work, but the wallet and bag it needs already exist. |

Do them in that order. Building the UI first means demoing it against an empty
shelf and then against items that cannot be used.

---

## 1. Blocker 1 — the stock lists are dropped by the compiler

A mart list is **data, not code**. Source:

```
	pokemart PewterCity_Mart_Items
	msgbox gText_PleaseComeAgain
	release
	end

	.align 2
PewterCity_Mart_Items::
	.2byte ITEM_POKE_BALL
	.2byte ITEM_POTION
	...
	.2byte ITEM_NONE
```

`gen_map_scripts.py` indexes `PewterCity_Mart_Items::` as an ordinary label and
then finds no opcodes in it, so the compiled entry is whatever executable lines
happen to follow — literally `[{"op":"release"},{"op":"end"}]`. The eight items
are gone, silently.

⚠️ **The label still RESOLVES, which is what makes this dangerous.** A consumer
asking "does `PewterCity_Mart_Items` exist?" gets yes. Only asking "what is in
it?" reveals the loss.

**What is needed:** teach the generator to recognise a `.2byte` data block and
emit it as a list rather than as a (broken) script. Shape suggestion — keep it
out of `ops_by_label`, since it is not a script and a future `goto` into it
should stay a bug:

```jsonc
"data_lists": { "PewterCity_Mart_Items": ["ITEM_POKE_BALL", "ITEM_POTION", ...] }
```

**Terminator:** `ITEM_NONE`, and it is real — `SetShopItemsForSale`
(`shop.c:384`) counts `while (itemList[i])`, i.e. reads until a zero. Emitting
the trailing `ITEM_NONE` into the list would put a phantom row on every shelf.

**Scale:** 13 mart lists region-wide, 20 distinct stock items. Both corridor
marts are among the 13. Regenerating `data/map_scripts.json` lands on that
file's already-open 8.6 MB tracked-size question.

### The 13 lists

| list | map | items |
|---|---|---|
| `ViridianCity_Mart_Items` | ViridianCity_Mart_Frlg | 4 |
| `PewterCity_Mart_Items` | PewterCity_Mart_Frlg | 8 |
| CeruleanCity / LavenderTown / SevenIsland / TrainerTower_Lobby | — | 9 each |
| FourIsland / SixIsland | — | 8 each |
| CinnabarIsland / VermilionCity | — | 7 each |
| FuchsiaCity / SaffronCity / ThreeIsland | — | 6 each |

Only the first two are in the corridor; the rest fall out for free once their
maps are baked, since the specials and the screen are generic.

---

## 2. Blocker 2 — the item roster

**17 of the 20 distinct stock items have no `.tres`.** `items.json` carries a
price and a pocket for every one, but **no `battle_usage` for any of them**, so
even the JSON layer does not say what they do.

| item | id | price | `.tres` | in N marts |
|---|---|---|---|---|
| Escape Rope | 120 | **0** | no | 10 |
| Revive | 33 | 2000 | no | 9 |
| Full Heal | 48 | 400 | **yes** | 8 |
| Max Repel | 116 | 900 | no | 8 |
| Ultra Ball | 3 | 800 | no | 7 |
| Great Ball | 2 | 600 | no | 6 |
| Antidote / Paralyze Heal | 43 / 44 | 200 | no | 5 each |
| Hyper Potion | 30 | 1500 | no | 5 |
| Poké Ball | 1 | 200 | **yes** | 4 |
| Super Potion | 29 | 700 | no | 4 |
| Full Restore | 32 | 3000 | no | 4 |
| Max Potion | 31 | 2500 | no | 4 |
| Potion | 28 | 200 | **yes** | 3 |
| Awakening / Burn Heal / Ice Heal | 47 / 45 / 46 | 200 | no | 3 each |
| Repel | 114 | 400 | no | 3 |
| Super Repel | 115 | 700 | no | 1 |
| Dream Mail | 208 | 50 | no | 1 |

They split into four groups by how much work each is:

- **Status heals** (Antidote, Paralyze Heal, Burn Heal, Ice Heal, Awakening) —
  data only. `ItemManager.BATTLE_USE_CURE_STATUS` already exists and Full Heal
  already uses it; these are narrower versions of the same effect.
- **HP heals** (Super/Hyper/Max Potion, Full Restore) — data only.
  `BATTLE_USE_RESTORE_HP` exists and Potion uses it.
- **Balls** (Great, Ultra) — `BATTLE_USE_THROW_BALL` exists and `[M27H H4]`'s
  capture formula already takes a ball multiplier, so this is a data row plus
  confirming the multiplier is read per ball rather than hardcoded to 1.
- **Genuinely absent mechanics** — **Revive** (no revive path anywhere; the
  party screen refuses a fainted target by design), **Repel/Super/Max Repel**
  (declined by Rob at M27H, so inert by decision), **Escape Rope** (no field
  mechanic), **Dream Mail** (no mail system).

⚠️ **Rob's decision, 2026-08-09: Repel (all three), Escape Rope and REVIVE are
stocked as INERT** — real price, real purchase, no effect. Five items. That
needs no new mechanics, but it does need the shop to not care whether an item
does anything. See §5 decision 1 for why inert Revive is safer than it sounds.

⚠️ **Escape Rope's price in `items.json` is 0 and its pocket is `key_items`.**
Both look like data gaps rather than intent — a free item on ten shelves, in a
pocket source does not use for it. Worth checking against source's own item
table before stocking it, or it is free.

---

## 3. Blocker 3 — the screen

### The flow, from source

`ScrCmd_pokemart` (`scrcmd.c:2553`) is three lines: `CreatePokemartMenu(ptr)`,
then **`ScriptContext_Stop()`**. The shop's own callback is
`ScriptContext_Enable` (`shop.c:1319`) — so the script **pauses for the whole
shop and resumes when it closes**.

⚠️ **That maps exactly onto `WAIT_NATIVE`** and needs no new pause kind — the
same call `multichoicegrid` and `fadescreen` already made. A handler opens the
shop, awaits its close, and returns; `ScriptDriver` resumes. Nothing to invent.

### Menu shape

`MART_TYPE_NORMAL` gets three actions (`sShopMenuActions_BuySellQuit`,
`shop.c:168`): **Buy / Sell / Quit**.

⚠️ **This project ships Buy / Quit instead — §5 decision 2 — and that is a real
source shape, not a trimmed one.** `sShopMenuActions_BuyQuit` (`shop.c:175`)
exists precisely for shops that do not buy back. The divergence is only in
WHICH shops use it, so nothing about the menu is invented.

### Rules worth porting exactly

⚠️ **SELL PRICE IS A QUARTER, NOT A HALF.** `GetItemSellPrice` is
`GetItemPrice(itemId) / ITEM_SELL_FACTOR` (`item.c:965`), and
`ITEM_SELL_FACTOR` is `(I_SELL_VALUE_FRACTION >= GEN_9) ? 4 : 2`
(`constants/item.h:21`). This project's reference config is **`GEN_LATEST`**, so
the factor is **4**. "Half price" is the thing everyone knows and it is wrong
here; getting it wrong doubles every sale.

**Buy quantity is capped by money AND by bag space** (`shop.c:1089-1094`):
`maxQuantity = money / unitCost`, then clamped to `MAX_BAG_ITEM_CAPACITY`. So
the quantity picker cannot offer more than the player can pay for — the
"you don't have enough money" path (`gText_YouDontHaveMoney`, `:1028`) only
guards the edge.

**Key items are shown as SOLD OUT, not hidden** (`shop.c:660, 1024`): if
`GetItemImportance(itemId)` and the player already has one, the price column
prints "SOLD OUT" and buying is refused. Same discipline as the party screen's
own "show it and say why" rule from `[M27I I5-2]`.

**Premier Ball bonus** (`shop.c:1198`): buying 10+ of a Poké Ball pocket item
throws in a free Premier Ball, gated on bag space. At `I_PREMIER_BALL_BONUS >=
GEN_8` the trigger is the whole `POCKET_POKE_BALLS`, not just Poké Balls.
Optional, but it is cheap and it is the kind of detail whose absence is noticed.

### What already exists and should be reused

- **`Wallet`** (`[M27I I3b]`) — `spend` clamps to zero and never fails, which is
  correct for the whiteout payout and **wrong for a purchase**: a shop must
  refuse rather than clamp. Check the affordability first, exactly as source
  does; do not "fix" `spend`.
- **`Bag`** (`[M27I I3]`) — slot model with real capacities, and `add` is
  all-or-nothing, which is what a purchase wants.
- **`FieldBagScreen`** (`[M27I I4]`) — the closest existing screen, and the
  natural model for list + description + pocket handling.
- **`SE_SHOP`** — already mapped to `Mart buy item.ogg` by `[M27R 7a-1]`,
  waiting for a purchase to fire it.

---

## 4. Proposed split

- **I6a — the pipeline.** `.2byte` data-list extraction, corpus regeneration,
  and a guard that every `pokemart` argument resolves to a non-empty list.
  Independently testable with no UI at all.
- **I6b — the item roster.** The 15 heals/balls as data rows, plus Repel and
  Escape Rope as inert stock. Ends with every mart's stock loadable.
- **I6c — the screen.** **Buy / Quit** (source's own `sShopMenuActions_BuyQuit`
  — Sell deferred, decision 2 below), the quantity picker capped by money AND
  bag space, sold-out key items, and the **Premier Ball bonus** folded in
  rather than split out. `WAIT_NATIVE`, no new pause kind.

(The former I6d is gone — the Premier Ball bonus is a branch on the purchase
I6c already makes, and splitting it would mean touching one function twice.)

**a and b are independently valuable** — a closes a silent data loss that
affects 13 lists, and b makes 17 items real for the bag and party screens that
already exist, whether or not a shop is ever built.

---

## 5. Decisions — resolved by Rob, 2026-08-09

**1. Revive is stocked INERT**, joining Repel/Super Repel/Max Repel and Escape
Rope. So the inert set is **five items**, and they divide into two kinds that
should not be conflated later:

- *Designed out* — Repel and its family, declined at `[M27H]` against that
  session's own recommendation. These are inert permanently unless that call is
  revisited.
- *Not yet built* — **Revive**, and Escape Rope's field effect. Real mechanics
  this project will plausibly want; inert is a waypoint, not a verdict.

⚠️ **A player CAN buy a 2000-money Revive that does nothing, and that is worth
knowing rather than discovering.** The exposure is smaller than it first looks,
though, and for a reason already built: `[M27I I5-3]` derives field usability
from `battle_usage`, so an item with none is **not offered a USE action at
all** — the party screen shows only CANCEL. So the player keeps the item rather
than spending it on nothing, and it starts working the day Revive is built.
The cost is money spent on a held item, not a consumable burned for no effect.

**2. Sell is OUT of scope for now.** Buy only.

⚠️ **This costs no invented UI, which is the useful part.** Source already ships
a two-action menu — `sShopMenuActions_BuyQuit` (`shop.c:175`) — so
**Buy / Quit** is a real shape from the reference rather than a trimmed-down
one. The divergence is only in WHICH shops use it (source reserves it for
Battle-Frontier-style shops), not in the menu existing. Record that at the site.

It also removes the /4 sell rule and the key-item sell refusal from I6c
entirely — both stay documented in §3 for whoever adds Sell later, and the /4
figure in particular should not be re-derived from memory.

**3. Premier Ball bonus is IN.** Fold into I6c rather than keeping I6d as a
separate tier — it is a branch on the purchase that just landed, and splitting
it would mean touching the same function twice.

### Still open

**Escape Rope's price of 0 and `key_items` pocket.** Not answered, and it
matters more now that it is deliberately stocked: as the data stands it is a
free item on ten shelves. Worth one check against source's own item table
before I6b, since it is a data correction rather than a design call.

---

## 6. What this does NOT cover

`pokemartdecoration` (Secret Base decorations — no such system, and Secret Bases
are a standing exclusion), the Battle Frontier BP shops (M35), and the
`ViridianCity_Mart` tutorial clerk, which has its own `OnLoad`/`OnFrame` map
scripts and is a scripted sequence rather than a shop question.
