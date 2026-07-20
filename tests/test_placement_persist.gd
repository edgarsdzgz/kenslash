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
## Plus four REVIEW-COVERAGE legs (both reviewers flagged these as missing tests, not bugs -- the code is
## correct), each a self-contained hand-driven ChunkManager at a FRESH remote coord clear of every other leg:
##   C (FIX 1): a placed STATION and a GONE baseline entry (a mined-out rock) coexist in ONE chunk across a
##     round trip -- exercising the exact index-alignment the ChunkManager STATION-skip reasons about (a null
##     nodes[k] slot for the gone rock + an appended STATION beyond _content). Both deltas must survive.
##   D (FIX 2): TWO stations (distinct positions + tags) in ONE chunk round-trip -- no loss, no double-spawn.
##   E (FIX 3): a place->unload->reload round trip in a NEGATIVE-both-axes chunk (Leg A is all-positive) --
##     proves the floori / chunk_origin local-pos math round-trips across negatives.
##   F (FIX 4): a station's tag surviving TWO full unload/reload cycles -- proves the addition is stable cold
##     data, not consumed on the first reload.
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

## --- REVIEW-COVERAGE legs (FIX 1-4): fresh remote focus chunks, each far from FOCUS_A/B and from every
## other module, so no manager's 3x3 co-activates another's placement. Distinctive per-leg tags (none the
## station.tscn default &"forge") so a reloaded station reading its tag proves the ADDITION's stored tag was
## re-applied on spawn -- a coincidental default could not pass.
const FOCUS_C: Vector2i = Vector2i(12000, 12000)     # FIX 1: station + mined-out (GONE) rock coexist
const TAG_C: StringName = &"kiln"
const PLACE_LOCAL_C: Vector2 = Vector2(200.0, 260.0)
const FOCUS_D: Vector2i = Vector2i(13000, -13000)    # FIX 2: two stations in one chunk
const TAG_D1: StringName = &"loom"
const TAG_D2: StringName = &"smithy"
const PLACE_LOCAL_D1: Vector2 = Vector2(100.0, 100.0)
const PLACE_LOCAL_D2: Vector2 = Vector2(430.0, 350.0)
const FOCUS_E: Vector2i = Vector2i(-14000, -14000)   # FIX 3: negative-both-axes round trip
const TAG_E: StringName = &"crucible"
const PLACE_LOCAL_E: Vector2 = Vector2(150.0, 220.0)
const FOCUS_F: Vector2i = Vector2i(15000, 15000)     # FIX 4: tag survives two unload/reload cycles
const TAG_F: StringName = &"tannery"
const PLACE_LOCAL_F: Vector2 = Vector2(300.0, 180.0)


func run(ctx: TestContext) -> void:
	print("[placement-persist] --- Epic 2 Part 1.2: placed stations survive unload/reload as ADDITION deltas ---")
	await _leg_manager(ctx)
	await _leg_streamed_world(ctx)
	await _leg_gone_coexist(ctx)     # FIX 1
	await _leg_two_stations(ctx)     # FIX 2
	await _leg_negative_coord(ctx)   # FIX 3
	await _leg_multi_cycle(ctx)      # FIX 4


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
	mgr.register_placement(world_pos, ChunkData.Kind.STATION, {"station_tag": String(TAG_A)})
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


