class_name Drop
extends Node2D
## A dropped world item -- the VISUAL + DATA carrier a harvest spawns (Milestone E2,
## design-items.md "Harvest yield" / "Drops"). It holds the ItemData it represents plus a
## count, and paints a small ground primitive in that item's `color`, so a drop reads as a
## shrunk version of its resource (a little brown square for Wood, a gray bit for Stone).
##
## SCOPE (E2 spawn + E3a magnet + E3b cull) -- still deliberately minimal. A Drop SPAWNS, is
## VISIBLE, carries item+count, is magnet-collectable (E3a lives in player.gd _process_pickups),
## and now AGES OUT after a `lifetime` (E3b, below). Chunk-persistence (ChunkData.Kind.DROP
## write-back / resume-aging-on-reload) is STILL deferred to E3c -- there is NO Area2D on the
## Drop, NO Timer, and NO persistence hook here yet. The cull rides a plain _physics_process.
##
## Rendered position-based (a plain Node2D at its global_position, small relative to a block
## per components/world_scale.gd) so it Y-sorts under the same parent container as trees and
## rocks, consistent with how those entities draw.

## The item this drop represents (its display_name / glyph / color). Null until setup().
var item: ItemData = null
## How many of `item` this single drop carries. E2 yield spawns bursts of count-1 drops.
var count: int = 0

## Seconds this drop may exist (while loaded) before it despawns. Default 300s = 5 REAL-minutes
## -- the anti-Project-Zomboid cull that keeps ground litter from accumulating without bound
## (patterns/persistent-world-scaling-pitfalls.md: drops are the #1 sprawl vector). Tunable
## per-instance so a caller can spawn short-lived debris or (later) longer-lived items.
@export var lifetime: float = 300.0
## Elapsed seconds this drop has existed WHILE its chunk was loaded (see _physics_process). A
## live Drop only exists as a node while its chunk is active, so simply accumulating physics
## delta here IS "age only while loaded" -- there is no extra gating to do. E3c will persist the
## REMAINING lifetime (`lifetime - _age`) so a reloaded drop resumes aging; `_age` and `lifetime`
## are kept as plain readable fields for that future write-back. NOT built here.
var _age: float = 0.0

@onready var _body: Polygon2D = $Body


## Store the item + count and tint the body to the item's world color. Called by the
## harvester right after instancing. It may run BEFORE the node has entered the tree (the
## deferred add_child pattern), in which case `_body` is still null here and the tint is
## (re)applied by _ready instead -- whichever fires last wins, and both paths agree.
func setup(p_item: ItemData, p_count: int) -> void:
	item = p_item
	count = p_count
	if _body != null and item != null:
		_body.color = item.color


func _ready() -> void:
	# Join the "drops" group so the player's magnetic auto-pickup (E3a, player.gd
	# _process_pickups) can find every ground drop with one group query -- the same
	# group-lookup contract the enemy AI uses to reach the "player". Pure membership; a
	# Drop stays a plain Node2D (no Area2D), so this adds no node to the scene.
	add_to_group("drops")
	# setup() may have run while this node was still outside the tree (_body null then), so
	# apply the tint here too. If setup() has not run yet, item is null and the Body keeps
	# its scene-default gray until a later setup().
	if item != null:
		_body.color = item.color


## Age the drop and despawn it once its lifetime is exhausted. Runs on the FIXED physics step
## (not idle _process) so the elapsed count is deterministic for the headless suite. Because a
## live Drop only exists as a node while its chunk is ACTIVE, accumulating delta here inherently
## ages the drop "only while loaded" -- an unloaded chunk's drops are not nodes and do not tick.
## Bails once queued for deletion so a drop that ages out (or is freed mid-magnet-pull by
## player.gd _process_pickups) does not keep re-counting or double-free.
func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	_age += delta
	if _age >= lifetime:
		queue_free()

# Verified against: Godot 4.7.1 (2026-07-18)
