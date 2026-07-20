class_name TestStationLeveling extends RefCounted
## EPIC 2 Phase 4 Part 4.1 -- "Windrose" PROXIMITY STATION LEVELING (plan-epic2-parts.md Phase 4). A crafting
## Station carries a LEVEL derived from the COUNT of placeable ADD-ONS (world/station_addon.gd) within its reach,
## capped at Station.MAX_ADDON_LEVELS: level = 1 + min(add-ons in reach, MAX_ADDON_LEVELS). The add-on is the THIRD
## placeable, riding the SAME kind-agnostic build + streaming-delta path a Station / Container does (it differs
## only in placement_kind() = Kind.ADDON and its own build cost, wood x2). This part is ONLY the add-on entity,
## the level() derivation + cap, and add-on persistence; wiring the level into a recipe TIER gate is Part 4.2.
##
## THREE self-contained legs, each at REMOTE coords clear of every other module + of each other (so no add-on or
## station wanders into another scan), mirroring the isolation style of tests/test_station.gd + test_container.gd:
##   A (level derivation + cap): a Station with NO add-on is level 1; ONE add-on in reach -> 2; TWO -> 3; a THIRD
##     in reach does NOT raise past the cap (still 3); an add-on FAR from the station does not count. Pure logic on
##     a holder (no streaming), the deterministic distance scan Station.addons_in_range / level() drive.
##   B (build cost, Builder-direct -- mirrors test_builder/test_container): an add-on PLACES for its authored build
##     cost (wood x2) ATOMICALLY -- exact consume, joins the "station_addon" group; a short cost REFUSES and
##     consumes nothing. Proves Builder is kind-agnostic (places an add-on, never `as Station`).
##   C (persistence + determinism): a Station and an add-on placed near it in a LIVE chunk both round-trip across
##     unload/reload as ADDITION deltas -- kept (NOT gone-flagged) by the generalized deactivate-skip, respawned at
##     their SAME positions on reload, and the station's level() RECOMPUTES to the same value (2) from the add-on
##     that persisted (nothing level-specific stored). Zero-orphan; the generator baseline regenerates byte-
##     identically (the additions are explicit deltas, never rng draws -- determinism sacred).
## Registered in tests/smoke_slash.gd after TestCraftFromStorage (Phase 3), before the environment/enemy legs.

const STATION_SCENE: PackedScene = preload("res://world/station.tscn")
const ADDON_SCENE: PackedScene = preload("res://world/station_addon.tscn")

## Remote regions clear of every other self-contained module (station -90000, container 140000/21000-24000,
## placement-persist 7000-15000, builder 120000, boulder 90000, pebble -60000, ...) AND of each other, so no
## add-on/station leaks into another scan.
const HOME_A: Vector2 = Vector2(-150000.0, -150000.0)   # Leg A: level derivation (holder, coord irrelevant)
const HOME_B: Vector2 = Vector2(-160000.0, 160000.0)    # Leg B: Builder-direct build (holder, coord irrelevant)
const FOCUS_C: Vector2i = Vector2i(31000, 31000)        # Leg C: station + add-on round trip
const STATION_LOCAL_C: Vector2 = Vector2(200.0, 240.0)
const ADDON_LOCAL_C: Vector2 = Vector2(230.0, 240.0)    # 30 px from the station -- inside DEFAULT_REACH (80 px)
const SEED: int = 7


func run(ctx: TestContext) -> void:
	print("[station-leveling] --- Epic 2 Part 4.1: add-ons raise a station's level (capped), persist as deltas ---")
	await _leg_level_derivation(ctx)
	await _leg_build_cost(ctx)
	await _leg_persist(ctx)


