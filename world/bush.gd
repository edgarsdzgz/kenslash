class_name Bush
extends Forageable
## A forageable BUSH -- the FIRST E4 interactable (design-items.md "Interaction 'f'"). Now a THIN
## subclass of world/forageable.gd: the base owns the shared mechanism (the "interactables" group-join,
## the interact_prompt() verb, and the interact() collect-then-free). This script authors ONLY what makes
## a bush a bush -- the verb "Harvest" and its Sticks + Fiber yields.
##
## Root is a plain Node2D, NOT a StaticBody2D/Area2D -- it has NO collision of any kind, so the player
## walks straight THROUGH it (a bush is soft ground cover, not an obstacle). It draws position-based (a
## small green triangle at its global_position), so it Y-sorts under the same chunk container as
## trees/rocks/drops, consistent with those entities.
##
## Yields are DATA-DRIVEN exports (yield_item_a/count_a + yield_item_b/count_b), so a chunk or main.tscn
## can author a differently-stocked bush with no code edits -- defaulting to the Sticks + Fiber a wild
## bush gives. The forage test reads yield_count_a / yield_count_b straight off the instance.

## The primary + secondary resources a harvested bush yields, and how many of each. Sticks + Fiber by
## default (a wild forage bush). Data-driven so an authored variant can differ.
@export var yield_item_a: ItemData = preload("res://data/stick.tres")
@export var yield_count_a: int = 2
@export var yield_item_b: ItemData = preload("res://data/fiber.tres")
@export var yield_count_b: int = 1


## Author this forageable's verb (the base defaults it to a generic "Forage"). A bush is harvested.
func _init() -> void:
	verb = "Harvest"


## The bush's two yields (base contract): Sticks then Fiber, in that order -- guarded + collected by
## Forageable.interact().
func _forage_yields() -> Array:
	return [[yield_item_a, yield_count_a], [yield_item_b, yield_count_b]]

# Verified against: Godot 4.7.1 (2026-07-19)
