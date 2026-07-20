class_name TestContainer extends RefCounted
## EPIC 2 Phase 2 Parts 2.1 + 2.2 -- storage CONTAINER entity, the KIND-AGNOSTIC placement/persistence path, AND
## atomic item TRANSFER + CONTENTS persistence (plan-epic2-parts.md Phase 2). A storage Container is the SECOND
## placeable, riding the SAME build + streaming-delta path a Station does (resolving the reviewer-flagged
## place_station STATION-hardcoding): it differs only in its placement_kind() (Kind.CONTAINER) and its own build
## cost. Part 2.1 proves the entity places for its cost, exposes an internal Inventory, and round-trips across
## unload/reload; Part 2.2 adds atomic deposit/withdraw and contents that ride the placement delta.
##
## SEVEN self-contained legs, each at REMOTE coords clear of every other module's content + of each other, so no
## placeable wanders into another module's group scan and no two hand-driven managers co-activate:
##   A (build cost, Builder-direct -- mirrors test_builder): a Container PLACES for its authored build cost
##     (wood x4) ATOMICALLY -- exact consume, joins the "container" group, exposes its internal Inventory; a short
##     cost REFUSES and consumes nothing. Proves Builder is kind-agnostic (places a Container, never `as Station`).
##   B (persistence): a placed EMPTY container survives chunk unload/reload as a Kind.CONTAINER ADDITION delta --
##     kept (NOT gone-flagged) on unload by the GENERALIZED deactivate-skip, respawned at the SAME pos on reload,
##     zero-orphan. Proves the kind-agnostic delta path + ChunkData.is_addition_kind cover CONTAINER.
##   C (BOTH kinds in ONE chunk): a Station AND a Container placed in the same chunk BOTH round-trip -- each back
##     at its own position as its own kind, no loss/double/mixup. Proves the path handles a heterogeneous mix.
##   D (Part 2.2 TRANSFER): the atomic deposit/withdraw primitive driven directly on a container's store -- exact
##     counts both ways with weight tracking; over-count / full-destination / zero-negative all REFUSE and move
##     NOTHING (the no-dupe/no-loss guarantee).
##   E (Part 2.2 CONTENTS PERSISTENCE): a placed container DEPOSITED into after placement, then unloaded + reloaded,
##     restores its EXACT contents -- the unload write-back serializes the live store into the delta, spawn()
##     ->apply_state() rebuilds it; zero-orphan.
##   F (Part 2.2 TWO CONTAINERS in ONE chunk): two placed containers with DISTINCT contents at DISTINCT positions
##     each round-trip their OWN contents -- proving the unload write-back matches each live box to its OWN entry
##     by local_pos with more than one box present; zero-orphan.
##   G (Part 2.2 DEFENSIVE load-failure): apply_state carrying an item path that does NOT resolve to an ItemData is
##     SKIPPED (the null-guard drops it) with no crash, and the other valid contents still restore.
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
const FOCUS_D: Vector2i = Vector2i(23000, 23000)           # _leg_contents_persist (Leg E; Leg D/transfer is coordless)
const PLACE_LOCAL_D: Vector2 = Vector2(220.0, 160.0)
const FOCUS_F: Vector2i = Vector2i(24000, -24000)          # Leg F: two containers, distinct contents, one chunk
const PLACE_LOCAL_F1: Vector2 = Vector2(120.0, 120.0)
const PLACE_LOCAL_F2: Vector2 = Vector2(360.0, 300.0)
const SEED: int = 7


func run(ctx: TestContext) -> void:
	print("[container] --- Epic 2 Part 2.1/2.2: a storage Container places, transfers items atomically, and round-trips its contents (kind-agnostic path) ---")
	await _leg_build_cost(ctx)
	await _leg_persist(ctx)
	await _leg_both_kinds(ctx)
	await _leg_transfer(ctx)          # Part 2.2: atomic deposit/withdraw
	await _leg_contents_persist(ctx)  # Part 2.2: contents ride the delta across unload/reload
	await _leg_two_containers(ctx)    # Part 2.2: two containers, distinct contents, one chunk
	await _leg_bad_path_skipped(ctx)  # Part 2.2: a non-ItemData path in apply_state is skipped, no crash


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


