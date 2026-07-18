class_name Bush
extends Node2D
## A forageable BUSH -- the FIRST E4 interactable (design-items.md "Interaction 'f'"). Unlike
## a Tree/Rock (attack-driven harvest via a Hurtbox), a bush is harvested by the player
## pressing the action button while standing on it, resolved by the pure-logic Interaction
## subsystem (components/interaction.gd) scanning the "interactables" group.
##
## Root is a plain Node2D, NOT a StaticBody2D/Area2D -- it has NO collision of any kind, so
## the player walks straight THROUGH it (a bush is soft ground cover, not an obstacle). It
## draws position-based (a small green triangle at its global_position), so it Y-sorts under
## the same chunk container as trees/rocks/drops, consistent with those entities.
##
## Yields are DATA-DRIVEN exports (yield_item_a/count_a + yield_item_b/count_b), so a chunk
## or main.tscn can author a differently-stocked bush with no code edits -- defaulting to the
## Sticks + Fiber a wild bush gives.

## The primary + secondary resources a harvested bush yields, and how many of each. Sticks +
## Fiber by default (a wild forage bush). Data-driven so an authored variant can differ.
@export var yield_item_a: ItemData = preload("res://data/stick.tres")
@export var yield_count_a: int = 2
@export var yield_item_b: ItemData = preload("res://data/fiber.tres")
@export var yield_count_b: int = 1


func _ready() -> void:
	# Join the group the Interaction subsystem scans (components/interaction.gd), the same
	# group-lookup contract drops use for the pickup magnet. Pure membership -- a bush stays
	# a plain Node2D (no Area2D), so this adds no node to the streaming node-count baseline.
	add_to_group("interactables")


## The verb the HUD shows after the action key (the Interaction contract). A bush is harvested.
func interact_prompt() -> String:
	return "Harvest"


## Harvest this bush (the Interaction contract): add both yields to the player's inventory via
## the E3a collect() facade, then remove the bush instantly (queue_free). Foraging is instant,
## so an overflowing yield on a FULL inventory is simply dropped -- the bush still vanishes
## (simplest of the two design-items.md options; no ground Drop is spawned for the overflow).
## Null yields are guarded so a partially-authored bush cannot crash the harvest.
func interact(player: Node) -> void:
	if yield_item_a != null and yield_count_a > 0:
		player.collect(yield_item_a, yield_count_a)
	if yield_item_b != null and yield_count_b > 0:
		player.collect(yield_item_b, yield_count_b)
	queue_free()

# Verified against: Godot 4.7.1 (2026-07-18)
