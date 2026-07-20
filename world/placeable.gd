class_name Placeable
extends Node2D
## Shared BASE for a BUILDABLE world entity the player places (Epic 2 -- Station, storage Container, and any
## future placeable). It owns the two things EVERY placeable shares so the placement/persistence path can be
## KIND-AGNOSTIC (Epic 2 Phase 2 Part 2.1, resolving the reviewer-flagged place_station hardcoding):
##   1. the recipe-like BUILD COST (build_items / build_counts) components/builder.gd reads + deducts to place
##      it -- so Builder types the instance as a Placeable and works for ANY placeable, never `as Station`; and
##   2. the small PERSISTENCE CONTRACT the streaming delta model uses to store + re-create it, kind-agnostically:
##        * placement_kind() -> int   -- the ChunkData.Kind this entity persists as (STATION / CONTAINER / ...).
##        * capture_state() -> Dictionary -- its persistable params, a store_var-/JSON-safe plain Dictionary
##          (Strings/ints/arrays only -- NO Nodes/Resources), recorded as the delta's `state` on placement.
##        * apply_state(state) -- restore those params BEFORE add_child (so _ready sees them), the inverse of
##          capture_state(): apply_state(capture_state()) reproduces the entity's identity.
## The contract is DUCK-TYPED through this base (no GDScript `interface`): streaming_world reads placement_kind()/
## capture_state() to record the right delta, and ChunkContent.spawn() apply_state()s a fresh instance on reload.
## Mirrors the base-class idiom world/forageable.gd and world/harvestable_body.gd already use -- shared mechanism
## on the base, per-kind identity on the thin subclass.
##
## A plain Node2D (no collision) -- placeables so far (Station, Container) are things you stand NEXT TO, not walls
## you bump into, so the base adds no physics body to the streaming node-count / orphan baselines. A subclass that
## needs solidity can add its own. RefCounted is NOT applicable: a placeable LIVES in the scene tree (it is a
## Node), unlike the RefCounted components (Inventory/Builder/...) it may hold.
##
## DETERMINISM: the contract is pure data (authored exports + plain-Dictionary state) -- no Input/Time/OS/RNG --
## so a placement is exactly headless-assertable and its delta round-trips byte-identically.

## BUILD COST to place this entity (plan-epic2-parts.md Phase 1) -- the item DEFINITIONS a placement CONSUMES,
## PARALLEL to build_counts (build_items[i] is spent build_counts[i] at a time). The recipe-like cost idiom
## RecipeData uses for craft inputs (input_items/input_counts), mirrored on the PLACEABLE so the cost is authored
## WORLD data on the scene. components/builder.gd reads + deducts these to place it; the placeable itself never
## touches an inventory (decoupled). Empty = a free placement. A subclass authors its own values on its scene.
@export var build_items: Array[ItemData] = []
## How many of each build_items[i] one placement consumes, PARALLEL to build_items (authored the same length).
## Aggregated (duplicate item rows summed) by components/builder.gd before its atomic precheck + consume.
@export var build_counts: Array[int] = []


## The ChunkData.Kind this placeable persists as (the streaming ADDITION delta type). A subclass MUST override
## with its concrete kind (STATION / CONTAINER / ...). The base default is an intentionally-invalid -1 so a
## placeable that forgot to declare its kind fails loudly rather than silently persisting as Kind 0 (TREE).
func placement_kind() -> int:
	return -1


## This placeable's persistable params as a plain, serializable Dictionary (the delta `state`) -- Strings/ints/
## arrays only, NEVER a Node or Resource. Recorded at placement time (streaming_world -> register_placement) and
## re-applied by apply_state() on reload. The base default is empty (a placeable with no params round-trips as
## pure identity: kind + position). A subclass overrides to add its params (a Station's station_tag, ...).
func capture_state() -> Dictionary:
	return {}


## Restore this placeable's persistable params from a capture_state() Dictionary -- the inverse of capture_state().
## Called by ChunkContent.spawn() on a FRESH instance BEFORE the caller add_child()s it, so _ready() sees the
## restored params (a Station joins the "station" group already carrying its tag). The base default is a no-op
## (nothing to restore for a params-less placeable). A subclass overrides to read its params back out.
func apply_state(_state: Dictionary) -> void:
	pass

# Verified against: Godot 4.7.1 (2026-07-20)
