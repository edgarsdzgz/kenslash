class_name Pebble
extends Forageable
## A forageable PEBBLE -- a small stone the player gathers WITHOUT a pickaxe (design-items.md
## "Interaction 'f'"). Now a THIN subclass of world/forageable.gd (the same E4 framework as the bush):
## the base owns the shared mechanism (the "interactables" group-join, the interact_prompt() verb, and
## the interact() collect-then-free). This script authors ONLY what makes a pebble a pebble -- the verb
## "Gather" and its single Stone yield. The big minable Rock still needs the pickaxe (its own Hurtbox).
##
## Root is a plain Node2D, NOT a StaticBody2D/Area2D -- it has NO collision of any kind, so the player
## walks straight THROUGH it (a loose pebble is not an obstacle). It draws position-based (a small gray
## hexagon at its global_position), so it Y-sorts under the same chunk container as
## trees/rocks/bushes/drops, consistent with those entities.
##
## The yield is a DATA-DRIVEN export (yield_item + yield_count) -- just ONE (unlike the bush's two),
## reflecting a smaller forage -- so a chunk or main.tscn can author a differently-stocked pebble with no
## code edits, defaulting to the single Stone a wild pebble gives. The test reads yield_count off it.

## The resource a gathered pebble yields, and how many. One Stone by default (a loose pebble).
## Data-driven so an authored variant can differ.
@export var yield_item: ItemData = preload("res://data/stone.tres")
@export var yield_count: int = 1


## Author this forageable's verb (the base defaults it to a generic "Forage"). A pebble is gathered.
func _init() -> void:
	verb = "Gather"


## The pebble's single yield (base contract): one Stone -- guarded + collected by Forageable.interact().
func _forage_yields() -> Array:
	return [[yield_item, yield_count]]

# Verified against: Godot 4.7.1 (2026-07-19)
