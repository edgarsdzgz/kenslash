class_name TestPlacementPersist extends RefCounted
## EPIC 2 Part 1.2 -- PERSISTENCE of placed objects (plan-epic2-parts.md Phase 1). A placed crafting Station
## must survive chunk UNLOAD/RELOAD via the streaming delta model: it is recorded as an ADDITION delta
## (Kind.STATION) keyed to the owning chunk coord -- the mirror of the DROP delta, but PUSHED by the build
## path (ChunkManager.register_placement) rather than swept on unload. On reload spawn() re-creates it from
## the delta at the SAME position + tag; the generator baseline is reproduced IDENTICALLY (the addition is an
## explicit delta, never an rng draw, so no per-Kind count shifts), with no orphan and no double-spawn.
##
## Two legs, both self-contained + at REMOTE coords clear of every other module's content:
##   A (manager-level, hand-driven ChunkManager, mirrors the C3b / drop-persist idiom): place a live Station
##     as chunk content AND register the addition; hop away (unload -> capture) then back (reload -> spawn);
##     assert the Station is back at the SAME pos + tag, EXACTLY one (no double, no loss), the generator's
##     existing-kind counts are UNCHANGED, zero-orphan holds, and a DIFFERENT chunk carries no placement.
##   B (streamed-world integration): the real streaming_world.place_station flow -- Builder deducts the build
##     cost + spawns under the owning chunk's container, and register_placement records the delta; a short
##     placement refused for want of materials records NO delta and consumes NOTHING (atomic).
## Registered in tests/smoke_slash.gd after TestBuilder (Part 1.1).

const STATION_SCENE: PackedScene = preload("res://world/station.tscn")

## Remote focus chunks, far from every other self-contained module (builder 120000, drop 9000, boulder
## 90000, ...), so no placement wanders into another module's scan and the two legs never co-activate.
const FOCUS_A: Vector2i = Vector2i(7000, 7000)
const FOCUS_B: Vector2i = Vector2i(8000, -8000)
## A DISTINCTIVE tag (not the station.tscn default &"forge"), so a reloaded station reading it proves the
## spawn path re-applied the ADDITION's stored tag -- a coincidental scene default could not pass.
const TAG_A: StringName = &"anvil"
## Where in the chunk the Leg A station is placed (arbitrary, distinct from origin), so the reloaded station's
## world position round-trips through the STATION entry's local_pos.
const PLACE_LOCAL: Vector2 = Vector2(120.0, 90.0)
const SEED: int = 7


func run(ctx: TestContext) -> void:
	print("[placement-persist] --- Epic 2 Part 1.2: placed stations survive unload/reload as ADDITION deltas ---")
	await _leg_manager(ctx)
	await _leg_streamed_world(ctx)


