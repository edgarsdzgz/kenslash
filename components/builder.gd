class_name Builder
extends RefCounted
## PLACEMENT of a buildable world entity for a recipe-like BUILD COST (plan-epic2-parts.md Phase 1 Part 1.1;
## design-crafting.md "Track B -- Building / crafting"). The BUILD half of base-building: take a placeable's
## PackedScene, deduct its authored build cost from the player's Inventory, and spawn the entity into the world
## at a target position under a passed parent. The companion to Crafting: where Crafting turns inputs into an
## inventory OUTPUT, Builder turns inputs into a PLACED WORLD OBJECT. RefCounted (NOT a Node), exactly like
## components/crafting.gd / inventory.gd / known_recipes.gd, so it never perturbs the streaming node-count /
## orphan baselines and is directly testable with `Builder.new()` + plain component instances (no player/scene
## wiring needed).
##
## STATELESS. Holds NO per-placement state -- the cost lives on the placeable (Station.build_items /
## build_counts, the parallel-array idiom RecipeData uses for craft inputs), the materials live on the
## Inventory, the world lives under the passed `parent` -- so ONE Builder instance serves any placement (or a
## test can `Builder.new()` per call). It only ORCHESTRATES: read the authored cost off the scene, verify +
## consume it against the inventory, add the entity under the parent.
##
## ATOMIC. place() verifies EVERY build item is present BEFORE it removes anything; on ANY shortfall it consumes
## NOTHING and returns null -- never a partial deduction. The precheck alone makes consumption atomic (a
## fully-verified cost cannot partially fail on remove_item, mirroring how Crafting's input precheck guards its
## _consume). A snapshot additionally guards the one post-consume misuse that could strand an entity -- a
## `parent` that is not in the tree, so the placement never enters the world / joins the "station" group: that
## rolls the cost back and abandons the node, keeping a failed placement a true no-op. Determinism: pure
## membership + integer counts over the passed components; no Input/scene singleton/Time/OS/RNG (NOTES.md rule),
## so every placement is exactly headless-assertable and server-re-simulable.
##
## DECOUPLED. Builder reaches into NO specific scene singleton -- the caller passes the `parent` the entity is
## added under (a test's own holder; in-game, the streamed chunk/content root), so placement never hard-codes
## streaming_world or a chunk path. PERSISTENCE of the placed object as a world delta is Part 1.2; this part is
## purely the deterministic place op + its cost.


## Whether `inventory` holds the BUILD COST to place `station_scene` RIGHT NOW -- every distinct build item in
## at least its aggregated total count (duplicate rows summed first, exactly like Crafting.has_materials_for).
## A pure predicate that MATCHES place()'s accept/refuse without committing, so a future build-mode UI can grey
## out an un-affordable placement through this. Reads the authored cost off a THROWAWAY instance of the scene
## (the cost is an @export on the placeable) that is never added to the tree -- so its _ready never runs, it
## never joins the "station" group, and it is freed immediately. A null scene or inventory -> false.
func can_place(station_scene: PackedScene, inventory: Inventory) -> bool:
	if station_scene == null or inventory == null:
		return false
	var probe: Station = station_scene.instantiate() as Station
	if probe == null:
		return false
	var ok: bool = _has_cost(_aggregate_cost(probe), inventory)
	probe.free()  # never entered the tree (no _ready, no group join) -> immediate synchronous free
	return ok


## Place one `station_scene` at `world_pos` under `parent`, deducting its build cost from `inventory`. ATOMIC:
##   (1) instantiate the placeable and AGGREGATE its authored build cost (build_items/build_counts, duplicate
##       rows summed);
##   (2) PRECHECK every distinct build item is present in its total count -- on ANY shortfall, free the
##       throwaway instance (it never entered the tree, so nothing was placed) and return null, consuming
##       NOTHING;
##   (3) SNAPSHOT the inventory, CONSUME the exact per-item totals, then add the entity under `parent` (its
##       _ready joins the "station" group) and position it at `world_pos`;
##   (4) backstop the one post-consume misuse: if the entity did not actually enter the tree (a detached
##       `parent`), RESTORE the snapshot, abandon the node, and return null.
## Returns the live placed Station on success, else null with the inventory byte-identical to before (no
## partial consumption). Deterministic integer/membership work, no Time/OS/RNG. Decoupled -- takes `parent`,
## never reaches into a scene singleton.
func place(station_scene: PackedScene, world_pos: Vector2, inventory: Inventory, parent: Node) -> Node:
	if station_scene == null or inventory == null or parent == null:
		return null
	var station: Station = station_scene.instantiate() as Station
	if station == null:
		return null
	# (2) ATOMIC PRECHECK -- aggregate duplicate rows, verify every distinct build item's total is present
	# BEFORE removing any. A shortfall frees the never-added instance and consumes nothing.
	var cost: Dictionary = _aggregate_cost(station)
	if not _has_cost(cost, inventory):
		station.free()
		return null
	# (3) TRANSACTIONAL: snapshot, consume the exact per-item totals, then add + position the entity. add_child
	# runs _ready synchronously for an in-tree parent, so the station joins the "station" group here.
	var snap: Array = inventory.snapshot()
	_consume_cost(cost, inventory)
	parent.add_child(station)
	station.global_position = world_pos
	# (4) Backstop the one post-consume misuse: a `parent` outside the tree leaves the entity un-entered (no
	# _ready, no group join) -- not a real placement. Roll the cost back and abandon the node so a failed
	# placement consumes NOTHING, preserving the atomic contract.
	if not station.is_inside_tree():
		inventory.restore(snap)
		station.free()
		return null
	return station


## Aggregate a placeable's parallel build rows (build_items[i] / build_counts[i]) into a per-item TOTAL:
## ItemData -> summed count. Summing FIRST makes a cost that lists the SAME item twice correct (the precheck
## compares the SUM, the consume removes the SUM once per distinct item). A shorter counts array reads 0 for
## the missing tail; null items and non-positive counts are skipped (defensive). Mirrors
## Crafting._aggregate_inputs exactly. Pure -- builds a fresh Dictionary, changes nothing.
func _aggregate_cost(station: Station) -> Dictionary:
	var cost: Dictionary = {}
	for i in range(station.build_items.size()):
		var item: ItemData = station.build_items[i]
		if item == null:
			continue
		var need: int = station.build_counts[i] if i < station.build_counts.size() else 0
		if need <= 0:
			continue
		cost[item] = int(cost.get(item, 0)) + need
	return cost


## True IFF `inventory` holds every distinct build item in at least its aggregated total (the atomic precheck's
## material test). `cost` is the item -> total map from _aggregate_cost, so duplicate rows were already summed.
## Mirrors Crafting._has_inputs. An empty cost (a free placeable) is trivially true.
func _has_cost(cost: Dictionary, inventory: Inventory) -> bool:
	for item: ItemData in cost:
		if inventory.count_of(item) < int(cost[item]):
			return false
	return true


## Remove each distinct build item's aggregated total from the inventory. Called ONLY after _has_cost cleared,
## so each remove_item takes its full amount (never partial). Because `cost` sums duplicate rows, each item is
## removed EXACTLY once at its total. Mirrors Crafting._consume.
func _consume_cost(cost: Dictionary, inventory: Inventory) -> void:
	for item: ItemData in cost:
		inventory.remove_item(item, int(cost[item]))

# Verified against: Godot 4.7.1 (2026-07-20)
