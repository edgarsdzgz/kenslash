# Milestone D -- The Playable Loop (boot into the biome)

Decided 2026-07-17. Turns the streaming biome (Milestone C) from a proving ground into
the actual game you boot into and play: wander, fight, harvest, die, respawn -- with the
built world PRESERVED across death. Placeholder-primitive visuals still; this is the
game-loop layer, not an art pass.

## D1 -- Boot + world-preserving respawn

**Boot scene**: `project.godot` `application/run/main_scene` -> `res://world/streaming_world.tscn`.
`main.tscn` (the arena) STAYS as the combat/test fixture -- the 118-assertion suite loads
it directly via `load("res://main.tscn")`, unaffected by the default-boot change. So
`kenslash` now launches the biome; tests still use the arena.

**The death problem**: `player.gd _on_died` currently ends with `reload_current_scene()`.
In the streaming world that would destroy the ChunkManager and its in-memory delta store
-- the whole built/harvested world resets on every death. Wrong for an explorable world.

**The fix -- a respawn policy on the player, so arena behavior is unchanged**:
- Add `var respawn_point: Vector2 = Vector2.INF` to the player. `INF` = "no respawn point
  -> reload the scene" (the arena's existing round-restart behavior, preserved). A finite
  value = "respawn IN PLACE at this point, keep the world."
- `streaming_world.gd` sets `player.respawn_point = <spawn>` (Vector2.ZERO for now) in
  `_ready`. This is the concrete first instance of the DECIDED checkpoint-based respawn
  (design DESIGN.md): spawn = origin now; a checkpoint system later just updates
  `respawn_point` to the last checkpoint reached.
- `_on_died` (after the existing burst + brief pause): if `respawn_point` is finite ->
  `_respawn_in_place()` (reposition to respawn_point; revive health to max; clear
  knockback/velocity/combo/attacking; re-show body/blade; unpause) and the ChunkManager +
  its store SURVIVE (the world is intact, harvested rocks stay harvested). Else (arena) ->
  `reload_current_scene()` as before.
- `HealthComponent` gains a `revive()` (set current_health = max_health) so the player can
  die again after respawn (died re-fires on the next 0).

**Verify headless (in test_streaming or a new test_playable)**: set `respawn_point`, damage
the player to death, await the death sequence; assert (a) player is back at respawn_point,
(b) health == max, (c) the ChunkManager still exists / the streamed world was NOT reloaded
(e.g. a pre-death chunk mutation / the same manager instance persists). Arena death path
(respawn_point == INF) still reloads -- keep the existing behavior intact; the 118 suite
stays green (no test kills the arena player to death).

## D2 -- Minimal HUD

A `CanvasLayer` HUD in `streaming_world.tscn` (Control nodes, placeholder styling, no art),
reading live player state -- NOT owning game state (presentation only, per
game-code-organization.md):
- **Health**: a bar or `current/max` readout, updates on `HealthComponent.damaged`/heal
  and on respawn.
- **Equipped tool**: the active tool's name + its durability (current/max), updates on
  equip and on wear; shows "Unarmed" for an empty slot.
- **Hotbar**: the 6 inventory slots, showing each tool (name/letter) and highlighting the
  equipped one; updates on any equip/cycle.
Wire via the existing signals/chokepoints (HealthComponent signals, DurabilityComponent
`durability_changed`, the inventory equip path) -- the HUD subscribes, never polls game
logic into itself. Headless: assert the HUD nodes reflect state after a damage / equip /
wear (read the label text or a bound value).

## Deliberately later (not D)
Checkpoints (respawn_point = last checkpoint), lives/game-over, pause + main menus, spawn-
area-clear (don't spawn inside a rock), audio. HUD art/polish is a `/4-design` pass later.

## Build order
D1 (boot + respawn -- systems, headless-verified) then D2 (HUD -- presentation, headless-
verified). Neither touches main.tscn's contents or the combat suite's intent.

*Verified against: Godot 4.7.1. Last updated: 2026-07-17*
