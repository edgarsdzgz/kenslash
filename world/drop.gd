class_name Drop
extends Node2D
## A dropped world item -- the VISUAL + DATA carrier a harvest spawns (Milestone E2,
## design-items.md "Harvest yield" / "Drops"). It holds the ItemData it represents plus a
## count, and paints a small ground primitive in that item's `color`, so a drop reads as a
## shrunk version of its resource (a little brown square for Wood, a gray bit for Stone).
##
## E2 SCOPE -- deliberately minimal. A Drop only SPAWNS, is VISIBLE, and carries item+count.
## It sits where it lands. Magnetic auto-pickup (a pickup Area2D + pull), the 5-minute
## lifetime cull, and chunk-persistence (ChunkData.Kind.DROP write-back / age-while-loaded)
## are ALL deferred to E3 -- there is NO Area2D, NO Timer, and NO persistence hook here yet.
##
## Rendered position-based (a plain Node2D at its global_position, small relative to a block
## per components/world_scale.gd) so it Y-sorts under the same parent container as trees and
## rocks, consistent with how those entities draw.

## The item this drop represents (its display_name / glyph / color). Null until setup().
var item: ItemData = null
## How many of `item` this single drop carries. E2 yield spawns bursts of count-1 drops.
var count: int = 0

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

# Verified against: Godot 4.7.1 (2026-07-18)
