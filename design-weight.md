# Weight & Carry Capacity -- Design (short)

Decided direction (2026-07-18): items have a per-unit weight; the player has a carry
capacity; carrying too much has a cost. Deferred behind the 15-slot / 255-stack / forage
work (now done). Small, data-driven, and it hangs off the SAME `add_item` / `collect`
chokepoints the pickup/forage/harvest already funnel through.

## Model
- **Per-unit weight** on `ItemData`: `@export var weight: float` -- the weight of ONE unit.
  A stack weighs `item.weight * count`. (Tools carry weight too.)
- **Carried weight** = the sum over ALL 15 inventory slots of `item.weight * count` -- hotbar
  AND background slots both count (weight is about what you HAUL, not what is equipped).
  Lives as `Inventory.total_weight()`.
- **Capacity** = a stat, `carry_capacity: float` (default ~50). Where it lives: on the
  Inventory (so it travels with the item model) or the player -- leaning Inventory, exposed
  via a player facade like `inventory`.

## Over-capacity behavior -- DECIDED: encumbrance / slow-down (2026-07-18, user)
You CAN always pick up -- nothing is ever blocked or stranded. Being OVER capacity slows you:
`max_speed` scales down as `carried` exceeds `capacity`. `add_item` is UNCHANGED (still only
returns slot/stack overflow, never a weight refusal). The speed scale:
- At or under capacity (`carried <= capacity`): full speed (factor 1.0).
- Over capacity: factor drops LINEARLY with the overage, clamped to a floor so you never fully
  stop -- e.g. `factor = clamp(1.0 - OVER_PENALTY * (carried/capacity - 1.0), FLOOR, 1.0)` with
  `FLOOR ~= 0.4` and `OVER_PENALTY` tuned so ~2x capacity hits the floor. Applied in `_simulate`
  (movement), reading `inventory.weight_ratio()`; knockback/lunge are NOT scaled (only walking).
(Rejected: hard block -- strands loot; hybrid -- more tuning than this game needs yet.)

## Default per-unit weights (tunable)
- Fiber 0.1, Stick 0.25, Wood 0.5, Stone 1.0 (stone is the heavy one).
- Sword 2.0, Axe 2.5, Pickaxe 3.0 (tools are heavy; you always carry them).
- Starting `carry_capacity` = **50** (DECIDED) -- ~50 stone / ~100 wood / ~200 stick before the
  cap bites, minus ~7.5 for the 3 starting tools. A tight-ish early game.

## HUD
- A weight readout -- "Wt 12.5 / 50" and/or a thin bar -- near the health/tool panel (top-left)
  or just above the hotbar. Shifts to a warning tint when over capacity (B) / full (A).

## Integration points (all EXISTING chokepoints -- minimal new surface)
- `Inventory`: add `total_weight()` + `carry_capacity` (+ a helper `weight_ratio()`).
- Encumbrance (decided): `add_item` unchanged; the player's movement (`_simulate`) reads an
  encumbrance factor from `inventory.weight_ratio()` and scales `max_speed` (floor ~0.4).
- No new entity types; pickup/forage/harvest already call `add_item` / `player.collect`.

## Phased build (after this design is approved)
1. `ItemData.weight` + set the 4 resource + 3 tool weights; `Inventory.total_weight()` +
   `carry_capacity` + `weight_ratio()`; player/inventory facade. Tests: the weight math.
2. Encumbrance: the `_simulate` movement hook scaling `max_speed` off `weight_ratio()`.
   Tests: at/under capacity = full speed; over = slower, clamped to the floor.
3. HUD weight readout. Tests: the readout reflects carried/capacity and the warning state.

## Notes / non-goals (for now)
- No volume/bulk separate from weight. No per-slot weight. No equip-vs-stored weight split
  (everything carried counts). No item-specific "too heavy to pick up a single unit" rule.

## REVISION 1 -- real-world units in GRAMS (2026-07-19, user; approved)
The abstract weights (fiber 0.1 ... stone 1.0) are replaced with researched real-world weights,
stored in GRAMS as the base unit so tiny items (fiber) and heavy ones (pickaxe) both read well.
- **Per-item weight (grams)** -- typical real figures, range midpoints (tunable):
  * Fiber 25 (handful of plant fiber) · Stick 50 (~35cm stick) · Stone 1000 (hand-sized cobble,
    density ~2.6) · Wood 1500 (split log / plank bundle).
  * Sword 1100 (1-hand arming sword 1.0-1.4kg) · Axe 1500 (1-2kg) · Pickaxe 2500 (2-3kg).
- **carry_capacity = 50000 g (50 kg)** -- starting tools 5100 g -> ratio ~0.1 (Normal). Real
  overload bites near 50 kg; a full 255-stack of stone (255 kg) is deep in Ultra.
- **Encumbrance is UNCHANGED** -- the tiers are ratios (carried_g / capacity_g), so the
  NORMAL/OVER/SUPER/ULTRA cutoffs (1x/2x/3x) and speeds (1.0/0.75/0.50/0.25) carry over verbatim;
  only the raw numbers become grams.
- **HUD display = auto g / kg (DECIDED)**: carried/capacity < 1000 g shows grams ("800 g"),
  >= 1000 g shows kilograms ("12.5 kg"); readout like "12.5 kg / 50 kg  Overencumbered".
  (Stored always in grams; a `_fmt_grams(g)` helper picks g vs kg. `carry_capacity` becomes 50000.)
- Build: retune the 7 `.tres` weight values to grams + set `carry_capacity = 50000`; add the
  g/kg formatter to the HUD readout; update the weight tests to the gram values. The pebble's
  yield is Stone, so it inherits Stone's 1000 g automatically.

*Verified against: Godot 4.7.1. Last updated: 2026-07-19*