## Leg D (Part 2.2 TRANSFER): the atomic deposit/withdraw primitive, exercised directly on a StorageContainer's
## store (no streaming needed -- pure inventory logic). Proves EXACT-count moves both ways with weight tracking,
## and that an over-count OR a full-destination transfer REFUSES and moves NOTHING (the classic no-dupe/no-loss
## atomic guarantee), and that a zero/negative move is a no-op.
func _leg_transfer(ctx: TestContext) -> void:
	var WOOD: ItemData = load("res://data/wood.tres")
	var AXE: ItemData = load("res://data/axe_data.tres")  # a ToolData: max_stack 1 (non-stackable)
	var box: StorageContainer = StorageContainer.new()
	ctx.tree.root.add_child(box)  # _ready joins the group (harmless here); the store is what we drive
	var player_inv: Inventory = Inventory.new()
	player_inv.add_item(WOOD, 10)
	var p_wt0: float = player_inv.total_weight()

	# DEPOSIT 4 wood player->container: exact counts on BOTH sides, weight rides with the items.
	var moved: int = box.deposit(WOOD, 4, player_inv)
	ctx.check(moved == 4 and player_inv.count_of(WOOD) == 6 and box.store.count_of(WOOD) == 4
			and is_equal_approx(box.store.total_weight(), WOOD.weight * 4.0)
			and is_equal_approx(player_inv.total_weight(), p_wt0 - WOOD.weight * 4.0),
		"deposit: EXACTLY 4 wood moved player->container (player 10->6, container 0->4); weight shifted with them (container = 4*w, player down 4*w); no dupe/loss",
		"deposit was not exact/weight-aware (moved=%d, player=%d, box=%d, box_wt=%.1f)" % [moved, player_inv.count_of(WOOD), box.store.count_of(WOOD), box.store.total_weight()])

	# WITHDRAW 3 wood container->player: exact counts the other direction.
	var moved_out: int = box.withdraw(WOOD, 3, player_inv)
	ctx.check(moved_out == 3 and box.store.count_of(WOOD) == 1 and player_inv.count_of(WOOD) == 9,
		"withdraw: EXACTLY 3 wood moved container->player (container 4->1, player 6->9) -- the mirror direction, no dupe/loss",
		"withdraw was not exact (moved=%d, box=%d, player=%d)" % [moved_out, box.store.count_of(WOOD), player_inv.count_of(WOOD)])

	# OVER-COUNT REFUSAL: withdraw 5 when only 1 is present -> move NOTHING, both sides byte-identical.
	var box_w: int = box.store.count_of(WOOD)
	var pl_w: int = player_inv.count_of(WOOD)
	var over: int = box.withdraw(WOOD, 5, player_inv)
	ctx.check(over == 0 and box.store.count_of(WOOD) == box_w and player_inv.count_of(WOOD) == pl_w,
		"over-count REFUSES (withdraw 5 of 1): returns 0 and moves NOTHING -- container stays 1, player stays 9 (atomic, no partial, no loss)",
		"over-count withdraw was not atomic (ret=%d, box=%d, player=%d)" % [over, box.store.count_of(WOOD), player_inv.count_of(WOOD)])

	# ZERO / NEGATIVE: a no-op both ways (no move, returns 0), nothing perturbed.
	var zero_dep: int = box.deposit(WOOD, 0, player_inv)
	var neg_wd: int = box.withdraw(WOOD, -3, player_inv)
	ctx.check(zero_dep == 0 and neg_wd == 0 and box.store.count_of(WOOD) == box_w and player_inv.count_of(WOOD) == pl_w,
		"zero/negative move is a NO-OP: deposit(0) and withdraw(-3) each return 0 and change nothing on either side",
		"zero/negative move was not a no-op (zero=%d, neg=%d)" % [zero_dep, neg_wd])

	# FULL-DESTINATION REFUSAL: a 1-slot store already full (a non-stackable AXE) cannot accept a wood ->
	# refuse, source untouched, destination byte-identical (snapshot/restore rollback proven).
	var tiny: StorageContainer = StorageContainer.new()
	ctx.tree.root.add_child(tiny)
	tiny.store.slots.resize(1)          # a single-slot store
	tiny.store.add_item(AXE, 1)         # slot 0 full (AXE is max_stack 1) -- no room for anything else
	var full_inv: Inventory = Inventory.new()
	full_inv.add_item(WOOD, 5)
	var tiny_wt0: float = tiny.store.total_weight()
	var full_ret: int = tiny.deposit(WOOD, 1, full_inv)
	ctx.check(full_ret == 0 and full_inv.count_of(WOOD) == 5 and tiny.store.count_of(WOOD) == 0
			and is_equal_approx(tiny.store.total_weight(), tiny_wt0),
		"full-destination REFUSES: depositing into a 1-slot store already full moves NOTHING (source wood stays 5, container gains 0), store byte-identical -- atomic, no partial, no loss",
		"full-destination deposit was not atomic (ret=%d, src=%d, dst_wood=%d)" % [full_ret, full_inv.count_of(WOOD), tiny.store.count_of(WOOD)])

	# A refused deposit did NOT corrupt an UNRELATED item in the source (rollback touched only the tested item).
	ctx.check(full_inv.count_of(WOOD) == 5,
		"atomic isolation: the refused full-destination deposit left the source inventory wholly intact (wood still 5)",
		"refused deposit corrupted the source (wood=%d)" % full_inv.count_of(WOOD))

	box.queue_free()
	tiny.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## Leg E (Part 2.2 CONTENTS PERSISTENCE): a container placed while active, DEPOSITED into (the realistic flow --
