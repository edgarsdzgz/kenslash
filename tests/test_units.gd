class_name TestUnits extends RefCounted
## Pure UNIT tests -- no scene, no await. Three decoupled slices proved directly:
##   * the two resolvers (CombatResolver.hp_damage across atk >/=/< def; the three
##     DurabilityResolver bands for the sword AND the pickaxe -- exact numbers from
##     design-durability.md);
##   * the Inventory model (design-inventory.md): default shape, add_tool auto-populate
##     order, equip_index direct-jump incl. empty slots, cycle/wrap locked vs unlocked
##     incl. the doc's 10-key-ring example, lock-vs-unlock range widening;
##   * streaming C1 chunk-data foundation (design-world-streaming.md): chunk-coord math
##     incl. the negative-coord floor cases, chunk_origin round-trips, ChunkGenerator
##     determinism, and the lossless ChunkData Dictionary round-trip.
## Split out of the former monolithic tests/smoke_slash.gd (CONVENTIONS.md Rule 1).


func run(ctx: TestContext) -> void:
	_unit_tests(ctx)
	_inventory_unit_tests(ctx)
	_chunk_unit_tests(ctx)


func _unit_tests(ctx: TestContext) -> void:
	# CombatResolver: subtractive, floored at 0 -- DEF can FULLY block (design-durability.md).
	ctx.check(CombatResolver.hp_damage(6, 1) == 5,
		"CombatResolver.hp_damage(6,1) == 5 (atk > def)",
		"CombatResolver.hp_damage(6,1) != 5")
	ctx.check(CombatResolver.hp_damage(4, 4) == 0,
		"CombatResolver.hp_damage(4,4) == 0 (atk == def, floors at 0)",
		"CombatResolver.hp_damage(4,4) != 0")
	ctx.check(CombatResolver.hp_damage(2, 9) == 0,
		"CombatResolver.hp_damage(2,9) == 0 (atk < def, DEF fully blocks)",
		"CombatResolver.hp_damage(2,9) != 0")

	# DurabilityResolver: the three bands (sword power 5, threshold 3, wear_max 4).
	var band_a: Dictionary = DurabilityResolver.resolve(5, 2, 3, 4)
	ctx.check(int(band_a["weapon_wear"]) == 0 and bool(band_a["affects_target"]),
		"DurabilityResolver Band A resolve(5,2,3,4) -> wear 0, affects true",
		"Band A resolve(5,2,3,4) wrong: " + str(band_a))
	var band_b: Dictionary = DurabilityResolver.resolve(5, 7, 3, 4)
	ctx.check(int(band_b["weapon_wear"]) == 3 and bool(band_b["affects_target"]),
		"DurabilityResolver Band B resolve(5,7,3,4) -> wear 3, affects true",
		"Band B resolve(5,7,3,4) wrong: " + str(band_b))
	var band_b_soft: Dictionary = DurabilityResolver.resolve(5, 6, 3, 4)
	ctx.check(int(band_b_soft["weapon_wear"]) == 2 and bool(band_b_soft["affects_target"]),
		"DurabilityResolver Band B resolve(5,6,3,4) -> wear 2, affects true (soft rock)",
		"Band B resolve(5,6,3,4) wrong: " + str(band_b_soft))
	var band_c: Dictionary = DurabilityResolver.resolve(5, 12, 3, 4)
	ctx.check(int(band_c["weapon_wear"]) == 4 and not bool(band_c["affects_target"]),
		"DurabilityResolver Band C resolve(5,12,3,4) -> wear 4, affects false (obsidian)",
		"Band C resolve(5,12,3,4) wrong: " + str(band_c))

	# Pickaxe power 7 (System 3 tool table) against the SAME two rocks -- confirms
	# the mineral/obsidian band split still holds with the pickaxe's own numbers,
	# not just the sword's, per design-durability.md's tuning note.
	var pick_band_a: Dictionary = DurabilityResolver.resolve(7, 6, 3, 4)
	ctx.check(int(pick_band_a["weapon_wear"]) == 0 and bool(pick_band_a["affects_target"]),
		"DurabilityResolver Band A resolve(7,6,3,4) -> wear 0, affects true (pickaxe, soft rock)",
		"Band A resolve(7,6,3,4) wrong: " + str(pick_band_a))
	var pick_band_c: Dictionary = DurabilityResolver.resolve(7, 12, 3, 4)
	ctx.check(int(pick_band_c["weapon_wear"]) == 4 and not bool(pick_band_c["affects_target"]),
		"DurabilityResolver Band C resolve(7,12,3,4) -> wear 4, affects false (pickaxe, obsidian)",
		"Band C resolve(7,12,3,4) wrong: " + str(pick_band_c))