## Leg A: the level() derivation + the cap, on a plain holder (no streaming). A Station is level 1 with no add-ons;
## each add-on WITHIN reach raises it by 1 up to MAX_ADDON_LEVELS; a further in-reach add-on is capped; a FAR add-on
## never counts. All additions/removals are reflected immediately (level() re-scans the group every call).
func _leg_level_derivation(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	var st: Station = _make_station(holder, HOME_A, &"forge")
	await ctx.tree.physics_frame
	ctx.check(st.level() == 1 and Station.addons_in_range(st.global_position, Station.DEFAULT_REACH) == 0,
		"a station with NO add-ons in reach is LEVEL 1 (base) -- addons_in_range 0",
		"bare station was not level 1 (level=%d, addons=%d)" % [st.level(), Station.addons_in_range(st.global_position, Station.DEFAULT_REACH)])

	# ONE add-on 30 px away (inside the 80 px DEFAULT_REACH) -> level 2.
	_make_addon(holder, HOME_A + Vector2(30.0, 0.0))
	await ctx.tree.physics_frame
	ctx.check(st.level() == 2 and Station.addons_in_range(st.global_position, Station.DEFAULT_REACH) == 1,
		"placing ONE add-on within reach raises the station to LEVEL 2 (1 + 1 add-on)",
		"one add-on did not raise level to 2 (level=%d, addons=%d)" % [st.level(), Station.addons_in_range(st.global_position, Station.DEFAULT_REACH)])

	# A SECOND in-reach add-on -> level 3 (= 1 + MAX_ADDON_LEVELS at cap 2).
	_make_addon(holder, HOME_A + Vector2(0.0, 30.0))
	await ctx.tree.physics_frame
	ctx.check(st.level() == 3 and st.level() == 1 + Station.MAX_ADDON_LEVELS,
		"placing a SECOND add-on within reach raises the station to LEVEL 3 (1 + MAX_ADDON_LEVELS)",
		"two add-ons did not raise level to 3 (level=%d, max=%d)" % [st.level(), Station.MAX_ADDON_LEVELS])

	# A THIRD in-reach add-on: the RAW count rises to 3 but level() CAPS at 1 + MAX_ADDON_LEVELS (still 3).
	_make_addon(holder, HOME_A + Vector2(-30.0, 0.0))
	await ctx.tree.physics_frame
	ctx.check(Station.addons_in_range(st.global_position, Station.DEFAULT_REACH) == 3 and st.level() == 3,
		"the CAP holds: a THIRD add-on in reach (raw count 3) does NOT raise the level past 3 -- level() clamps to 1 + MAX_ADDON_LEVELS",
		"the level cap did not hold (addons=%d, level=%d)" % [Station.addons_in_range(st.global_position, Station.DEFAULT_REACH), st.level()])

	# A FAR add-on (400 px, well outside the 80 px reach): counts for NOTHING -- level unchanged.
	_make_addon(holder, HOME_A + Vector2(400.0, 0.0))
	await ctx.tree.physics_frame
	ctx.check(Station.addons_in_range(st.global_position, Station.DEFAULT_REACH) == 3 and st.level() == 3,
		"an add-on FAR from the station (400 px, outside DEFAULT_REACH) is NOT counted -- level stays 3 (deterministic <= radius scan)",
		"a far add-on wrongly counted toward the level (addons=%d, level=%d)" % [Station.addons_in_range(st.global_position, Station.DEFAULT_REACH), st.level()])

	holder.queue_free()
	await ctx.tree.physics_frame


## Leg B: Builder places an add-on for its authored build cost (wood x2) ATOMICALLY, joining the "station_addon"
## group; a short cost refuses and consumes nothing. Mirrors test_builder/test_container's shape -- proves the
## add-on rides the kind-agnostic Builder path (typed as Placeable, never `as Station`).
func _leg_build_cost(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var builder: Builder = Builder.new()
	var WOOD: ItemData = load("res://data/wood.tres")

	# SUFFICIENT: wood 5 >= cost 2. can_place clears; place spawns at HOME_B under the holder, consuming EXACTLY 2.
	var inv: Inventory = Inventory.new()
	inv.add_item(WOOD, 5)
	var can_ok: bool = builder.can_place(ADDON_SCENE, inv)
	var placed: Node = builder.place(ADDON_SCENE, HOME_B, inv, holder)
	await ctx.tree.physics_frame
	var addon: StationAddon = placed as StationAddon
	ctx.check(can_ok and addon != null and addon.is_in_group(StationAddon.GROUP)
			and addon.global_position == HOME_B and inv.count_of(WOOD) == 3
			and addon.placement_kind() == ChunkData.Kind.ADDON,
		"place SPAWNS a StationAddon at the target in the \"station_addon\" group, consumes the EXACT build cost (wood 5 -> 3 surplus), and reports placement_kind() ADDON; can_place agreed (true)",
		"add-on did not place/charge/kind correctly (can=%s, addon=%s, grouped=%s, pos=%s, wood=%d)" % [str(can_ok), str(addon != null), str(addon != null and addon.is_in_group(StationAddon.GROUP)), str(addon.global_position if addon != null else Vector2.ZERO), inv.count_of(WOOD)])

	# INSUFFICIENT: wood 1 < 2. can_place false, place null, wood untouched (no partial consume), no new add-on.
	var before_count: int = _addons_under(holder).size()
	var inv_short: Inventory = Inventory.new()
	inv_short.add_item(WOOD, 1)
	var short_can: bool = builder.can_place(ADDON_SCENE, inv_short)
	var short_placed: Node = builder.place(ADDON_SCENE, HOME_B + Vector2(200.0, 0.0), inv_short, holder)
	await ctx.tree.physics_frame
	ctx.check(not short_can and short_placed == null and inv_short.count_of(WOOD) == 1
			and _addons_under(holder).size() == before_count,
		"INSUFFICIENT (wood 1 < 2): place REFUSES and consumes NOTHING -- wood stays 1 (not drained), no add-on spawned; can_place agreed (false)",
		"insufficient add-on placement was not atomic (can=%s, placed=%s, wood=%d, spawned=%d)" % [str(short_can), str(short_placed != null), inv_short.count_of(WOOD), _addons_under(holder).size() - before_count])

	holder.queue_free()
	await ctx.tree.physics_frame


## Leg C: a Station + an add-on placed near it in a LIVE chunk both round-trip across unload/reload as ADDITION
## deltas, and the station's level() RECOMPUTES to 2 from the persisted add-on (nothing level-specific stored).
## Zero-orphan; the generator baseline regenerates byte-identically (determinism sacred). Hand-driven ChunkManager
## (load_radius 1 -> a 3x3 set, so one short hop unloads the focus chunk and back reloads it).
func _leg_persist(ctx: TestContext) -> void:
	var mgr: ChunkManager = ChunkManager.new()
	mgr.load_radius = 1
	mgr.world_seed = SEED
	ctx.tree.root.add_child(mgr)
	var mover: Node2D = Node2D.new()
	ctx.tree.root.add_child(mover)
	mgr.target = mover

	# The DETERMINISM ORACLE: the generator's per-Kind baseline for the focus chunk, captured BEFORE any placement.
	var oracle: Dictionary = _gen_counts(ChunkGenerator.generate(FOCUS_C, SEED))

	mover.global_position = WorldScale.chunk_origin(FOCUS_C) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var container: Node2D = mgr.active_container(FOCUS_C)

	# Place a live Station + a live add-on 30 px from it (both under the chunk container), and register BOTH as
	# additions (keyed by each entity's OWN placement_kind()/capture_state() -- the placeable contract). Registering
	# after activation appends the entries BEYOND _content, the case the generalized addition-skip must handle.
	var station_pos: Vector2 = WorldScale.chunk_origin(FOCUS_C) + STATION_LOCAL_C
	var addon_pos: Vector2 = WorldScale.chunk_origin(FOCUS_C) + ADDON_LOCAL_C
	var live_station: Station = STATION_SCENE.instantiate() as Station
	container.add_child(live_station)
	live_station.global_position = station_pos
	mgr.register_placement(station_pos, live_station.placement_kind(), live_station.capture_state())
	var live_addon: StationAddon = ADDON_SCENE.instantiate() as StationAddon
	container.add_child(live_addon)
	live_addon.global_position = addon_pos
	mgr.register_placement(addon_pos, live_addon.placement_kind(), live_addon.capture_state())
	await ctx.tree.physics_frame

	var stored: ChunkData = mgr.stored_data(FOCUS_C)
	ctx.check(_station_entries(stored).size() == 1 and _addon_entries(stored).size() == 1 and stored.dirty
			and live_station.level() == 2,
		"place-while-active: a Station AND a Kind.ADDON add-on recorded as distinct ADDITION deltas on chunk " + str(FOCUS_C) + " (a dirty delta chunk); the live station reads level() 2 from the add-on in reach",
		"place/record/level wrong (stations=" + str(_station_entries(stored).size()) + " addons=" + str(_addon_entries(stored).size()) + " level=" + str(live_station.level()) + ")")

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# UNLOAD: the generalized skip (ChunkData.is_addition_kind covers ADDON) must KEEP both additions, never gone-flag.
	mover.global_position = WorldScale.chunk_origin(FOCUS_C + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var kept_st: Array = _station_entries(mgr.stored_data(FOCUS_C))
	var kept_ad: Array = _addon_entries(mgr.stored_data(FOCUS_C))
	ctx.check(kept_st.size() == 1 and kept_ad.size() == 1 and not _any_gone(kept_st) and not _any_gone(kept_ad),
		"persist-across-unload: BOTH the STATION and the ADDON additions are KEPT (neither gone-flagged) -- the generalized deactivate-skip covers the add-on kind",
		"an addition was lost/gone-flagged on unload (stations=" + str(kept_st.size()) + " addons=" + str(kept_ad.size()) + ")")

	# RELOAD: spawn() re-creates both from their deltas; the station's level() RECOMPUTES to 2 from the persisted add-on.
	mover.global_position = WorldScale.chunk_origin(FOCUS_C) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rc: Node2D = mgr.active_container(FOCUS_C)
	var reloaded_st: Array = _stations_in(rc)
	var reloaded_ad: Array = _addons_in(rc)
	var reload_ok: bool = reloaded_st.size() == 1 and reloaded_ad.size() == 1 \
		and station_pos.distance_to((reloaded_st[0] as Station).global_position) < 0.5 \
		and addon_pos.distance_to((reloaded_ad[0] as StationAddon).global_position) < 0.5 \
		and (reloaded_st[0] as Station).level() == 2
	ctx.check(reload_ok,
		"reload-round-trip: EXACTLY one Station + one add-on respawned at their SAME positions (no double, no loss), and the station's level() RECOMPUTES to 2 from the persisted add-on -- the level was never stored, only the add-on delta",
		"station+add-on did not round-trip / relevel correctly (stations=" + str(reloaded_st.size()) + " addons=" + str(reloaded_ad.size()) + " level=" + str((reloaded_st[0] as Station).level() if reloaded_st.size() == 1 else -1) + ")")

	# DETERMINISM: the additions did NOT perturb the generator baseline -- regenerating the chunk is byte-identical.
	ctx.check(_counts_equal(_gen_counts(ChunkGenerator.generate(FOCUS_C, SEED)), oracle),
		"determinism intact: regenerating " + str(FOCUS_C) + " yields per-Kind counts byte-identical to the oracle -- the add-on + station are explicit deltas, never rng draws",
		"the additions shifted the generator baseline (regen != oracle)")

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	ctx.check(orphans_after <= orphans_before,
		"zero-orphan-leak: orphan node count did not grow across place -> unload -> reload (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"orphan nodes leaked across the leveling round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	mgr.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## Instantiate a Station of `tag` at world position `at` under the holder (immediate add so _ready runs its group
## join), then set its position. Returns the live node. Mirrors test_station._make_station.
func _make_station(holder: Node2D, at: Vector2, tag: StringName) -> Station:
	var st: Station = STATION_SCENE.instantiate() as Station
	st.station_tag = tag
	holder.add_child(st)
	st.global_position = at
	return st


## Instantiate a StationAddon at world position `at` under the holder (immediate add so _ready joins the group),
## then set its position. Returns the live node.
func _make_addon(holder: Node2D, at: Vector2) -> StationAddon:
	var addon: StationAddon = ADDON_SCENE.instantiate() as StationAddon
	holder.add_child(addon)
	addon.global_position = at
	return addon


## The live StationAddon instances directly under a holder/container (empty if null).
func _addons_under(parent: Node) -> Array:
	var out: Array = []
	if parent == null:
		return out
	for child in parent.get_children():
		if child is StationAddon:
			out.append(child)
	return out


## Alias for a chunk container (Leg C) -- same scan, named for the test's readability.
func _addons_in(container: Node2D) -> Array:
	return _addons_under(container)


## The live Station instances directly under a chunk container (empty if null).
func _stations_in(container: Node2D) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is Station:
			out.append(child)
	return out


## The Kind.STATION ADDITION entries of a stored ChunkData (empty if null).
func _station_entries(cd: ChunkData) -> Array:
	return _entries_of_kind(cd, ChunkData.Kind.STATION)


## The Kind.ADDON ADDITION entries of a stored ChunkData (empty if null).
func _addon_entries(cd: ChunkData) -> Array:
	return _entries_of_kind(cd, ChunkData.Kind.ADDON)


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


## Per-Kind counts of a generated ChunkData's existing (non-addition) baseline Kinds -- the determinism oracle.
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


## Field-by-field equality of two per-Kind count Dictionaries (the six baseline Kinds).
func _counts_equal(a: Dictionary, b: Dictionary) -> bool:
	for k in ["tree", "rock", "enemy", "bush", "pebble", "boulder"]:
		if int(a.get(k, -1)) != int(b.get(k, -2)):
			return false
	return true

# Verified against: Godot 4.7.1 (2026-07-20)
