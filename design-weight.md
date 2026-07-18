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

*Verified against: Godot 4.7.1. Last updated: 2026-07-18*
