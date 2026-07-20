class_name TestBuilder extends RefCounted
## PLACEMENT + build cost end to end (plan-epic2-parts.md Phase 1 Part 1.1). Proves components/builder.gd
## places a Station into the world for a recipe-like BUILD COST deducted from the Inventory, ATOMICALLY, and
## that the PLACED station is a real station-gate-satisfying node -- deterministically (no Time/OS/RNG; Builder
## + Inventory + CharacterSheet + Crafting are RefCounted, the Station is a real node under this test's OWN
## holder). Goal-post assertions:
##   * can_place TRUE with sufficient materials -> place() spawns a Station at the target position, in the
##     "station" group, consuming the EXACT build cost (stone x3 + stick x2) and keeping the surplus;
##   * the PLACED station satisfies the craft station-gate: Station.levels_in_range finds its &"forge" tag and a
##     forge-gated recipe (master_cordage) crafts beside it (fiber 5 -> 0, cord 0 -> 3), yet refuses far away;
##   * can_place FALSE with a short build item -> place() refuses and consumes NOTHING (the OTHER, present item
##     is untouched -- atomic, no partial deduction), spawning no station;
##   * can_place EXACTLY matches place()'s accept/refuse in both cases.
## Self-contained: builds its own holder / inventories at REMOTE coords clear of every other module's station
## scans, frees the holder (and the placed station under it) at teardown, so the streaming node-count / orphan
## and station-scan baselines are undisturbed. Mirrors the isolation style of tests/test_station.gd. Registered
## in tests/smoke_slash.gd.

const STATION_SCENE: PackedScene = preload("res://world/station.tscn")

const MASTER: StringName = &"master_cordage"  # fiber x5 -> cord x3, station_tag &"forge", min_level 3

## Remote region clear of every other self-contained module's coords (station -90000/90000, boulder 90000/
## -90000, elevation 48000, pebble -60000, ...), so no stray station wanders into these levels_in_range scans and
## this test's placed station wanders into no other module's scan.
const HOME: Vector2 = Vector2(120000.0, 120000.0)


