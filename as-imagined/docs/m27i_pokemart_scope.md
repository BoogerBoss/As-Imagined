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
`shop.c:168`): **Buy / Sell / Quit** — and that is what this project ships, per
§5 decision 2 as revised 2026-08-09. `sShopMenuActions_BuyQuit` (`shop.c:175`)
is a real second shape for shops that do not buy back, and is no longer needed
here.

Leaving either screen returns to the clerk rather than closing the shop —
`Task_GoToBuyOrSellMenu` ends on `gText_CanIHelpWithAnythingElse` /
`gText_AnythingElseICanHelp` (`shop.c:485-487`) and re-shows the menu.

### ⚠️ Sell does NOT use the mart's own list — it opens the BAG

This is the finding that decides what Sell costs, and it cuts the estimate
rather than raising it. `Task_HandleShopMenuSell` hands off to
`CB2_GoToSellMenu`, which is one line: `GoToBagMenu(ITEMMENULOCATION_SHOP,
POCKETS_COUNT, CB2_ExitSellMenu)` (`item_menu.c:622-624`). So selling is the
ordinary bag screen opened in a shop CONTEXT, across all pockets — there is no
second list widget to build. `FieldBagScreen` (`[M27I I4]`) is already that
screen, and `[M27I I5-3]`'s item-use flow already established the pattern of a
bag context that reports a chosen item back to a caller.

**Sell rules, from `Task_ItemContext_Sell` (`item_menu.c:2179`):**

⚠️ **The refusal tests TWO things, and price is one of them:**
`GetItemPrice(item) == 0 || GetItemImportance(item)` refuses with
`gText_CantBuyKeyItem`. Note the upstream name says *CantBuy* and it is the
SELL refusal — do not go looking for a separate string. **A price of 0 is
therefore unsellable by construction**, which matters directly for the Escape
Rope question still open below.

- **A stack of 1 skips the quantity picker** entirely and goes straight to
  confirm (`tQuantity == 1`).
- **The sell quantity cap is `MAX_MONEY / sell_price`** — 999999
  (`include/money.h:4`), which this project's `Wallet.MAX_MONEY` already
  matches — clamped against the stack the player actually holds. It is NOT a
  bag-space cap; that is the BUY side.
- `SellItem` (`item_menu.c`) is `PlaySE(SE_SHOP)` → `RemoveBagItem` →
  `AddMoney`, in that order. `SE_SHOP` is shared with buying, so `[M27R 7a-1]`
  already covers it, and `Bag.remove` (all-or-nothing) and `Wallet.earn`
  (clamps at `MAX_MONEY`) are both already the right shapes.

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
- **I6c — the screen, Buy half.** The clerk menu (**Buy / Sell / Quit**, with
  Sell inert until I6d), the mart list, the quantity picker capped by money AND
  bag space, sold-out key items, and the **Premier Ball bonus** folded in
  rather than split out. `WAIT_NATIVE`, no new pause kind.
- **I6d — Sell.** Kept separate not because it is large but because it is a
  DIFFERENT SCREEN: it opens `FieldBagScreen` in a shop context rather than the
  mart list, so it shares almost nothing with I6c except the wallet. Sequencing
  it second means I6c can ship a working shop without waiting on a bag-context
  mode.

(The Premier Ball bonus is deliberately NOT its own tier — it is a branch on
the purchase I6c already makes, and splitting it would mean touching one
function twice.)

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

**2. Sell is IN — Rob, 2026-08-09. This REVERSES the earlier "out of scope for
now" call, and the earlier text is replaced rather than annotated, because a
struck-through decision beside a live one is exactly what gets misread later.**

The menu is source's own default **Buy / Sell / Quit**
(`sShopMenuActions_BuySellQuit`, `shop.c:168`); `sShopMenuActions_BuyQuit` is no
longer needed and its note is retired.

⚠️ **A Step 0 pass done when this was reversed found selling to be CHEAPER than
the deferral assumed, and for a reason that was never checked at the time: it
does not build a list at all.** `CB2_GoToSellMenu` opens the ordinary bag
across all pockets (`item_menu.c:622-624`), so Sell is a context on
`FieldBagScreen` — which exists — plus a confirm, a quantity picker and two
refusal cases. See §3 for the rules, all now sourced rather than deferred: the
**/4** factor, the **price-0-or-importance** refusal (whose upstream string is
confusingly named `gText_CantBuyKeyItem`), the stack-of-1 shortcut, and the
`MAX_MONEY / sell_price` cap.