## Leg A: the persistence core on a hand-driven ChunkManager (load_radius 1 -> a 3x3 = 9 active set, so one
## short hop moves the focus chunk out of range and back).
func _leg_manager(ctx: TestContext) -> void:
	var mgr: ChunkManager = ChunkManager.new()
	mgr.load_radius = 1
	mgr.world_seed = SEED
	ctx.tree.root.add_child(mgr)
	var mover: Node2D = Node2D.new()
	ctx.tree.root.add_child(mover)
	mgr.target = mover

	# The DETERMINISM ORACLE: the generator's per-Kind baseline for the focus chunk, captured BEFORE any
	# placement touches the store. Every assertion below that "the addition did not shift the baseline"
	# compares against THIS.
	var oracle: Dictionary = _gen_counts(ChunkGenerator.generate(FOCUS_A, SEED))

	mover.global_position = WorldScale.chunk_origin(FOCUS_A) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var container: Node2D = mgr.active_container(FOCUS_A)
	var live_before: Dictionary = _live_counts(container)
	var baseline_ok: bool = container != null and _stations_in(container).size() == 0 and _counts_equal(live_before, oracle)
	ctx.check(baseline_ok,
		"Part 1.2 setup: focus chunk " + str(FOCUS_A) + " activated with its generator baseline (no station yet) -- live content matches the generator oracle",
		"focus chunk baseline did not match the generator (container=" + str(container != null) + ", stations=" + str(_stations_in(container).size()) + ")")

	# Place WHILE ACTIVE: a live Station child (the node Builder would spawn in the real flow) PLUS the
	# registered ADDITION delta. Registering after activation appends the entry BEYOND _content -- the very
	# case the ChunkManager STATION-skip must handle without gone-flagging it.
	var world_pos: Vector2 = WorldScale.chunk_origin(FOCUS_A) + PLACE_LOCAL
	var live_station: Station = STATION_SCENE.instantiate() as Station
	live_station.station_tag = TAG_A
	container.add_child(live_station)
	live_station.global_position = world_pos
	mgr.register_placement(world_pos, {"station_tag": String(TAG_A)})
	await ctx.tree.physics_frame

	var placed_now: Array = _stations_in(container)
	ctx.check(placed_now.size() == 1 and (placed_now[0] as Station).station_tag == TAG_A
			and world_pos.distance_to((placed_now[0] as Station).global_position) < 0.5,
		"place-while-active: exactly ONE live Station is present at the target with tag " + str(TAG_A) + " (the build-path node)",
		"live placement wrong (stations=" + str(placed_now.size()) + ")")

	var stored: ChunkData = mgr.stored_data(FOCUS_A)
	var adds: Array = _station_entries(stored)
	ctx.check(adds.size() == 1 and String((adds[0]["state"] as Dictionary).get("station_tag", "")) == String(TAG_A) and stored != null and stored.dirty,
		"the placement is recorded as ONE Kind.STATION ADDITION delta on the owning chunk (tag " + str(TAG_A) + ") and the chunk is now dirty -- a delta chunk",
		"placement was not recorded as a STATION addition (adds=" + str(adds.size()) + ")")

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# UNLOAD: hop away so FOCUS_A leaves the 3x3 set (capture write-back). The STATION addition must be KEPT
	# (skipped by the paired loop), never gone-flagged, so it survives as cold data.
	mover.global_position = WorldScale.chunk_origin(FOCUS_A + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var kept: Array = _station_entries(mgr.stored_data(FOCUS_A))
	ctx.check(kept.size() == 1 and not _any_gone(kept),
		"persist-across-unload: the unloaded chunk still holds its ONE STATION addition (kept, NOT gone-flagged) -- the placement became cheap delta data",
		"placement addition was lost or gone-flagged on unload (kept=" + str(kept.size()) + ")")

	# RELOAD: hop back so FOCUS_A reactivates and spawn() re-creates the station from the addition.
	mover.global_position = WorldScale.chunk_origin(FOCUS_A) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rc: Node2D = mgr.active_container(FOCUS_A)
	var reloaded: Array = _stations_in(rc)
	var reload_ok: bool = reloaded.size() == 1 \
		and (reloaded[0] as Station).station_tag == TAG_A \
		and world_pos.distance_to((reloaded[0] as Station).global_position) < 0.5
	ctx.check(reload_ok,
		"reload-round-trip: EXACTLY one Station respawned at the SAME position with the SAME tag " + str(TAG_A) + " (no double-spawn, no loss) -- dormant delta became a node again",
		"station did not round-trip correctly (count=" + str(reloaded.size()) + ")")

	# DETERMINISM: the addition did NOT perturb the generator baseline -- the reloaded chunk's live
	# existing-kind content matches the oracle exactly (station excluded), and the generator regenerates
	# byte-identically (untouched).
	var live_after: Dictionary = _live_counts(rc)
	ctx.check(_counts_equal(live_after, oracle) and _counts_equal(live_after, live_before),
		"determinism intact: the reloaded baseline (TREE/MINERAL/ENEMY/BUSH/PEBBLE/BOULDER) is UNCHANGED by the addition -- matches the generator oracle and the pre-placement counts",
		"the addition shifted the generator baseline (after=" + str(live_after) + " oracle=" + str(oracle) + ")")
	ctx.check(_counts_equal(_gen_counts(ChunkGenerator.generate(FOCUS_A, SEED)), oracle),
		"generator untouched: regenerating " + str(FOCUS_A) + " yields per-Kind counts byte-identical to the oracle (placements are explicit deltas, never rng draws)",
		"generator per-Kind counts changed (regen != oracle)")

	# ZERO-ORPHAN across the round trip.
	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"zero-orphan-leak: orphan node count did not grow across place -> unload -> reload (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"orphan nodes leaked across the placement round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	# ISOLATION: a placement in FOCUS_A does NOT appear in a DIFFERENT (also-active) chunk.
	var neighbor: Vector2i = FOCUS_A + Vector2i(1, 0)
	var nc: Node2D = mgr.active_container(neighbor)
	ctx.check(nc != null and _stations_in(nc).size() == 0 and _station_entries(mgr.stored_data(neighbor)).size() == 0,
		"chunk isolation: the neighboring chunk " + str(neighbor) + " carries NO station -- a placement belongs ONLY to the chunk that owns its world position",
		"a placement leaked into a different chunk (" + str(neighbor) + ")")

	mgr.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## Leg B: the real streamed-world flow -- streaming_world.place_station wires Builder (build cost) to
## register_placement (persistence), and refuses atomically when the cost is short.
func _leg_streamed_world(ctx: TestContext) -> void:
	var STONE: ItemData = load("res://data/stone.tres")
	var STICK: ItemData = load("res://data/stick.tres")

	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	var sw: Node2D = sw_scene.instantiate()
	ctx.tree.root.add_child(sw)
	var sw_player: Node2D = sw.get_node("Player") as Node2D
	# Suppress the origin pickup magnet before the first frame (established streaming-test hygiene).
	sw_player.set("pickup_radius", 0.0)
	var sw_mgr: ChunkManager = sw.get_node("ChunkManager") as ChunkManager

	# Wander the player to a remote chunk so its neighborhood streams in (place_station can only build into
	# a LIVE chunk -- the player's own chunk is always active).
	sw_player.global_position = WorldScale.chunk_origin(FOCUS_B) + Vector2(40.0, 40.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	# Place a station beside the player (same chunk) with a sufficient build cost (stone x3 + stick x2).
	var wpos: Vector2 = WorldScale.chunk_origin(FOCUS_B) + Vector2(200.0, 150.0)
	var inv: Inventory = Inventory.new()
	inv.add_item(STONE, 3)
	inv.add_item(STICK, 2)
	var placed: Node = sw.call("place_station", STATION_SCENE, wpos, inv)
	await ctx.tree.physics_frame
	var station: Station = placed as Station
	var owner_container: Node2D = sw_mgr.active_container(FOCUS_B)
	ctx.check(station != null and inv.count_of(STONE) == 0 and inv.count_of(STICK) == 0
			and station.is_in_group(Station.GROUP)
			and wpos.distance_to(station.global_position) < 0.5
			and station.get_parent() == owner_container,
		"place_station (real flow): Builder consumed the EXACT build cost (stone 3 -> 0, stick 2 -> 0) and spawned the Station under its OWNING chunk container at the target -- freed WITH the chunk on unload",
		"place_station did not build/parent correctly (station=%s, stone=%d, stick=%d)" % [str(station != null), inv.count_of(STONE), inv.count_of(STICK)])

	var recorded: Array = _station_entries(sw_mgr.stored_data(FOCUS_B))
	ctx.check(recorded.size() == 1 and String((recorded[0]["state"] as Dictionary).get("station_tag", "")) == "forge",
		"place_station recorded the placement as a STATION delta on the owning chunk (tag \"forge\") -- the wiring pushes the addition into the streaming persistence",
		"place_station did not record a placement delta (recorded=" + str(recorded.size()) + ")")

	# ATOMIC REFUSAL: an insufficient build cost places nothing, records NO delta, consumes nothing.
	var before: int = _station_entries(sw_mgr.stored_data(FOCUS_B)).size()
	var inv_short: Inventory = Inventory.new()
	inv_short.add_item(STONE, 1)  # short: no sticks, and stone 1 < 3
	var refused: Node = sw.call("place_station", STATION_SCENE, wpos + Vector2(80.0, 0.0), inv_short)
	await ctx.tree.physics_frame
	var after: int = _station_entries(sw_mgr.stored_data(FOCUS_B)).size()
	ctx.check(refused == null and after == before and inv_short.count_of(STONE) == 1,
		"place_station refusal is ATOMIC: an unaffordable placement returns null, records NO new addition delta, and consumes NOTHING (stone stays 1)",
		"refused placement was not atomic (refused=%s, before=%d, after=%d, stone=%d)" % [str(refused != null), before, after, inv_short.count_of(STONE)])

	sw.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## The live Station instances directly under a chunk container (empty if the container is null).
func _stations_in(container: Node2D) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is Station:
			out.append(child)
	return out


## The Kind.STATION ADDITION entries of a stored ChunkData (empty if the data is null).
func _station_entries(cd: ChunkData) -> Array:
	var out: Array = []
	if cd == null:
		return out
	for e in cd.entries:
		if int(e["type"]) == ChunkData.Kind.STATION:
			out.append(e)
	return out


## True iff any of the given entries is flagged `gone` (a STATION should NEVER be -- it is a permanent addition).
func _any_gone(entries: Array) -> bool:
	for e in entries:
		if bool((e["state"] as Dictionary).get("gone", false)):
			return true
	return false


## Per-Kind counts of a generated ChunkData's existing (non-STATION) baseline Kinds -- the determinism oracle.
func _gen_counts(cd: ChunkData) -> Dictionary:
	var c: Dictionary = {"tree": 0, "rock": 0, "enemy": 0, "bush": 0, "pebble": 0, "boulder": 0}
	for e in cd.entries:
		match int(e["type"]):
			ChunkData.Kind.TREE: c["tree"] += 1
			ChunkData.Kind.MINERAL: c["rock"] += 1
			ChunkData.Kind.ENEMY: c["enemy"] += 1
			ChunkData.Kind.BUSH: c["bush"] += 1
			ChunkData.Kind.PEBBLE: c["pebble"] += 1
			ChunkData.Kind.BOULDER: c["boulder"] += 1
	return c


## Per-Kind counts of the LIVE baseline content under a container -- Station EXCLUDED, so it is directly
## comparable to _gen_counts. Same class-order discipline as test_streaming (Rock/Boulder both extend
## StaticBody2D, so those explicit classes are tested before the bare-StaticBody2D Tree fallthrough).
func _live_counts(container: Node2D) -> Dictionary:
	var c: Dictionary = {"tree": 0, "rock": 0, "enemy": 0, "bush": 0, "pebble": 0, "boulder": 0}
	if container == null:
		return c
	for child in container.get_children():
		if child is Station:
			continue  # additions are not baseline content
		if child is Enemy:
			c["enemy"] += 1
		elif child is Rock:
			c["rock"] += 1
		elif child is Boulder:
			c["boulder"] += 1
		elif child is Bush:
			c["bush"] += 1
		elif child is Pebble:
			c["pebble"] += 1
		elif child is StaticBody2D:
			c["tree"] += 1
	return c


## Field-by-field equality of two per-Kind count Dictionaries (the six baseline Kinds).
func _counts_equal(a: Dictionary, b: Dictionary) -> bool:
	for k in ["tree", "rock", "enemy", "bush", "pebble", "boulder"]:
		if int(a.get(k, -1)) != int(b.get(k, -2)):
			return false
	return true

# Verified against: Godot 4.7.1 (2026-07-20)