func run(ctx: TestContext) -> void:
	print("[builder] --- placement + build cost: place a Station for stone x3 + stick x2, atomic, gate-satisfying ---")
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var builder: Builder = Builder.new()

	var STONE: ItemData = load("res://data/stone.tres")
	var STICK: ItemData = load("res://data/stick.tres")
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")

	# --- SUFFICIENT: can_place true -> place spawns at target in group, consumes EXACT cost, keeps surplus ---
	# Inventory with a surplus of both build items (stone 5 >= 3, stick 4 >= 2). can_place clears; place spawns
	# the station at HOME under this holder, deducting exactly stone x3 + stick x2 (5 -> 2, 4 -> 2 surplus).
	var inv: Inventory = Inventory.new()
	inv.add_item(STONE, 5)
	inv.add_item(STICK, 4)
	var can_ok: bool = builder.can_place(STATION_SCENE, inv)
	var placed: Node = builder.place(STATION_SCENE, HOME, inv, holder)
	await ctx.tree.physics_frame
	var station: Station = placed as Station
	ctx.check(can_ok and station != null and station.is_in_group(Station.GROUP)
			and station.global_position == HOME
			and inv.count_of(STONE) == 2 and inv.count_of(STICK) == 2,
		"place SPAWNS a Station at the target in the \"station\" group and consumes the EXACT build cost (stone 5 -> 2, stick 4 -> 2 surplus); can_place agreed (true)",
		"place did not spawn/charge correctly (can=%s, station=%s, grouped=%s, pos=%s, stone=%d, stick=%d)" % [str(can_ok), str(station != null), str(station != null and station.is_in_group(Station.GROUP)), str(station.global_position if station != null else Vector2.ZERO), inv.count_of(STONE), inv.count_of(STICK)])

	# --- PLACED station satisfies the craft station-gate, end to end -------------------------------------
	# master_cordage (station_tag &"forge") + 5 fiber. Beside the PLACED station the scan returns {&"forge": 1} and
	# the craft succeeds (fiber 5 -> 0, cord 0 -> 3) -- the levels flowing placed-Station -> levels_in_range ->
	# Crafting.craft with no coupling. Far from it the scan is empty and the SAME craft refuses (fiber stays 5).
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.progression.blueprint_points = 3
	sheet.progression.level = 3
	var learned: bool = sheet.learn_recipe(MASTER)
	var craft: Crafting = Crafting.new()

	var near_levels: Dictionary = Station.levels_in_range(HOME, Station.DEFAULT_REACH)
	var inv_near: Inventory = Inventory.new()
	inv_near.add_item(FIBER, 5)
	var near_ok: bool = craft.craft(MASTER, sheet, inv_near, near_levels)
	ctx.check(learned and near_levels.has(&"forge") and near_ok
			and inv_near.count_of(FIBER) == 0 and inv_near.count_of(CORD) == 3,
		"the PLACED station satisfies the station-gate: levels_in_range finds &\"forge\" and master_cordage crafts beside it (fiber 5 -> 0, cord 0 -> 3)",
		"placed station did not satisfy the craft gate (learned=%s, levels=%s, ok=%s, fiber=%d, cord=%d)" % [str(learned), str(near_levels), str(near_ok), inv_near.count_of(FIBER), inv_near.count_of(CORD)])

	var away: Vector2 = HOME + Vector2(0.0, 6000.0)
	var away_levels: Dictionary = Station.levels_in_range(away, Station.DEFAULT_REACH)
	var inv_away: Inventory = Inventory.new()
	inv_away.add_item(FIBER, 5)
	var away_ok: bool = craft.craft(MASTER, sheet, inv_away, away_levels)
	ctx.check(away_levels.is_empty() and not away_ok and inv_away.count_of(FIBER) == 5,
		"far from the placed station the gate closes: levels_in_range {} -> master_cordage refuses, fiber stays 5",
		"placed-station gate leaked far away (levels=%s, ok=%s, fiber=%d)" % [str(away_levels), str(away_ok), inv_away.count_of(FIBER)])

	# --- INSUFFICIENT: can_place false -> place refuses, consumes NOTHING (atomic, no partial) -----------
	# stone sufficient (3 >= 3) but stick SHORT (1 < 2). can_place must be false and place must return null with
	# NEITHER item touched -- the present stone is not drained (the classic partial-consumption bug) -- and no
	# station spawned. Count stations under the holder before/after to prove no addition delta leaked.
	var before_count: int = _stations_under(holder).size()
	var inv_short: Inventory = Inventory.new()
	inv_short.add_item(STONE, 3)
	inv_short.add_item(STICK, 1)
	var short_can: bool = builder.can_place(STATION_SCENE, inv_short)
	var short_placed: Node = builder.place(STATION_SCENE, HOME + Vector2(200.0, 0.0), inv_short, holder)
	await ctx.tree.physics_frame
	var after_count: int = _stations_under(holder).size()
	ctx.check(not short_can and short_placed == null
			and inv_short.count_of(STONE) == 3 and inv_short.count_of(STICK) == 1
			and after_count == before_count,
		"INSUFFICIENT (stick 1 < 2): place REFUSES and consumes NOTHING -- stone stays 3 (not drained), stick stays 1, no station spawned; can_place agreed (false)",
		"insufficient placement was not atomic (can=%s, placed=%s, stone=%d, stick=%d, spawned_delta=%d)" % [str(short_can), str(short_placed != null), inv_short.count_of(STONE), inv_short.count_of(STICK), after_count - before_count])

	holder.queue_free()
	await ctx.tree.physics_frame


## The live Station instances directly under a holder (empty if none) -- proves a refused placement spawned
## nothing while the accepted one did.
func _stations_under(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child is Station:
			out.append(child)
	return out

# Verified against: Godot 4.7.1 (2026-07-20)