**3. Premier Ball bonus is IN.** Fold into I6c rather than keeping I6d as a
separate tier — it is a branch on the purchase that just landed, and splitting
it would mean touching the same function twice.

### Still open

**Escape Rope's price of 0 and `key_items` pocket.** Not answered, and it
matters more now that it is deliberately stocked: as the data stands it is a
free item on ten shelves. Worth one check against source's own item table
before I6b, since it is a data correction rather than a design call.

⚠️ **RESOLVED 2026-08-09 — see §8.3: the price and pocket are CORRECT for this
project's `GEN_LATEST` config and must not be changed. What follows was written
before that was checked, and its conclusion is retracted.**

⚠️ **Sell being back in scope gives that price a SECOND consequence, and the
two point opposite ways.** `Task_ItemContext_Sell` refuses any item whose price
is 0, so as the data stands Escape Rope is free to buy and impossible to sell —
the sell side is accidentally correct while the buy side is broken. Fixing the
price fixes both; leaving it "for now" leaves an exploit on the buy side only.
Check the price before I6b, not before I6d.

---

## 6. What this does NOT cover

`pokemartdecoration` (Secret Base decorations — no such system, and Secret Bases
are a standing exclusion), the Battle Frontier BP shops (M35), and the
`ViridianCity_Mart` tutorial clerk, which has its own `OnLoad`/`OnFrame` map
scripts and is a scripted sequence rather than a shop question.

---

## 8. Build plan — re-measured 2026-08-09, and three corrections

Everything below was measured against the tree today. **Three figures in the
sections above are wrong or stale and are corrected here rather than edited in
place**, because the reasoning that produced them is still worth reading.

### 8.1 ⚠️ The pipeline gap is NOT "the label is missing"

`pokemart ViridianCity_Mart_Items` names a label, and that label **is emitted**
— carrying `[release, end]` and nothing else. The `.2byte ITEM_*` lines are
dropped silently by `gen_map_scripts.py`, which only understands opcodes.

That is worse than an absent label, and it changes I6a's acceptance test: a
handler asking for the stock would get an **empty list**, not an error. A shop
with nothing in it looks like a design decision. **I6a must fail closed** —
`pokemart` with an empty or unresolvable list must refuse and say so, never
open an empty shop.

⚠️ **The label is data AND code**, which is the shape to emit for:

```
ViridianCity_Mart_Items::
    .2byte ITEM_POKE_BALL      <- stock, ITEM_NONE-terminated
    ...
    .2byte ITEM_NONE
    release                    <- the clerk's own continuation
    end
```

So the emitter must keep both halves: the item list AND the trailing ops the
script resumes into. Dropping the ops would strand every clerk in the region.

**The rest of the clerk compiles correctly today** — `lock`, `faceplayer`, the
`goto_if_eq`, `message`, then `pokemart`, then `message gText_PleaseComeAgain`
/ `waitmessage` / `waitbuttonpress` / `release` / `end`. `pokemart` is the only
halt, so the flow works the moment it is implemented.

### 8.2 ⚠️ The corridor needs SIX new items, not seventeen

Measured across the corridor's only two marts:

| mart | stock |
|---|---|
| **Viridian** | Poké Ball · Potion · Antidote · Paralyze Heal |
| **Pewter** | those four, plus Awakening · Burn Heal · Escape Rope · Repel |

**8 distinct items, of which 2 already have a `.tres`** (Poké Ball, Potion).
The six missing are **Antidote, Awakening, Burn Heal, Paralyze Heal, Escape
Rope, Repel** — all present in `items.json` with real prices, so I6b is six
`gen_items.py` rows, not a roster project. §2's "17 of 20" is a different,
wider measurement and does not describe the corridor.

⚠️ **Four of those six become field-usable for free, and one is a trap.**
`[M27I I5-3]` derives field usability from `battle_usage`, so Antidote /
Awakening / Burn Heal / Paralyze Heal need a real `CURE_STATUS` usage or they
will be sold and then refuse to work. Repel and Escape Rope stay **inert by
decision** (§5) and correctly offer no USE action at all.

### 8.3 ⚠️ RETRACTED — Escape Rope is CORRECT, and "fixing" it would have broken it

**This section previously claimed `price = 0` and `pocket = key_items` were two
data gaps to correct in I6b. Both claims are wrong.** Rob flagged it before any
change was made — *"I think the change might be on purpose"* — and source
settles it (`src/data/items.h`, `[ITEM_ESCAPE_ROPE]`):