func _inventory_unit_tests(ctx: TestContext) -> void:
	# --- Default shape -------------------------------------------------------
	var inv: Inventory = Inventory.new()
	ctx.check(inv.slots.size() == 15 and inv.hotbar_size() == 10,
		"Inventory default: slots.size()==15, hotbar_size()==10 (10-key hotbar window over 15 slots)",
		"Inventory default shape wrong (slots=" + str(inv.slots.size()) + " hotbar=" + str(inv.hotbar_size()) + ")")

	# --- add_tool: fills first-empty in caller-supplied priority order -------
	var added_sword: bool = inv.add_tool(Player.SWORD_DATA)
	var added_axe: bool = inv.add_tool(Player.AXE_DATA)
	var added_pick: bool = inv.add_tool(Player.PICKAXE_DATA)
	ctx.check(added_sword and added_axe and added_pick
			and inv.item_at(0) == Player.SWORD_DATA and inv.item_at(1) == Player.AXE_DATA
			and inv.item_at(2) == Player.PICKAXE_DATA
			and inv.item_at(3) == null and inv.item_at(13) == null and inv.item_at(14) == null,
		"add_tool fills first-empty in priority order (sword,axe,pickaxe -> slots 0-2; 3-14 empty)",
		"add_tool ordering wrong: " + str(inv.slots))

	# --- equip_index: direct jump to ANY valid index, including empty --------
	inv.equip_index(4)
	ctx.check(inv.equipped_index == 4 and inv.equipped_tool() == null,
		"equip_index jumps directly to an EMPTY slot (index 4, equipped_tool() null)",
		"equip_index to an empty slot wrong (index=" + str(inv.equipped_index) + " tool=" + str(inv.equipped_tool()) + ")")
	inv.equip_index(1)
	ctx.check(inv.equipped_index == 1 and inv.equipped_tool() == Player.AXE_DATA,
		"equip_index jumps directly to a FILLED slot (index 1 -> axe)",
		"equip_index to a filled slot wrong (index=" + str(inv.equipped_index) + " tool=" + str(inv.equipped_tool()) + ")")

	# --- Cycle/wrap, LOCKED, default 15-slot inventory (hotbar_size=10) -------
	# Locked scroll wraps within the 10-slot hotbar window [0,10), never into the 10-14
	# background-storage slots.
	var lock_inv: Inventory = Inventory.new()
	lock_inv.equip_index(0)
	lock_inv.cycle(-1)
	ctx.check(lock_inv.equipped_index == 9,
		"locked cycle(-1) from index 0 wraps to 9 (last of the 10-slot hotbar, not index 14)",
		"locked cycle(-1) from 0 wrong (got " + str(lock_inv.equipped_index) + ")")
	lock_inv.cycle(-1)
	ctx.check(lock_inv.equipped_index == 8,
		"locked cycle(-1) again -> 8",
		"locked cycle(-1) again wrong (got " + str(lock_inv.equipped_index) + ")")
	lock_inv.equip_index(9)
	lock_inv.cycle(1)
	ctx.check(lock_inv.equipped_index == 0,
		"locked cycle(+1) from 9 wraps forward to 0",
		"locked cycle(+1) from 9 wrong (got " + str(lock_inv.equipped_index) + ")")

	# --- Cycle/wrap, the FULL 10-key-ring example from design-inventory.md ---
	var ring_inv: Inventory = Inventory.new()
	ring_inv.slots.resize(10)
	ctx.check(ring_inv.hotbar_size() == 10,
		"a 10-slot inventory has hotbar_size()==10",
		"10-slot hotbar_size() wrong (got " + str(ring_inv.hotbar_size()) + ")")
	ring_inv.equip_index(0)  # key '1'
	ring_inv.cycle(-1)
	ctx.check(ring_inv.equipped_index == 9,
		"10-key ring: cycle(-1) from '1' (index 0) -> '0' (index 9)",
		"10-key ring cycle(-1) from 0 wrong (got " + str(ring_inv.equipped_index) + ")")
	ring_inv.cycle(-1)
	ctx.check(ring_inv.equipped_index == 8,
		"10-key ring: cycle(-1) again -> '9' (index 8)",
		"10-key ring cycle(-1) again wrong (got " + str(ring_inv.equipped_index) + ")")
	ring_inv.equip_index(9)  # key '0'
	ring_inv.cycle(1)
	ctx.check(ring_inv.equipped_index == 0,
		"10-key ring: cycle(+1) from '0' (index 9) -> '1' (index 0)",
		"10-key ring cycle(+1) from 9 wrong (got " + str(ring_inv.equipped_index) + ")")
	ring_inv.cycle(1)
	ctx.check(ring_inv.equipped_index == 1,
		"10-key ring: cycle(+1) again -> '2' (index 1)",
		"10-key ring cycle(+1) again wrong (got " + str(ring_inv.equipped_index) + ")")

	# --- Lock vs unlock range, 12-slot inventory (hotbar_size=10) -------------
	var big_inv: Inventory = Inventory.new()
	big_inv.slots.resize(12)
	ctx.check(big_inv.hotbar_size() == 10,
		"a 12-slot inventory still caps hotbar_size() at 10",
		"12-slot hotbar_size() wrong (got " + str(big_inv.hotbar_size()) + ")")
	# LOCKED: repeated cycle(-1) from 0 stays within [0,10), never reaching 10/11.
	big_inv.equip_index(0)
	var locked_out_of_range: bool = false
	for _i in range(11):
		big_inv.cycle(-1)
		if big_inv.equipped_index >= 10:
			locked_out_of_range = true
	ctx.check(not locked_out_of_range,
		"locked scroll on a 12-slot inventory never leaves the 10-slot hotbar window [0,10)",
		"locked scroll wrongly reached beyond the hotbar window")
	# UNLOCKED: cycle(-1) from 0 reaches 11 -- the full 12, not just the 10-hotbar.
	big_inv.equip_index(0)
	big_inv.hotbar_unlocked = true
	big_inv.cycle(-1)
	ctx.check(big_inv.equipped_index == 11,
		"unlocked cycle(-1) from 0 reaches index 11 (the full 12-slot inventory)",
		"unlocked cycle(-1) from 0 wrong (got " + str(big_inv.equipped_index) + ")")
	# Toggling lock alone (no cycle call) must not move equipped_index.
	var lock_toggle_inv: Inventory = Inventory.new()
	lock_toggle_inv.equip_index(3)
	var before_lock_toggle: int = lock_toggle_inv.equipped_index
	lock_toggle_inv.hotbar_unlocked = true
	ctx.check(lock_toggle_inv.equipped_index == before_lock_toggle,
		"toggling hotbar_unlocked alone does not change equipped_index",
		"toggling lock moved equipped_index (" + str(before_lock_toggle) + " -> " + str(lock_toggle_inv.equipped_index) + ")")

	# --- Number-key direct jump ignores lock state ----------------------------
	var jump_inv: Inventory = Inventory.new()
	jump_inv.slots.resize(12)
	jump_inv.hotbar_unlocked = false
	jump_inv.equip_index(4)
	ctx.check(jump_inv.equipped_index == 4,
		"equip_index(4) lands on 4 while LOCKED",
		"equip_index(4) while locked wrong (got " + str(jump_inv.equipped_index) + ")")
	jump_inv.hotbar_unlocked = true
	jump_inv.equip_index(4)
	ctx.check(jump_inv.equipped_index == 4,
		"equip_index(4) lands on 4 while UNLOCKED (direct jump ignores lock either way)",
		"equip_index(4) while unlocked wrong (got " + str(jump_inv.equipped_index) + ")")

	# --- E1b item model: stacking, overflow, tool non-stacking, equip gating ---------
	var WOOD: ItemData = load("res://data/wood.tres")
	ctx.check(WOOD != null and WOOD.max_stack == 255 and WOOD.glyph == "W",
		"wood.tres loads as ItemData (max_stack 255, glyph W)",
		"wood.tres wrong (item=" + str(WOOD) + ")")

	# Resource stacking under the 255 cap: 10 then 60 wood now BOTH fit in slot0 (70 <= 255),
	# so a single stack, slot1 empty. Then +200 more (270 total) tops slot0 to the 255 cap and
	# spills the remaining 15 into slot1 -- exercising the max_stack boundary directly.
	var stack_inv: Inventory = Inventory.new()
	var wood_first: int = stack_inv.add_item(WOOD, 10)
	var wood_second: int = stack_inv.add_item(WOOD, 60)
	ctx.check(wood_first == 0 and wood_second == 0
			and stack_inv.count_at(0) == 70 and stack_inv.item_at(0) == WOOD
			and stack_inv.count_at(1) == 0,
		"add_item stacks wood under cap 255: 10 then 60 -> a single 70-stack in slot0, slot1 empty",
		"wood stacking wrong (r1=" + str(wood_first) + " r2=" + str(wood_second)
			+ " c0=" + str(stack_inv.count_at(0)) + " c1=" + str(stack_inv.count_at(1)) + ")")
	var wood_third: int = stack_inv.add_item(WOOD, 200)
	ctx.check(wood_third == 0
			and stack_inv.count_at(0) == 255 and stack_inv.item_at(0) == WOOD
			and stack_inv.count_at(1) == 15 and stack_inv.item_at(1) == WOOD
			and stack_inv.count_at(2) == 0,
		"add_item honors the 255 cap: +200 more (270 total) fills slot0 to 255 and spills 15 to slot1",
		"wood 255-boundary spill wrong (r3=" + str(wood_third)
			+ " c0=" + str(stack_inv.count_at(0)) + " c1=" + str(stack_inv.count_at(1)) + ")")

	# Overflow: a 15-slot inventory holds 15*255=3825 wood; adding 3830 into a fresh one fills
	# every slot to the 255 cap and spills 5 back as the returned remainder.
	var overflow_inv: Inventory = Inventory.new()
	var overflow: int = overflow_inv.add_item(WOOD, 3830)
	ctx.check(overflow == 5 and overflow_inv.count_at(14) == 255,
		"add_item overflow: 3830 wood into 15 slots (cap 3825) returns 5, last slot full at 255",
		"wood overflow wrong (remainder=" + str(overflow) + " c14=" + str(overflow_inv.count_at(14)) + ")")

	# Tools never merge: two swords land in two separate single-count slots.
	var tool_inv: Inventory = Inventory.new()
	var t1: int = tool_inv.add_item(Player.SWORD_DATA, 1)
	var t2: int = tool_inv.add_item(Player.SWORD_DATA, 1)
	ctx.check(t1 == 0 and t2 == 0
			and tool_inv.item_at(0) == Player.SWORD_DATA and tool_inv.count_at(0) == 1
			and tool_inv.item_at(1) == Player.SWORD_DATA and tool_inv.count_at(1) == 1,
		"add_item never merges tools: two swords -> two separate slots, count 1 each",
		"tool non-stacking wrong (c0=" + str(tool_inv.count_at(0)) + " c1=" + str(tool_inv.count_at(1)) + ")")

	# Equip gating: a resource stack in the equipped slot is NOT a weapon --
	# equipped_tool() returns null (unarmed) while equipped_item() returns the resource.
	var gate_inv: Inventory = Inventory.new()
	gate_inv.add_item(WOOD, 5)
	gate_inv.equip_index(0)
	ctx.check(gate_inv.equipped_item() == WOOD and gate_inv.equipped_tool() == null,
		"equip gating: a resource stack -> equipped_item() is the item, equipped_tool() is null (unarmed)",
		"equip gating wrong (item=" + str(gate_inv.equipped_item()) + " tool=" + str(gate_inv.equipped_tool()) + ")")


