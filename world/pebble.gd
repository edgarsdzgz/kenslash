class_name Pebble
extends Node2D
## A forageable PEBBLE -- a small stone the player gathers WITHOUT a pickaxe (design-items.md
## "Interaction 'f'"). A near-copy of world/bush.gd on the SAME E4 interactable framework: it
## is harvested by the player pressing the action button while standing on it, resolved by the
## pure-logic Interaction subsystem (components/interaction.gd) scanning the "interactables"
## group -- NOT by an attack-driven Hurtbox (the big minable Rock still needs the pickaxe).
##
## Root is a plain Node2D, NOT a StaticBody2D/Area2D -- it has NO collision of any kind, so the
## player walks straight THROUGH it (a loose pebble is not an obstacle). It draws position-based
## (a small gray hexagon at its global_position), so it Y-sorts under the same chunk container
## as trees/rocks/bushes/drops, consistent with those entities.
##
## The yield is a DATA-DRIVEN export (yield_item + yield_count), so a chunk or main.tscn can
## author a differently-stocked pebble with no code edits -- defaulting to the single Stone a
## wild pebble gives. Just ONE yield (unlike the bush's two), reflecting a smaller forage.

## The resource a gathered pebble yields, and how many. One Stone by default (a loose pebble).
## Data-driven so an authored variant can differ.
@export var yield_item: ItemData = preload("res://data/stone.tres")
@export var yield_count: int = 1


func _ready() -> void:
	# Join the group the Interaction subsystem scans (components/interaction.gd), the same
	# group-lookup contract the bush and the pickup magnet use. Pure membership -- a pebble stays
	# a plain Node2D (no Area2D), so this adds no node to the streaming node-count baseline.
	add_to_group("interactables")


## The verb the HUD shows after the action key (the Interaction contract). A pebble is gathered,
## so the HUD renders "[F] Gather".
func interact_prompt() -> String:
	return "Gather"


## Gather this pebble (the Interaction contract): add its single yield to the player's inventory
## via the E3a collect() facade, then remove the pebble instantly (queue_free). Foraging is
## instant, so an overflowing yield on a FULL inventory is simply dropped -- the pebble still
## vanishes (matches the bush; no ground Drop is spawned for the overflow). A null/zero yield is
## guarded so a partially-authored pebble cannot crash the gather.
func interact(player: Node) -> void:
	if yield_item != null and yield_count > 0:
		player.collect(yield_item, yield_count)
	queue_free()

# Verified against: Godot 4.7.1 (2026-07-19)