## items added AFTER placement), then unloaded and reloaded, restores its EXACT contents. Proves the contents ride
## the SAME placement delta: the unload write-back serializes the live store into the CONTAINER entry's `state`, and
## spawn()->apply_state() rebuilds the store on reload. Hand-driven ChunkManager (load_radius 1 -> one hop unloads).
func _leg_contents_persist(ctx: TestContext) -> void:
	var WOOD: ItemData = load("res://data/wood.tres")
	var STONE: ItemData = load("res://data/stone.tres")
	var mgr: ChunkManager = ChunkManager.new()
	mgr.load_radius = 1
	mgr.world_seed = SEED
	ctx.tree.root.add_child(mgr)
	var mover: Node2D = Node2D.new()
	ctx.tree.root.add_child(mover)
	mgr.target = mover

	mover.global_position = WorldScale.chunk_origin(FOCUS_D) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var container: Node2D = mgr.active_container(FOCUS_D)

	# Place a live container WHILE ACTIVE + register the (empty) addition -- the entry appends BEYOND _content.
	var world_pos: Vector2 = WorldScale.chunk_origin(FOCUS_D) + PLACE_LOCAL_D
	var live_box: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	container.add_child(live_box)
	live_box.global_position = world_pos
	mgr.register_placement(world_pos, live_box.placement_kind(), live_box.capture_state())

	# DEPOSIT into the live container AFTER placement (so the contents exist only on the live node, NOT yet in
	# the recorded delta -- exactly what the unload write-back must capture).
	var source: Inventory = Inventory.new()
	source.add_item(WOOD, 7)
	source.add_item(STONE, 3)
	live_box.deposit(WOOD, 5, source)
	live_box.deposit(STONE, 2, source)
	await ctx.tree.physics_frame
	ctx.check(live_box.store.count_of(WOOD) == 5 and live_box.store.count_of(STONE) == 2,
		"contents setup: the live placed container holds 5 wood + 2 stone after two deposits (source drained accordingly)",
		"contents setup wrong (wood=%d, stone=%d)" % [live_box.store.count_of(WOOD), live_box.store.count_of(STONE)])

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# UNLOAD: the contents write-back must serialize the live store into the CONTAINER delta `state`.
	mover.global_position = WorldScale.chunk_origin(FOCUS_D + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var adds: Array = _container_entries(mgr.stored_data(FOCUS_D))
	var wrote_ok: bool = adds.size() == 1 and not _any_gone(adds) \
		and _entry_count(adds[0], WOOD) == 5 and _entry_count(adds[0], STONE) == 2
	ctx.check(wrote_ok,
		"persist-across-unload: the CONTAINER delta captured its live contents on unload (5 wood + 2 stone serialized as [item_path, count] pairs) -- contents rode the write-back into cold data, kept (not gone-flagged)",
		"contents write-back wrong (adds=%d, wood=%d, stone=%d)" % [adds.size(), (_entry_count(adds[0], WOOD) if adds.size() == 1 else -1), (_entry_count(adds[0], STONE) if adds.size() == 1 else -1)])

	# RELOAD: spawn()->apply_state() rebuilds the store from the delta contents.
	mover.global_position = WorldScale.chunk_origin(FOCUS_D) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rc: Node2D = mgr.active_container(FOCUS_D)
	var reloaded: Array = _containers_in(rc)
	var restore_ok: bool = reloaded.size() == 1 \
		and (reloaded[0] as StorageContainer).store.count_of(WOOD) == 5 \
		and (reloaded[0] as StorageContainer).store.count_of(STONE) == 2 \
		and world_pos.distance_to((reloaded[0] as StorageContainer).global_position) < 0.5
	ctx.check(restore_ok,
		"reload-round-trip: the container respawned at its pos holding its EXACT contents (5 wood + 2 stone restored, no loss/dupe) -- dormant delta contents became live stacks again",
		"contents did not round-trip (count=%d, wood=%d, stone=%d)" % [reloaded.size(), (int((reloaded[0] as StorageContainer).store.count_of(WOOD)) if reloaded.size() == 1 else -1), (int((reloaded[0] as StorageContainer).store.count_of(STONE)) if reloaded.size() == 1 else -1)])

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"zero-orphan-leak: orphan node count did not grow across deposit -> unload -> reload with contents (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"orphan nodes leaked across the contents round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	mgr.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## Leg F (Part 2.2 TWO CONTAINERS in ONE chunk): two placed containers with DISTINCT contents at DISTINCT positions
## in the SAME chunk EACH round-trip their OWN contents. The unload write-back matches each live box to its OWN
## CONTAINER entry by local_pos -- this proves that match holds with MORE THAN ONE box present (a position-swap /
## last-writer-wins bug would surface HERE, not in the single-box Leg E), valuable before Phase 3. Hand-driven
## ChunkManager (load_radius 1 -> one hop unloads), zero-orphan.
func _leg_two_containers(ctx: TestContext) -> void:
	var WOOD: ItemData = load("res://data/wood.tres")
	var STONE: ItemData = load("res://data/stone.tres")
	var mgr: ChunkManager = ChunkManager.new()
	mgr.load_radius = 1
	mgr.world_seed = SEED
	ctx.tree.root.add_child(mgr)
	var mover: Node2D = Node2D.new()
	ctx.tree.root.add_child(mover)
	mgr.target = mover

	mover.global_position = WorldScale.chunk_origin(FOCUS_F) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var container: Node2D = mgr.active_container(FOCUS_F)

	# Place TWO live containers WHILE ACTIVE at two distinct local positions + register each (empty) addition.
	var pos1: Vector2 = WorldScale.chunk_origin(FOCUS_F) + PLACE_LOCAL_F1
	var pos2: Vector2 = WorldScale.chunk_origin(FOCUS_F) + PLACE_LOCAL_F2
	var box1: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	container.add_child(box1)
	box1.global_position = pos1
	mgr.register_placement(pos1, box1.placement_kind(), box1.capture_state())
	var box2: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	container.add_child(box2)
	box2.global_position = pos2
	mgr.register_placement(pos2, box2.placement_kind(), box2.capture_state())

	# DISTINCT contents per box, added AFTER placement (only on the live nodes, not yet in the recorded delta).
	var src: Inventory = Inventory.new()
	src.add_item(WOOD, 9)
	src.add_item(STONE, 9)
	box1.deposit(WOOD, 6, src)   # box1 @ pos1 -> 6 wood only
	box2.deposit(STONE, 4, src)  # box2 @ pos2 -> 4 stone only
	await ctx.tree.physics_frame
	ctx.check(box1.store.count_of(WOOD) == 6 and box1.store.count_of(STONE) == 0
			and box2.store.count_of(STONE) == 4 and box2.store.count_of(WOOD) == 0,
		"two-container setup: box@pos1 holds 6 wood ONLY, box@pos2 holds 4 stone ONLY (distinct contents at distinct positions)",
		"two-container setup wrong (b1_wood=%d, b1_stone=%d, b2_stone=%d, b2_wood=%d)" % [box1.store.count_of(WOOD), box1.store.count_of(STONE), box2.store.count_of(STONE), box2.store.count_of(WOOD)])

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# UNLOAD: the write-back must serialize EACH live store into ITS OWN CONTAINER entry (matched by local_pos).
	mover.global_position = WorldScale.chunk_origin(FOCUS_F + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	# RELOAD: spawn()->apply_state() rebuilds BOTH stores from their own delta contents.
	mover.global_position = WorldScale.chunk_origin(FOCUS_F) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rc: Node2D = mgr.active_container(FOCUS_F)
	var r1: StorageContainer = _container_at(rc, pos1)
	var r2: StorageContainer = _container_at(rc, pos2)
	var each_ok: bool = _containers_in(rc).size() == 2 and r1 != null and r2 != null \
		and r1.store.count_of(WOOD) == 6 and r1.store.count_of(STONE) == 0 \
		and r2.store.count_of(STONE) == 4 and r2.store.count_of(WOOD) == 0
	ctx.check(each_ok,
		"two-container round-trip: EACH container restored its OWN contents BY POSITION (box@pos1 = 6 wood, box@pos2 = 4 stone; no mixup, no cross-contamination, no loss) -- the local_pos write-back match holds with 2 boxes in one chunk",
		"two-container contents mismatched on reload (count=%d, p1=%s, p2=%s)" % [_containers_in(rc).size(), (str(r1.store.count_of(WOOD)) + "w/" + str(r1.store.count_of(STONE)) + "s" if r1 != null else "nil"), (str(r2.store.count_of(WOOD)) + "w/" + str(r2.store.count_of(STONE)) + "s" if r2 != null else "nil")])

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"zero-orphan-leak: orphan node count did not grow across the two-container round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"orphan nodes leaked across the two-container round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	mgr.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## Leg G (Part 2.2 DEFENSIVE load-failure): apply_state carrying an item path that does NOT resolve to an ItemData
## is SKIPPED by the `if item != null` guard (load()...as ItemData yields null -- the same null a renamed/removed
## resource produces) with NO crash, and the OTHER valid contents still restore. A non-ItemData path (a real scene)
## is used instead of a truly missing one so the reload exercises the identical null-guard WITHOUT the engine
## logging a load-failure ERROR line into the smoke output.
func _leg_bad_path_skipped(ctx: TestContext) -> void:
	var WOOD: ItemData = load("res://data/wood.tres")
	var box: StorageContainer = StorageContainer.new()
	ctx.tree.root.add_child(box)
	# One path that resolves to a NON-ItemData resource (dropped by the null-guard) alongside one valid wood entry.
	box.apply_state({"contents": [
		["res://world/container.tscn", 3],
		[WOOD.resource_path, 2],
	]})
	await ctx.tree.physics_frame
	ctx.check(box.store.count_of(WOOD) == 2,
		"load-failure SKIPPED: apply_state drops a path that is not an ItemData (no crash) and still restores the valid wood x2 -- a missing/renamed item resource never takes down the whole reload",
		"bad-path apply_state did not skip cleanly (wood=%d)" % box.store.count_of(WOOD))
	box.queue_free()
	await ctx.tree.physics_frame


## The live StorageContainer under `container` whose global_position matches `world_pos` (within 0.5 px), or null.
## Lets Leg F assert each reloaded box restored its OWN contents BY POSITION (a placed container never moves, so
## position is a stable key -- the same key the unload write-back matches on).
func _container_at(container: Node2D, world_pos: Vector2) -> StorageContainer:
	for box in _containers_in(container):
		if world_pos.distance_to((box as StorageContainer).global_position) < 0.5:
			return box as StorageContainer
	return null


## Sum the count of `item` (matched by resource_path) across a CONTAINER entry's serialized `contents` pairs --
## the read-side of container.gd's [item_path, count] serialization, letting Leg E assert the delta captured the
## exact contents. 0 if the entry has no contents for that item.
func _entry_count(entry: Dictionary, item: ItemData) -> int:
	var total: int = 0
	var contents: Array = (entry["state"] as Dictionary).get("contents", [])
	for pair in contents:
		if String(pair[0]) == item.resource_path:
			total += int(pair[1])
	return total


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
