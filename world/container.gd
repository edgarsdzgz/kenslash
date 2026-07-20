class_name StorageContainer
extends Placeable
## A placeable STORAGE CONTAINER (plan-epic2-parts.md Phase 2 Part 2.1; design-crafting.md "Track B -- Building").
## The SECOND placeable (after the crafting Station) and the first that resolves the reviewer-flagged place_station
## hardcoding: it rides the SAME kind-agnostic build/persistence path as a Station, differing only in its
## placement_kind() (CONTAINER) and its own build cost. A chest you place in the world and later stash items in.
##
## `class_name StorageContainer`, NOT `Container`: `Container` is a BUILT-IN Godot class (the Control layout base
## for HBoxContainer/VBoxContainer/...), so `class_name Container` collides with the native namespace and fails to
## parse -- the same native-class clash world/tree.gd documents (it drops its class_name entirely). The FILE stays
## container.gd / container.tscn (the plan's name); the SCRIPT class is StorageContainer so tests can `is`-check it.
##
## Holds its OWN components/inventory.gd store (DRY -- a container reuses the player's slot+weight inventory model,
## plan-epic2-parts.md open-confirmation #4). The store is a RefCounted field, NOT a Node child, so it never
## perturbs the streaming node-count / orphan baselines (freed with the container when its refcount drops). Part
## 2.1 scope is the ENTITY + its EMPTY-container round-trip ONLY: the store exists and is exposed, but item
## TRANSFER (store/retrieve) and CONTENTS persistence are Part 2.2 -- for now an empty container round-trips as
## pure identity (kind + position), capture_state()/apply_state() carrying no contents yet.
##
## A plain Node2D in the "container" group (no collision) -- like Station/Forageable, a thing you stand NEXT TO
## and interact with, not a wall. The group is what Part 2.2's transfer interaction (and tests) scan to find a
## container in range, exactly as Station.tags_in_range scans the "station" group.
##
## DETERMINISM: build cost + persistence are pure data (authored exports + plain-Dictionary state), no Time/OS/RNG.

## The group every StorageContainer joins -- the one Part 2.2's transfer scan (and the tests) look it up by. A
## StringName const so the join and the scan reference the SAME key (never a typo'd literal in two places).
const GROUP: StringName = &"container"

## This container's internal store (design-inventory.md), a fresh per-instance Inventory (RefCounted -- the `.new()`
## initializer runs per _init, so no two containers ever alias one store, avoiding the shared-default trap). Item
## TRANSFER into/out of it is Part 2.2; for Part 2.1 it starts EMPTY and is only EXPOSED (the goal-post assertion
## that a placed container carries an internal Inventory). A public field so Part 2.2's transfer op + the tests
## read it directly, mirroring how the player exposes its own `inventory`.
var store: Inventory = Inventory.new()


func _ready() -> void:
	# Join the "container" group Part 2.2's transfer scan uses -- the same pure group-membership contract Station
	# and Forageable use. Membership on a plain Node2D (no Area2D), so this adds no collision node to the streaming
	# node-count baseline.
	add_to_group(GROUP)


## The persistence contract (world/placeable.gd): a container persists as a Kind.CONTAINER ADDITION delta, the
## mirror of a Station's STATION delta. Part 2.1: an EMPTY container round-trips as pure IDENTITY -- capture_state()
## records NO params (kind + position alone reproduce it) and apply_state() restores nothing. Part 2.2 adds the
## `store` contents to both halves here (serialize the Inventory's stacks, restore them on reload) with no change
## to the kind-agnostic path -- this file is the single place that knowledge will live.
func placement_kind() -> int:
	return ChunkData.Kind.CONTAINER


func capture_state() -> Dictionary:
	return {}


func apply_state(_state: Dictionary) -> void:
	pass

# Verified against: Godot 4.7.1 (2026-07-20)