func _chunk_unit_tests(ctx: TestContext) -> void:
	# --- world_to_chunk: floor division correct for POSITIVE and NEGATIVE coords ---
	# CHUNK_PX = 640. The negatives are the trap: GDScript truncates toward zero, so a
	# naive int divide would map (-1,-1) to (0,0). floori floors toward -inf instead.
	ctx.check(WorldScale.CHUNK_TILES == 16 and WorldScale.CHUNK_PX == 640.0,
		"chunk constants: CHUNK_TILES == 16, CHUNK_PX == 640.0",
		"chunk constants wrong (tiles=" + str(WorldScale.CHUNK_TILES) + " px=" + str(WorldScale.CHUNK_PX) + ")")
	ctx.check(WorldScale.world_to_chunk(Vector2(0, 0)) == Vector2i(0, 0),
		"world_to_chunk(0,0) == (0,0)",
		"world_to_chunk(0,0) wrong (got " + str(WorldScale.world_to_chunk(Vector2(0, 0))) + ")")
	ctx.check(WorldScale.world_to_chunk(Vector2(639, 639)) == Vector2i(0, 0),
		"world_to_chunk(639,639) == (0,0) (last px inside chunk 0)",
		"world_to_chunk(639,639) wrong (got " + str(WorldScale.world_to_chunk(Vector2(639, 639))) + ")")
	ctx.check(WorldScale.world_to_chunk(Vector2(640, 0)) == Vector2i(1, 0),
		"world_to_chunk(640,0) == (1,0) (first px of chunk 1)",
		"world_to_chunk(640,0) wrong (got " + str(WorldScale.world_to_chunk(Vector2(640, 0))) + ")")
	ctx.check(WorldScale.world_to_chunk(Vector2(-1, -1)) == Vector2i(-1, -1),
		"world_to_chunk(-1,-1) == (-1,-1) (NEGATIVE floors to -1, not 0)",
		"world_to_chunk(-1,-1) wrong (got " + str(WorldScale.world_to_chunk(Vector2(-1, -1))) + ")")
	ctx.check(WorldScale.world_to_chunk(Vector2(-640, -640)) == Vector2i(-1, -1),
		"world_to_chunk(-640,-640) == (-1,-1) (top-left of chunk -1)",
		"world_to_chunk(-640,-640) wrong (got " + str(WorldScale.world_to_chunk(Vector2(-640, -640))) + ")")
	ctx.check(WorldScale.world_to_chunk(Vector2(-641, 0)) == Vector2i(-2, 0),
		"world_to_chunk(-641,0) == (-2,0) (one px past chunk -1 boundary)",
		"world_to_chunk(-641,0) wrong (got " + str(WorldScale.world_to_chunk(Vector2(-641, 0))) + ")")

	# --- chunk_origin: top-left world pos = coord * CHUNK_PX -------------------
	ctx.check(WorldScale.chunk_origin(Vector2i(0, 0)) == Vector2(0, 0)
			and WorldScale.chunk_origin(Vector2i(1, 0)) == Vector2(640, 0)
			and WorldScale.chunk_origin(Vector2i(-1, -1)) == Vector2(-640, -640)
			and WorldScale.chunk_origin(Vector2i(-2, 3)) == Vector2(-1280, 1920),
		"chunk_origin maps coord -> coord*640 (incl. negatives)",
		"chunk_origin wrong (e.g. (-1,-1) -> " + str(WorldScale.chunk_origin(Vector2i(-1, -1))) + ")")

	# --- chunk_origin round-trips through world_to_chunk for many coords -------
	var round_trip_ok: bool = true
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 7), Vector2i(-1, -1),
			Vector2i(-2, 0), Vector2i(-3, 4), Vector2i(10, -8)]:
		if WorldScale.world_to_chunk(WorldScale.chunk_origin(c)) != c:
			round_trip_ok = false
	ctx.check(round_trip_ok,
		"world_to_chunk(chunk_origin(c)) == c for several coords (incl. negatives)",
		"chunk_origin/world_to_chunk round-trip failed for some coord")

	# --- ChunkGenerator DETERMINISM: same (coord, seed) -> identical entries ----
	var gen_a: ChunkData = ChunkGenerator.generate(Vector2i(3, -2), 12345)
	var gen_b: ChunkData = ChunkGenerator.generate(Vector2i(3, -2), 12345)
	ctx.check(_entries_equal(gen_a.entries, gen_b.entries) and gen_a.coord == gen_b.coord,
		"ChunkGenerator deterministic: generate((3,-2),12345) twice yields identical entries (" + str(gen_a.entries.size()) + ")",
		"ChunkGenerator NOT deterministic: two identical calls diverged")
	# Different SEED shifts content; different COORD shifts content -- proves it is
	# actually seeded, not a constant scatter.
	var gen_diff_seed: ChunkData = ChunkGenerator.generate(Vector2i(3, -2), 99999)
	var gen_diff_coord: ChunkData = ChunkGenerator.generate(Vector2i(4, -2), 12345)
	ctx.check(not _entries_equal(gen_a.entries, gen_diff_seed.entries),
		"ChunkGenerator seeded: a different world_seed yields different content",
		"ChunkGenerator ignored the seed (same content for seed 12345 vs 99999)")
	ctx.check(not _entries_equal(gen_a.entries, gen_diff_coord.entries),
		"ChunkGenerator seeded: a different coord yields different content",
		"ChunkGenerator ignored the coord (same content for (3,-2) vs (4,-2))")

	# --- ChunkData Dictionary round-trip: lossless to_dict()/from_dict() --------
	var src: ChunkData = ChunkGenerator.generate(Vector2i(-7, 5), 424242)
	src.dirty = true  # exercise the dirty flag through the round-trip too
	var restored: ChunkData = ChunkData.from_dict(src.to_dict())
	ctx.check(restored.coord == src.coord and restored.dirty == src.dirty
			and restored.entries.size() == src.entries.size(),
		"ChunkData round-trip: coord/dirty/entry-count preserved (" + str(src.entries.size()) + " entries, dirty=" + str(src.dirty) + ")",
		"ChunkData round-trip lost coord/dirty/count (coord " + str(restored.coord) + " dirty " + str(restored.dirty) + " n " + str(restored.entries.size()) + ")")
	ctx.check(_entries_equal(src.entries, restored.entries),
		"ChunkData round-trip: every entry (type/local_pos/state) is lossless",
		"ChunkData round-trip corrupted an entry's type/local_pos/state")
	# The restored state dicts must be independent copies (mutating one must not touch
	# the other) -- confirms to_dict/from_dict deep-copy rather than alias.
	var alias_free: bool = true
	for i in src.entries.size():
		var s_state: Dictionary = src.entries[i]["state"]
		var r_state: Dictionary = restored.entries[i]["state"]
		if s_state.has("integrity"):
			r_state["integrity"] = 999
			if int(s_state["integrity"]) == 999:
				alias_free = false
			r_state["integrity"] = int(s_state["integrity"])  # restore for cleanliness
	ctx.check(alias_free,
		"ChunkData round-trip: restored entry state is an independent deep copy (no aliasing)",
		"ChunkData round-trip aliased entry state between source and restored")


func _entries_equal(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if int(a[i]["type"]) != int(b[i]["type"]):
			return false
		if Vector2(a[i]["local_pos"]) != Vector2(b[i]["local_pos"]):
			return false
		if a[i]["state"] != b[i]["state"]:
			return false
	return true

# Verified against: Godot 4.7.1 (2026-07-18)
