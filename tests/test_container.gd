class_name TestContainer extends RefCounted
## EPIC 2 Phase 2 Part 2.1 -- storage CONTAINER entity + the KIND-AGNOSTIC placement/persistence path (plan-
## epic2-parts.md Phase 2). A storage Container is the SECOND placeable, riding the SAME build + streaming-delta
## path a Station does (resolving the reviewer-flagged place_station STATION-hardcoding): it differs only in its
## placement_kind() (Kind.CONTAINER) and its own build cost. NARROW SCOPE (Part 2.1): the entity places for its
## cost, exposes an internal Inventory, and an EMPTY container round-trips across unload/reload. Item TRANSFER +
## CONTENTS persistence are Part 2.2 -- NOT asserted here.
##
## Three self-contained legs, each at REMOTE coords clear of every other module's content + of each other, so no
## placeable wanders into another module's group scan and no two hand-driven managers co-activate:
##   A (build cost, Builder-direct -- mirrors test_builder): a Container PLACES for its authored build cost
##     (wood x4) ATOMICALLY -- exact consume, joins the "container" group, exposes its internal Inventory; a short
##     cost REFUSES and consumes nothing. Proves Builder is kind-agnostic (places a Container, never `as Station`).
##   B (persistence): a placed EMPTY container survives chunk unload/reload as a Kind.CONTAINER ADDITION delta --
##     kept (NOT gone-flagged) on unload by the GENERALIZED deactivate-skip, respawned at the SAME pos on reload,
##     zero-orphan. Proves the kind-agnostic delta path + ChunkData.is_addition_kind cover CONTAINER.
##   C (BOTH kinds in ONE chunk): a Station AND a Container placed in the same chunk BOTH round-trip -- each back
##     at its own position as its own kind, no loss/double/mixup. Proves the path handles a heterogeneous mix.
## Registered in tests/smoke_slash.gd after TestPlacementPersist.

const CONTAINER_SCENE: PackedScene = preload("res://world/container.tscn")
const STATION_SCENE: PackedScene = preload("res://world/station.tscn")

## Remote region clear of every other self-contained module (placement-persist 7000-15000, builder 120000,
## boulder 90000, station -90000, elevation 48000, pebble -60000, ...), so no placeable leaks into another
## module's scan and this test's placeables leak into none.
const HOME: Vector2 = Vector2(140000.0, 140000.0)          # Leg A: Builder-direct build (holder, coord irrelevant)
const FOCUS_B: Vector2i = Vector2i(21000, 21000)           # Leg B: empty-container round trip
const PLACE_LOCAL_B: Vector2 = Vector2(180.0, 240.0)
const FOCUS_C: Vector2i = Vector2i(22000, -22000)          # Leg C: station + container coexist
const STATION_TAG_C: StringName = &"depot"                 # distinctive (not the scene default &"forge")
const STATION_LOCAL_C: Vector2 = Vector2(120.0, 140.0)
const CONTAINER_LOCAL_C: Vector2 = Vector2(360.0, 300.0)
const SEED: int = 7


func run(ctx: TestContext) -> void:
	print("[container] --- Epic 2 Part 2.1: a storage Container places for its cost + an empty container round-trips (kind-agnostic path) ---")
	await _leg_build_cost(ctx)
	await _leg_persist(ctx)
	await _leg_both_kinds(ctx)


