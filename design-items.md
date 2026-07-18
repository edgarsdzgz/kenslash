# Milestone E -- Items, Harvesting & Pickup

Decided 2026-07-18. Harvest by ATTACKING with the right tool (existing); MAGNETIC-PULL
auto-pickup for ground drops (Stardew-style); drops PERSIST as chunk data (age only
while their chunk is loaded, despawn at a 5-real-minute lifetime). Reference points:
Valheim (tree must fall to yield; ore drops per hit; E to interact), Minecraft (auto-
pickup, 5-min item despawn, items saved with chunks), Stardew (magnetic debris pull).

## Item model (generalizes the tool-only inventory)

- `ItemData` (base Resource): `display_name`, `max_stack` (1 for tools, e.g. 64 for
  resources), a short `glyph`/icon-later, category. `ToolData` EXTENDS `ItemData`
  (adds atk/power/break_threshold/wear_max/harvest_type/blade_color).
- `ItemStack`: `{ item: ItemData, count: int }` -- what an inventory slot holds now.
  Tools are non-stackable (max_stack 1); resources stack to `max_stack`.
- Inventory generalized: slots hold `ItemStack` (or null). `add_item(item, count)`
  fills existing matching stacks first (up to max_stack) then new slots; returns any
  overflow. Tools auto-populate the hotbar front; resources land in the background
  (the `sort()` intent from design-inventory.md). EQUIP: only a `ToolData` equips as a
  weapon; a resource stack or empty slot -> unarmed.
- Resource items as `.tres`: Wood (from trees), Stone / ore (from minerals). max_stack ~64.

## Harvest yield (hook the EXISTING harvest chokepoint)

The Hurtbox/material path already resolves a harvest hit (integrity drop / destroy).
Attach a yield rule per resource:
- **Tree**: yields NOTHING per chop; on FELL (integrity 0 -> destroyed) -> spawn a burst
  of Wood drops. ("Nothing until it's chopped down.")
- **Mineral**: each successful mine (integrity drop, one chunk breaking off) -> spawn ONE
  Stone/ore drop. ("Gradually give the resource per pick.")

## Drops -- managed world entities (SPRAWL-CRITICAL)

Per patterns/persistent-world-scaling-pitfalls.md, dropped items are the #1 sprawl
vector -- treat them as culled, chunk-owned, pooled from day one.
- `Drop` scene: a small primitive (mini version of the resource -- e.g. a little brown
  square for wood, small gray bit for stone) + a pickup detection Area2D. Carries its
  `ItemData` + `count` + a `lifetime` (default 300s).
- **Magnetic pickup**: the player has a pickup-radius Area2D. A drop inside it slides
  toward the player (a pull force) and is grabbed on contact -> `Inventory.add_item()`
  -> drop freed. (Stardew feel; no button.)
- **Lifetime / cull**: default 300s (5 real-min), tunable. Ages ONLY while its chunk is
  loaded (active). Despawn at lifetime. This is the anti-Project-Zomboid cull.
- **Chunk-ownership + persistence**: drops are chunk content (spawned into the chunk
  container like trees/rocks). On chunk unload -> written back into `ChunkData` as a
  delta entry (`Kind.DROP` with item id + count + remaining age); on reload ->
  respawned. Reuses the C3b store. So drops are cheap DATA when dormant, culled at 5
  active-minutes -- bounded, not accumulating.

## Interaction 'f' (framework -- deferred to E4/later)

Harvest is attack-driven (above), so 'f' is NOT needed for harvesting. 'f' is the
context-interact key for doors / chests / talking / picking up a *placed* item you do
not want auto-grabbed. Reuse recipes/interaction-system.md (player interaction Area2D,
nearby Interactables register, 'f' fires the nearest). DEFERRED until there are
interactables (doors/chests) to act on -- no point building the framework with nothing
to interact with yet.

## Build sub-sequence

- **E1a** (prerequisite / debt paydown): extract the equipment subsystem (equip_tool /
  _apply_equipped / _apply_unarmed / durability map / inventory-input handling) out of
  `player.gd` (549 lines, over the CONVENTIONS 500 cap) into an `Equipment` component.
  PURE refactor, no behavior change (anchor: the same 142 assertions), and it gives the
  item system a clean home so E1b does not bloat player.gd further.
- **E1b**: `ItemData` base + `ToolData` extends it; `ItemStack`; generalize `Inventory`
  to stacks + `add_item`; Wood/Stone resource items; equip only tools; HUD shows a
  stack's count. Headless-verified (stacking, tool non-stacking, equip still works).
- **E2**: harvest yield -- tree-on-fell, mineral-per-hit -- spawning drops (spawn a Drop
  at the harvest point via the existing chokepoint).
- **E3**: `Drop` entity + magnetic auto-pickup + 5-min lifetime + chunk-persist
  (`Kind.DROP` in ChunkData, age-while-loaded). Headless-verified (walk-over pickup adds
  to inventory; lifetime despawn; persists across unload/reload).
- **E4** (later): 'f' interaction framework + first interactables (a door / chest).

*Verified against: Godot 4.7.1. Last updated: 2026-07-18*