```c
#if I_KEY_ESCAPE_ROPE >= GEN_8
    .price = 0,
    .importance = 1,
    .pocket = POCKET_KEY_ITEMS,
#else
    .price = (I_PRICE >= GEN_7) ? 1000 : 550,
    .pocket = POCKET_ITEMS,
#endif
```

`I_KEY_ESCAPE_ROPE` is `GEN_LATEST`, and `GEN_LATEST` is `GEN_9`
(`include/config/general.h:73`). So the importer took the `>= GEN_8` branch and
this project's data is **exactly what its configured generation specifies**.

⚠️ **THE REFERENCE'S OWN CONFIG COMMENT PREDICTS THE CONSEQUENCE THAT LOOKED
LIKE A BUG**: *"In Gen8, Escape Rope became a Key Item. Keep in mind, this will
make it free to buy in marts."* Free-in-marts is a documented upstream
consequence of the chosen generation, not a data gap.

**Nothing to change in I6b.** What it does change is I6c: Escape Rope carries
`importance`, so the shop must handle it the way source already does — a key
item the player already holds prints **SOLD OUT** rather than being hidden
(`shop.c:660, 1024`), and `importance` is one of the two conditions that refuse
a SELL (§3). Both rules were already scoped; this is simply the corridor's own
worked example of them, which is useful rather than inconvenient.

**The lesson, recorded because it nearly cost real data:** a value that looks
wrong in a project tracking `GEN_LATEST` is a config branch until proven
otherwise. Read the `#if` before calling it a gap.

---

## 9. Chrome: generic Godot UI — Rob's call, 2026-08-09

**The screen is built from plain Godot controls. No reference art is pulled.**

⚠️ **THIS OVERRIDES A STANDING RULE, AND SAYING SO IS THE POINT.** CLAUDE.md's
"pull real reference-game assets/structure first" exists specifically to forbid
building a generic version and retrofitting authenticity later, and it cites
the cost that produced it: M25h took **three sessions** to reach one authentic
element that way. Rob has accepted that trade here. It is a decision, not an
oversight, and a later session finding a plain `Panel` shop must not treat it
as an unfinished job to "fix" without asking.

**Two things genuinely lower the usual cost of this trade, and they are why the
call is defensible rather than merely allowed:**

1. **The upgrade target already exists.** Source's own sell path *is* the bag
   (`GoToBagMenu(ITEMMENULOCATION_SHOP, ...)`), and `FieldBagScreen` already
   carries real Emerald UI Pack art (`bg_m.png`, from `[M26E1]`). So the
   eventual chrome pass is "adopt the sibling's conventions", not a fresh art
   hunt — which is exactly the retrofit the standing rule warns is expensive,
   made cheap by a sibling having already paid for it.
2. **`FieldBagScreen` itself shipped this way** — a plain `Panel` at `[M27I
   I4]`, real art later at `[M26E1]`. The sequence is established for this
   family of screens even though the rule prefers otherwise.

**The chrome pass is NOT scoped here** and belongs with M26E's own screen work.

---

## 10. Tiers, with the corrected sizes

- **I6a — the pipeline.** Emit `.2byte` stock lists alongside the trailing
  opcodes; regenerate the corpus; a guard that every `pokemart` argument
  resolves to a NON-EMPTY list. ⚠️ Fail closed on an empty one (§8.1).
  Independently testable with no UI at all.
- **I6b — the item roster.** Six `gen_items.py` rows, four of them needing a
  real `CURE_STATUS` usage. ⚠️ **No Escape Rope data fix — §8.3 retracts it.**
  Ends with every corridor mart's stock loadable.
- **I6c — the screen, Buy half.** Generic Godot controls. Clerk menu
  (Buy/Sell/Quit), the stock list, quantity capped by money AND bag space,
  sold-out key items, and the Premier Ball bonus. `WAIT_NATIVE`, no new pause
  kind — the same seam `multichoicegrid` and `fadescreen` already use.
- **I6d — Sell.** `FieldBagScreen` in a shop context; the /4 price, the
  price-0-or-importance refusal, the stack-of-1 shortcut, the
  `MAX_MONEY / sell_price` cap.

**Nothing is open.** The `authored_encounters`-style questions were settled in
§5, the chrome is settled in §9, and the sizes are measured in §8.
