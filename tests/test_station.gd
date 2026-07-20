class_name TestStation extends RefCounted
## Crafting STATION + the station-gate, end to end (plan-epic1-parts.md Part 4.1; plan-core-loop.md Phase 4;
## design-crafting.md "Track B"). Where tests/test_crafting.gd proves the gate LOGIC purely (passing a tag list
## straight to Crafting.craft), this leg proves the WORLD half: real Station nodes (world/station.gd) in the
## "station" group, the STATIC Station.tags_in_range() distance scan that collects their tags, and the two
## joined so a station-gated recipe genuinely fails out of range and succeeds in range of the right station.
## Goal-post assertions:
##   * tags_in_range collects ONLY stations within the radius -- a forge just inside is picked up, an identical
##     forge just outside is not (deterministic <= radius compare);
##   * a DISTINCT-tag scan de-duplicates (two forges near the query yield one &"forge") and reports a
##     different-tagged station separately;
##   * END TO END: master_cordage (station_tag &"forge") REFUSES when the scan finds no forge in range
##     (nothing consumed) and SUCCEEDS when a forge IS in range -- the tags flowing Station -> tags_in_range ->
##     Crafting.craft with no coupling between them;
##   * a craft-anywhere recipe (spin_cord) still crafts with NO station anywhere near.
## Self-contained: builds its own holder / stations / character sheets at REMOTE coords, frees them at the end,
## and touches no shared game state -- mirrors the isolation style of tests/test_boulder.gd. Registered in
## tests/smoke_slash.gd.

const STATION_SCENE: PackedScene = preload("res://world/station.tscn")

const MASTER: StringName = &"master_cordage"  # fiber x5 -> cord x3, station_tag &"forge", min_level 3
const SPIN: StringName = &"spin_cord"         # fiber x3 -> cord x1, station_tag "" (craft anywhere)

## Remote region clear of every other self-contained module's coords (boulder 90000, elevation 48000,
## pebble -60000, ...), so no stray station node from elsewhere wanders into these radius scans.
const HOME: Vector2 = Vector2(-90000.0, 90000.0)