## Leg A: Builder places a Container for its authored build cost (wood x4) ATOMICALLY, joins the "container"
## group, exposes an internal Inventory; a short cost refuses and consumes nothing. Mirrors test_builder's shape.
func _leg_build_cost(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var builder: Builder = Builder.new()
	var WOOD: ItemData = load("res://data/wood.tres")

	# SUFFICIENT: wood 6 >= cost 4. can_place clears; place spawns at HOME under the holder, consuming EXACTLY 4.
	var inv: Inventory = Inventory.new()
	inv.add_item(WOOD, 6)
	var can_ok: bool = builder.can_place(CONTAINER_SCENE, inv)
	var placed: Node = builder.place(CONTAINER_SCENE, HOME, inv, holder)
	await ctx.tree.physics_frame
	var box: StorageContainer = placed as StorageContainer
	ctx.check(can_ok and box != null and box.is_in_group(StorageContainer.GROUP)
			and box.global_position == HOME and inv.count_of(WOOD) == 2
			and box.store != null,
		"place SPAWNS a Container at the target in the \"container\" group, consumes the EXACT build cost (wood 6 -> 2 surplus), and exposes an internal Inventory; can_place agreed (true)",
		"container did not place/charge/expose-store correctly (can=%s, box=%s, grouped=%s, pos=%s, wood=%d, store=%s)" % [str(can_ok), str(box != null), str(box != null and box.is_in_group(StorageContainer.GROUP)), str(box.global_position if box != null else Vector2.ZERO), inv.count_of(WOOD), str(box != null and box.store != null)])

	# INSUFFICIENT: wood 3 < 4. can_place false, place null, wood untouched (no partial consume), no new container.
	var before_count: int = _containers_under(holder).size()
	var inv_short: Inventory = Inventory.new()
	inv_short.add_item(WOOD, 3)
	var short_can: bool = builder.can_place(CONTAINER_SCENE, inv_short)
	var short_placed: Node = builder.place(CONTAINER_SCENE, HOME + Vector2(200.0, 0.0), inv_short, holder)
	await ctx.tree.physics_frame
	ctx.check(not short_can and short_placed == null and inv_short.count_of(WOOD) == 3
			and _containers_under(holder).size() == before_count,
		"INSUFFICIENT (wood 3 < 4): place REFUSES and consumes NOTHING -- wood stays 3 (not drained), no container spawned; can_place agreed (false)",
		"insufficient container placement was not atomic (can=%s, placed=%s, wood=%d, spawned=%d)" % [str(short_can), str(short_placed != null), inv_short.count_of(WOOD), _containers_under(holder).size() - before_count])

	holder.queue_free()
	await ctx.tree.physics_frame


## Leg B: an EMPTY placed container survives unload/reload as a Kind.CONTAINER ADDITION delta -- kept (not gone-
## flagged) by the GENERALIZED deactivate-skip, respawned at the same pos on reload, zero-orphan. Hand-driven
## ChunkManager (load_radius 1 -> a 3x3 set, so one short hop unloads the focus chunk and back reloads it).
func _leg_persist(ctx: TestContext) -> void:
	var mgr: ChunkManager = ChunkManager.new()
	mgr.load_radius = 1
	mgr.world_seed = SEED
	ctx.tree.root.add_child(mgr)
	var mover: Node2D = Node2D.new()
	ctx.tree.root.add_child(mover)
	mgr.target = mover

	mover.global_position = WorldScale.chunk_origin(FOCUS_B) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var container: Node2D = mgr.active_container(FOCUS_B)

	# Place WHILE ACTIVE: a live Container child + the registered CONTAINER addition (keyed by the entity's OWN
	# placement_kind() + capture_state() -- the placeable contract, not a hardcoded kind). Registering after
	# activation appends the entry BEYOND _content, the case the generalized addition-skip must handle.
	var world_pos: Vector2 = WorldScale.chunk_origin(FOCUS_B) + PLACE_LOCAL_B
	var live_box: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	container.add_child(live_box)
	live_box.global_position = world_pos
	mgr.register_placement(world_pos, live_box.placement_kind(), live_box.capture_state())
	await ctx.tree.physics_frame

	var stored: ChunkData = mgr.stored_data(FOCUS_B)
	var adds: Array = _container_entries(stored)
	ctx.check(_containers_in(container).size() == 1 and adds.size() == 1 and stored != null and stored.dirty,
		"place-while-active: exactly ONE live Container is present AND recorded as ONE Kind.CONTAINER ADDITION delta (via placement_kind()/capture_state()) on the owning chunk -- a dirty delta chunk",
		"container place/record wrong (live=" + str(_containers_in(container).size()) + " adds=" + str(adds.size()) + ")")

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# UNLOAD: the GENERALIZED skip (ChunkData.is_addition_kind covers CONTAINER) must KEEP the addition, never
	# gone-flag it, even though its index sits beyond _content.
	mover.global_position = WorldScale.chunk_origin(FOCUS_B + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var kept: Array = _container_entries(mgr.stored_data(FOCUS_B))
	ctx.check(kept.size() == 1 and not _any_gone(kept),
		"persist-across-unload: the unloaded chunk still holds its ONE CONTAINER addition (kept, NOT gone-flagged) -- the generalized deactivate-skip covers containers",
		"container addition was lost or gone-flagged on unload (kept=" + str(kept.size()) + ")")

	# RELOAD: spawn() re-creates the container from the addition through the kind-agnostic path (apply_state).
	mover.global_position = WorldScale.chunk_origin(FOCUS_B) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rc: Node2D = mgr.active_container(FOCUS_B)
	var reloaded: Array = _containers_in(rc)
	var reload_ok: bool = reloaded.size() == 1 \
		and (reloaded[0] as StorageContainer).store != null \
		and world_pos.distance_to((reloaded[0] as StorageContainer).global_position) < 0.5
	ctx.check(reload_ok,
		"reload-round-trip: EXACTLY one empty Container respawned at the SAME position (no double, no loss), carrying a fresh internal Inventory -- dormant CONTAINER delta became a node again",
		"container did not round-trip correctly (count=" + str(reloaded.size()) + ")")

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"zero-orphan-leak: orphan node count did not grow across place -> unload -> reload (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"orphan nodes leaked across the container round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	mgr.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## Leg C: a Station AND a Container placed in the SAME chunk BOTH round-trip -- proving the kind-agnostic path
## handles a heterogeneous mix of addition kinds, each re-created as its own kind at its own position.
func _leg_both_kinds(ctx: TestContext) -> void:
	var mgr: ChunkManager = ChunkManager.new()
	mgr.load_radius = 1
	mgr.world_seed = SEED
	ctx.tree.root.add_child(mgr)
	var mover: Node2D = Node2D.new()
	ctx.tree.root.add_child(mover)
	mgr.target = mover

	mover.global_position = WorldScale.chunk_origin(FOCUS_C) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	var station_pos: Vector2 = WorldScale.chunk_origin(FOCUS_C) + STATION_LOCAL_C
	var box_pos: Vector2 = WorldScale.chunk_origin(FOCUS_C) + CONTAINER_LOCAL_C
	mgr.register_placement(station_pos, ChunkData.Kind.STATION, {"station_tag": String(STATION_TAG_C)})
	mgr.register_placement(box_pos, ChunkData.Kind.CONTAINER, {})
	await ctx.tree.physics_frame

	var stored: ChunkData = mgr.stored_data(FOCUS_C)
	ctx.check(_station_entries(stored).size() == 1 and _container_entries(stored).size() == 1 and stored.dirty,
		"place: a STATION and a CONTAINER recorded as distinct ADDITION deltas on the SAME chunk " + str(FOCUS_C) + " (one of each kind, a dirty delta chunk)",
		"both-kinds place wrong (stations=" + str(_station_entries(stored).size()) + " containers=" + str(_container_entries(stored).size()) + ")")

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# UNLOAD -> RELOAD.
	mover.global_position = WorldScale.chunk_origin(FOCUS_C + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var kept_stations: Array = _station_entries(mgr.stored_data(FOCUS_C))
	var kept_boxes: Array = _container_entries(mgr.stored_data(FOCUS_C))
	ctx.check(kept_stations.size() == 1 and kept_boxes.size() == 1 and not _any_gone(kept_stations) and not _any_gone(kept_boxes),
		"unload: BOTH additions kept (neither gone-flagged) -- the generalized skip covers a mixed station+container chunk",
		"both-kinds unload lost/gone-flagged an addition (stations=" + str(kept_stations.size()) + " containers=" + str(kept_boxes.size()) + ")")

	mover.global_position = WorldScale.chunk_origin(FOCUS_C) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rc: Node2D = mgr.active_container(FOCUS_C)
	var stations: Array = _stations_in(rc)
	var boxes: Array = _containers_in(rc)
	var both_ok: bool = stations.size() == 1 and boxes.size() == 1 \
		and (stations[0] as Station).station_tag == STATION_TAG_C \
		and station_pos.distance_to((stations[0] as Station).global_position) < 0.5 \
		and box_pos.distance_to((boxes[0] as StorageContainer).global_position) < 0.5
	ctx.check(both_ok,
		"reload: BOTH kinds round-tripped -- the Station back at its pos with tag " + str(STATION_TAG_C) + " AND the Container back at its own pos, each re-created as its own kind (no mixup, no loss)",
		"both-kinds reload wrong (stations=" + str(stations.size()) + " containers=" + str(boxes.size()) + " tag_ok=" + str(stations.size() == 1 and (stations[0] as Station).station_tag == STATION_TAG_C) + ")")

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"zero-orphan-leak: orphan node count did not grow across the mixed station+container round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"orphan nodes leaked across the both-kinds round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	mgr.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## The live StorageContainer instances directly under a chunk container / holder (empty if null).
func _containers_in(container: Node2D) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is StorageContainer:
			out.append(child)
	return out


## Alias for a plain holder Node (Leg A) -- same scan, named for the test's readability.
func _containers_under(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child is StorageContainer:
			out.append(child)
	return out


## The live Station instances directly under a chunk container (empty if null).
func _stations_in(container: Node2D) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is Station:
			out.append(child)
	return out


## The Kind.CONTAINER ADDITION entries of a stored ChunkData (empty if null).
func _container_entries(cd: ChunkData) -> Array:
	return _entries_of_kind(cd, ChunkData.Kind.CONTAINER)


## The Kind.STATION ADDITION entries of a stored ChunkData (empty if null).
func _station_entries(cd: ChunkData) -> Array:
	return _entries_of_kind(cd, ChunkData.Kind.STATION)


func _entries_of_kind(cd: ChunkData, kind: int) -> Array:
	var out: Array = []
	if cd == null:
		return out
	for e in cd.entries:
		if int(e["type"]) == kind:
			out.append(e)
	return out


## True iff any of the given entries is flagged `gone` (an ADDITION should NEVER be -- it is permanent).
func _any_gone(entries: Array) -> bool:
	for e in entries:
		if bool((e["state"] as Dictionary).get("gone", false)):
			return true
	return false

# Verified against: Godot 4.7.1 (2026-07-20)