## FIX 1 -- a placed STATION and a GONE baseline entry (a mined-out rock) coexist in ONE chunk across a round
## trip. This is the most valuable coverage gap: it exercises the exact index-alignment the ChunkManager
## STATION-skip reasons about. The mined rock leaves a null nodes[k] slot the paired deactivate loop must
## gone-flag, WHILE the station -- registered AFTER activation -- is an entry appended BEYOND _content that the
## STATION `continue` must SKIP (not gone-flag). Both deltas must survive: the gone rock never respawns AND the
## station returns at its pos + tag. The mine seam is the SAME direct Material.wear the C3b streaming legs use.
func _leg_gone_coexist(ctx: TestContext) -> void:
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
	var container: Node2D = mgr.active_container(FOCUS_C)
	var rocks: Array = _rocks_in(container)
	var rocks_before: int = rocks.size()

	# Mine the FIRST rock OUT: drive its Material to 0 -> rock.gd._on_broke -> queue_free. After the deferred
	# free resolves, nodes[k] is an invalid slot, so the paired loop gone-flags that baseline MINERAL entry.
	if rocks_before >= 1:
		var doomed_mat: DurabilityComponent = (rocks[0] as Rock).get_node("Material") as DurabilityComponent
		doomed_mat.wear(doomed_mat.current_durability)
	await ctx.tree.physics_frame  # let the doomed rock's deferred queue_free resolve

	# Place a station WHILE ACTIVE (live node + registered addition) -- the addition appends BEYOND _content.
	var world_pos: Vector2 = WorldScale.chunk_origin(FOCUS_C) + PLACE_LOCAL_C
	var live_station: Station = STATION_SCENE.instantiate() as Station
	live_station.station_tag = TAG_C
	container.add_child(live_station)
	live_station.global_position = world_pos
	mgr.register_placement(world_pos, ChunkData.Kind.STATION, {"station_tag": String(TAG_C)})
	await ctx.tree.physics_frame

	ctx.check(container != null and rocks_before >= 1 and _stations_in(container).size() == 1,
		"FIX1 setup: chunk " + str(FOCUS_C) + " active with >= 1 rock; its first rock mined OUT and ONE station placed (live node + addition delta) -- a GONE baseline entry and an addition now share the chunk",
		"FIX1 setup wrong (rocks_before=" + str(rocks_before) + ", stations=" + str(_stations_in(container).size()) + ")")

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# UNLOAD: the paired loop must gone-flag the mined rock's MINERAL entry (null nodes[k]) AND skip the STATION
	# addition (index beyond nodes.size()) -- keeping it, never gone-flagging it.
	mover.global_position = WorldScale.chunk_origin(FOCUS_C + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var stored: ChunkData = mgr.stored_data(FOCUS_C)
	var kept_station: Array = _station_entries(stored)
	ctx.check(kept_station.size() == 1 and not _any_gone(kept_station) and _any_mineral_gone(stored),
		"FIX1 unload: the STATION addition is KEPT (not gone-flagged) AND the mined rock's MINERAL entry is flagged gone -- the index-alignment held (skip the appended station, gone-flag the null rock slot)",
		"FIX1 unload wrong (station kept=" + str(kept_station.size()) + " station-gone=" + str(_any_gone(kept_station)) + " mineral-gone=" + str(_any_mineral_gone(stored)) + ")")

	# RELOAD: spawn() re-creates the station from the addition; the gone rock is SKIPPED (never respawns).
	mover.global_position = WorldScale.chunk_origin(FOCUS_C) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rc: Node2D = mgr.active_container(FOCUS_C)
	var reloaded: Array = _stations_in(rc)
	var station_ok: bool = reloaded.size() == 1 \
		and (reloaded[0] as Station).station_tag == TAG_C \
		and world_pos.distance_to((reloaded[0] as Station).global_position) < 0.5
	var rock_ok: bool = _rocks_in(rc).size() == rocks_before - 1
	ctx.check(station_ok and rock_ok,
		"FIX1 reload: BOTH deltas survived -- exactly ONE station back at its pos + tag " + str(TAG_C) + " AND the mined rock stayed GONE (rocks " + str(rocks_before) + " -> " + str(_rocks_in(rc).size()) + ", not respawned)",
		"FIX1 reload wrong (stations=" + str(reloaded.size()) + " rocks=" + str(_rocks_in(rc).size()) + " expected rocks=" + str(rocks_before - 1) + ")")

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"FIX1 zero-orphan-leak: orphan node count did not grow across mine + place -> unload -> reload (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"FIX1 orphan nodes leaked (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	mgr.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## FIX 2 -- TWO stations (distinct positions AND distinct tags) placed in ONE chunk survive a round trip: both
## come back at their own position with their own tag, no loss, no double-spawn, no orphan/mixup. Driven via
## register_placement directly (so the two tags can differ), then reloaded from the two ADDITION entries.
func _leg_two_stations(ctx: TestContext) -> void:
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

	var pos1: Vector2 = WorldScale.chunk_origin(FOCUS_D) + PLACE_LOCAL_D1
	var pos2: Vector2 = WorldScale.chunk_origin(FOCUS_D) + PLACE_LOCAL_D2
	mgr.register_placement(pos1, ChunkData.Kind.STATION, {"station_tag": String(TAG_D1)})
	mgr.register_placement(pos2, ChunkData.Kind.STATION, {"station_tag": String(TAG_D2)})
	await ctx.tree.physics_frame

	var stored: ChunkData = mgr.stored_data(FOCUS_D)
	var adds: Array = _station_entries(stored)
	ctx.check(adds.size() == 2 and stored != null and stored.dirty,
		"FIX2 place: TWO distinct STATION additions recorded on chunk " + str(FOCUS_D) + " (a dirty delta chunk)",
		"FIX2 did not record two additions (adds=" + str(adds.size()) + ")")

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# UNLOAD -> RELOAD.
	mover.global_position = WorldScale.chunk_origin(FOCUS_D + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var kept: Array = _station_entries(mgr.stored_data(FOCUS_D))
	ctx.check(kept.size() == 2 and not _any_gone(kept),
		"FIX2 unload: BOTH STATION additions kept (neither gone-flagged) as cold data",
		"FIX2 lost/gone-flagged an addition on unload (kept=" + str(kept.size()) + ")")

	mover.global_position = WorldScale.chunk_origin(FOCUS_D) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rc: Node2D = mgr.active_container(FOCUS_D)
	var reloaded: Array = _stations_in(rc)
	var s1: Station = _station_at(reloaded, pos1)
	var s2: Station = _station_at(reloaded, pos2)
	var both_ok: bool = reloaded.size() == 2 \
		and s1 != null and s1.station_tag == TAG_D1 \
		and s2 != null and s2.station_tag == TAG_D2
	ctx.check(both_ok,
		"FIX2 reload: EXACTLY two stations respawned, each at its own position with its own tag (" + str(TAG_D1) + " + " + str(TAG_D2) + ") -- no loss, no double-spawn, no mixup",
		"FIX2 two-station round-trip wrong (count=" + str(reloaded.size()) + " s1=" + str(s1 != null) + " s2=" + str(s2 != null) + ")")

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"FIX2 zero-orphan-leak: orphan node count did not grow across the two-station round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"FIX2 orphan nodes leaked (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	mgr.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## FIX 3 -- a place->unload->reload round trip in a NEGATIVE-both-axes chunk (Leg A's only round trip is
## all-positive). Proves the floori / chunk_origin local-pos math round-trips across negatives: the station's
## stored local_pos = world_pos - chunk_origin(coord) (a positive [0, CHUNK_PX) offset from a NEGATIVE origin)
## must re-produce the exact world_pos on reload.
func _leg_negative_coord(ctx: TestContext) -> void:
	var mgr: ChunkManager = ChunkManager.new()
	mgr.load_radius = 1
	mgr.world_seed = SEED
	ctx.tree.root.add_child(mgr)
	var mover: Node2D = Node2D.new()
	ctx.tree.root.add_child(mover)
	mgr.target = mover

	mover.global_position = WorldScale.chunk_origin(FOCUS_E) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	var world_pos: Vector2 = WorldScale.chunk_origin(FOCUS_E) + PLACE_LOCAL_E
	mgr.register_placement(world_pos, ChunkData.Kind.STATION, {"station_tag": String(TAG_E)})
	await ctx.tree.physics_frame
	var stored: ChunkData = mgr.stored_data(FOCUS_E)
	ctx.check(WorldScale.world_to_chunk(world_pos) == FOCUS_E and _station_entries(stored).size() == 1,
		"FIX3 place: a station at a NEGATIVE-both-axes world pos " + str(world_pos) + " is owned by chunk " + str(FOCUS_E) + " and recorded as ONE addition (floori chunk math resolves negatives)",
		"FIX3 place wrong (owning=" + str(WorldScale.world_to_chunk(world_pos)) + " adds=" + str(_station_entries(stored).size()) + ")")

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# UNLOAD -> RELOAD.
	mover.global_position = WorldScale.chunk_origin(FOCUS_E + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var kept: Array = _station_entries(mgr.stored_data(FOCUS_E))
	ctx.check(kept.size() == 1 and not _any_gone(kept),
		"FIX3 unload: the negative-chunk STATION addition is kept (not gone-flagged) as cold data",
		"FIX3 lost/gone-flagged the addition on unload (kept=" + str(kept.size()) + ")")

	mover.global_position = WorldScale.chunk_origin(FOCUS_E) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rc: Node2D = mgr.active_container(FOCUS_E)
	var reloaded: Array = _stations_in(rc)
	var ok: bool = reloaded.size() == 1 \
		and (reloaded[0] as Station).station_tag == TAG_E \
		and world_pos.distance_to((reloaded[0] as Station).global_position) < 0.5
	ctx.check(ok,
		"FIX3 reload: the station restored at the SAME negative world pos " + str(world_pos) + " with tag " + str(TAG_E) + " -- floori/chunk_origin local-pos math round-trips across negatives",
		"FIX3 negative round-trip wrong (count=" + str(reloaded.size()) + " pos_ok/tag: " + str(ok) + ")")

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"FIX3 zero-orphan-leak: orphan node count did not grow across the negative-coord round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"FIX3 orphan nodes leaked (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	mgr.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## FIX 4 -- a station's tag survives TWO full unload/reload cycles (hop away/back twice). Proves the addition
## is STABLE cold data, not consumed on the first reload. It also exercises the STATION-skip in BOTH index
## regimes: cycle 1's unload sees the entry appended BEYOND _content (no live node yet); cycle 1's reload
## spawns a live node so cycle 2's unload sees the entry IN _content (the paired-loop `continue` path).
func _leg_multi_cycle(ctx: TestContext) -> void:
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

	var world_pos: Vector2 = WorldScale.chunk_origin(FOCUS_F) + PLACE_LOCAL_F
	mgr.register_placement(world_pos, ChunkData.Kind.STATION, {"station_tag": String(TAG_F)})
	await ctx.tree.physics_frame
	ctx.check(_station_entries(mgr.stored_data(FOCUS_F)).size() == 1 and mgr.stored_data(FOCUS_F).dirty,
		"FIX4 place: ONE STATION addition recorded on chunk " + str(FOCUS_F) + " (a dirty delta chunk)",
		"FIX4 did not record the addition (adds=" + str(_station_entries(mgr.stored_data(FOCUS_F)).size()) + ")")

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var away: Vector2 = WorldScale.chunk_origin(FOCUS_F + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	var home: Vector2 = WorldScale.chunk_origin(FOCUS_F) + Vector2(20.0, 20.0)

	# --- CYCLE 1 (entry appended BEYOND _content on this unload) ---
	mover.global_position = away
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(_station_entries(mgr.stored_data(FOCUS_F)).size() == 1 and not _any_gone(_station_entries(mgr.stored_data(FOCUS_F))),
		"FIX4 cycle 1 unload: the addition is kept (not gone-flagged) as cold data",
		"FIX4 cycle 1 lost/gone-flagged the addition (kept=" + str(_station_entries(mgr.stored_data(FOCUS_F)).size()) + ")")
	mover.global_position = home
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var r1: Array = _stations_in(mgr.active_container(FOCUS_F))
	ctx.check(r1.size() == 1 and (r1[0] as Station).station_tag == TAG_F and world_pos.distance_to((r1[0] as Station).global_position) < 0.5,
		"FIX4 cycle 1 reload: the station respawned once at its pos with tag " + str(TAG_F) + " (survived cycle 1)",
		"FIX4 cycle 1 reload wrong (count=" + str(r1.size()) + ")")

	# --- CYCLE 2 (entry now IN _content -- the paired-loop STATION `continue` path) ---
	mover.global_position = away
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(_station_entries(mgr.stored_data(FOCUS_F)).size() == 1 and not _any_gone(_station_entries(mgr.stored_data(FOCUS_F))),
		"FIX4 cycle 2 unload: the addition is STILL kept (not consumed by cycle 1, not gone-flagged now that it sits in _content)",
		"FIX4 cycle 2 lost/gone-flagged the addition (kept=" + str(_station_entries(mgr.stored_data(FOCUS_F)).size()) + ")")
	mover.global_position = home
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var r2: Array = _stations_in(mgr.active_container(FOCUS_F))
	ctx.check(r2.size() == 1 and (r2[0] as Station).station_tag == TAG_F and world_pos.distance_to((r2[0] as Station).global_position) < 0.5,
		"FIX4 cycle 2 reload: the station + tag " + str(TAG_F) + " survived a SECOND full unload/reload cycle -- the delta is stable cold data, not consumed on first reload",
		"FIX4 cycle 2 reload wrong (count=" + str(r2.size()) + ")")

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"FIX4 zero-orphan-leak: orphan node count did not grow across BOTH unload/reload cycles (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"FIX4 orphan nodes leaked across the two cycles (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	mgr.queue_free()
	mover.queue_free()
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


## The live Rock instances directly under a chunk container (empty if the container is null). Used by FIX 1
## to drive the mine seam and to count that a mined-out rock did NOT respawn after reload.
func _rocks_in(container: Node2D) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is Rock:
			out.append(child)
	return out


## True iff the stored ChunkData has a MINERAL entry flagged `gone` (the mined-out-rock write-back result).
## FIX 1's proof that the paired deactivate loop gone-flagged the null nodes[k] slot -- distinct from the
## STATION addition it must instead keep.
func _any_mineral_gone(cd: ChunkData) -> bool:
	if cd == null:
		return false
	for e in cd.entries:
		if int(e["type"]) == ChunkData.Kind.MINERAL and bool((e["state"] as Dictionary).get("gone", false)):
			return true
	return false


## The Station in `stations` whose world position matches `pos` (within 0.5 px), or null. Lets FIX 2 pair
## each reloaded station back to the position it was placed at -- proving no mixup between two placements.
func _station_at(stations: Array, pos: Vector2) -> Station:
	for s in stations:
		if pos.distance_to((s as Station).global_position) < 0.5:
			return s as Station
	return null


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