func run(ctx: TestContext) -> void:
	print("[station] --- crafting station: in-range tag scan + station-gated craft, end to end ---")
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	# --- tags_in_range: ONE station in radius, ONE out -----------------------------------------------
	# A forge 30 px from the query point (well inside a 100 px reach) and an identical forge 400 px away
	# (well outside). The scan must return exactly [&"forge"] -- the near one in, the far one filtered out.
	var query: Vector2 = HOME
	var near: Station = _make_station(holder, query + Vector2(30.0, 0.0), &"forge")
	var far: Station = _make_station(holder, query + Vector2(400.0, 0.0), &"forge")
	await ctx.tree.physics_frame
	var in_only: Array[StringName] = Station.tags_in_range(query, 100.0)
	ctx.check(in_only.has(&"forge") and in_only.size() == 1 and is_instance_valid(near) and is_instance_valid(far),
		"tags_in_range collects ONLY the in-radius station: forge at 30px IN, identical forge at 400px OUT (got " + str(in_only) + ")",
		"tags_in_range did not filter by radius (got " + str(in_only) + ")")

	# The far forge alone from a query near IT proves the same scan finds it when it IS the close one --
	# so the miss above was distance, not a broken group join.
	var far_side: Array[StringName] = Station.tags_in_range(far.global_position, 100.0)
	ctx.check(far_side.has(&"forge") and far_side.size() == 1,
		"the far forge IS found by a query beside it (100px) -- the earlier miss was distance, not a bad group join (got " + str(far_side) + ")",
		"the far station was not in its own group scan (got " + str(far_side) + ")")

	# --- DE-DUP + distinct tags: two forges near + one anvil near ------------------------------------
	# A second forge overlapping the query and a differently-tagged station both in range: the forge tag
	# appears ONCE (de-duplicated) and the anvil tag appears alongside it.
	var dedup_home: Vector2 = HOME + Vector2(0.0, 3000.0)
	_make_station(holder, dedup_home + Vector2(10.0, 0.0), &"forge")
	_make_station(holder, dedup_home + Vector2(20.0, 0.0), &"forge")
	_make_station(holder, dedup_home + Vector2(0.0, 25.0), &"anvil")
	await ctx.tree.physics_frame
	var many: Array[StringName] = Station.tags_in_range(dedup_home, 100.0)
	ctx.check(many.has(&"forge") and many.has(&"anvil") and many.size() == 2,
		"tags_in_range DE-DUPLICATES: two forges + one anvil near the query -> [&\"forge\", &\"anvil\"] once each (got " + str(many) + ")",
		"tags_in_range did not de-dup / collect distinct tags (got " + str(many) + ")")

	# --- END TO END: station-gated craft fails out of range, succeeds in range ----------------------
	# A learned master_cordage (station_tag &"forge") + 5 fiber. Query a spot with NO forge nearby: the scan
	# returns [], the craft REFUSES, nothing consumed. Then query beside the near forge: the scan returns
	# [&"forge"], the craft SUCCEEDS (fiber 5 -> 0, cord 0 -> 3). The station node and Crafting never touch.
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.progression.blueprint_points = 3
	sheet.progression.level = 3
	var learned: bool = sheet.learn_recipe(MASTER)
	var craft: Crafting = Crafting.new()

	# Out of range: a query far from every station (5000 px away) -> empty scan -> refuse.
	var away: Vector2 = HOME + Vector2(0.0, 6000.0)
	var inv_out: Inventory = Inventory.new()
	inv_out.add_item(FIBER, 5)
	var out_tags: Array[StringName] = Station.tags_in_range(away, Station.DEFAULT_REACH)
	var out_ok: bool = craft.craft(MASTER, sheet, inv_out, out_tags)
	ctx.check(learned and out_tags.is_empty() and not out_ok
			and inv_out.count_of(FIBER) == 5 and inv_out.count_of(CORD) == 0,
		"END TO END: no forge in range -> tags_in_range [] -> master_cordage REFUSES, nothing consumed (fiber stays 5)",
		"station-gated craft ran out of range (learned=%s, tags=%s, ok=%s, fiber=%d, cord=%d)" % [str(learned), str(out_tags), str(out_ok), inv_out.count_of(FIBER), inv_out.count_of(CORD)])

	# In range: query beside the near forge -> [&"forge"] -> craft succeeds end to end.
	var inv_in: Inventory = Inventory.new()
	inv_in.add_item(FIBER, 5)
	var in_tags: Array[StringName] = Station.tags_in_range(near.global_position, Station.DEFAULT_REACH)
	var in_ok: bool = craft.craft(MASTER, sheet, inv_in, in_tags)
	ctx.check(in_tags.has(&"forge") and in_ok and inv_in.count_of(FIBER) == 0 and inv_in.count_of(CORD) == 3,
		"END TO END: a forge in range -> tags_in_range [&\"forge\"] -> master_cordage crafts (fiber 5 -> 0, cord 0 -> 3)",
		"station-gated craft failed in range (tags=%s, ok=%s, fiber=%d, cord=%d)" % [str(in_tags), str(in_ok), inv_in.count_of(FIBER), inv_in.count_of(CORD)])

	# --- craft-anywhere recipe crafts with NO station near -------------------------------------------
	var sheet_free: CharacterSheet = CharacterSheet.new()
	sheet_free.known_recipes.learn(SPIN)
	var inv_free: Inventory = Inventory.new()
	inv_free.add_item(FIBER, 3)
	var free_tags: Array[StringName] = Station.tags_in_range(away, Station.DEFAULT_REACH)  # [] out here
	var free_ok: bool = craft.craft(SPIN, sheet_free, inv_free, free_tags)
	ctx.check(free_tags.is_empty() and free_ok and inv_free.count_of(FIBER) == 0 and inv_free.count_of(CORD) == 1,
		"craft-anywhere spin_cord crafts with NO station in range (tags []): fiber 3 -> 0, cord 0 -> 1 -- the gate fences only station-tagged recipes",
		"craft-anywhere recipe was blocked with no station (tags=%s, ok=%s, fiber=%d, cord=%d)" % [str(free_tags), str(free_ok), inv_free.count_of(FIBER), inv_free.count_of(CORD)])

	holder.queue_free()
	await ctx.tree.physics_frame


## Instantiate a Station of `tag` at world position `at` under the holder (immediate add so _ready runs its
## group-join), then set its position. Returns the live node.
func _make_station(holder: Node2D, at: Vector2, tag: StringName) -> Station:
	var st: Station = STATION_SCENE.instantiate() as Station
	st.station_tag = tag
	holder.add_child(st)
	st.global_position = at
	return st

# Verified against: Godot 4.7.1 (2026-07-19)
