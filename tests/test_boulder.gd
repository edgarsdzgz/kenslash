class_name TestBoulder extends RefCounted
## Environment #2 -- LARGE UNMINEABLE ROCK TERRAIN (boulders), design-environment.md section 2. A Boulder
## (world/boulder.gd) is a big SOLID StaticBody2D that BLOCKS movement and divides areas, in authorable
## sizes rock -> hill -> mountain, streamed as a new ChunkData.Kind.BOULDER. Unlike the mineable Rock it
## is PERMANENT terrain -- no Hurtbox, no durability, no drops -- so a pick/axe does nothing to it and it
## never yields or breaks. This leg proves all of that AND the load-bearing invariant: adding the BOULDER
## Kind did NOT disturb the deterministic generator (TREE/MINERAL/ENEMY/BUSH/PEBBLE counts byte-unchanged,
## boulders reproduce identically on unload/reload).
##
## Self-contained: builds its own holders / players / boulders at REMOTE coords and its own ChunkManager,
## frees them at the end, and touches no shared game state. Registered in tests/smoke_slash.gd. Mirrors
## the streaming determinism style of tests/test_streaming.gd rather than weakening it.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const BOULDER_SCENE: PackedScene = preload("res://world/boulder.tscn")

## Remote region clear of every other self-contained module's coords (elevation 48000, pebble -60000,
## forage -30000, ...), so no other body wanders into these solidity checks.
const HOME: Vector2 = Vector2(90000.0, -90000.0)
## Seed for this leg's own ChunkManager + generator scans -- distinct from test_streaming's 7.
const SEED: int = 4242


func run(ctx: TestContext) -> void:
	print("[boulder] --- Environment #2: solid + unmineable + sized terrain, streamed deterministically ---")
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	# --- SIZES DIFFER: rock -> hill -> mountain build bigger footprints + taller silhouettes ---------
	var rock_b: Boulder = _make_boulder(holder, HOME + Vector2(0.0, 0.0), Boulder.Size.ROCK)
	var hill_b: Boulder = _make_boulder(holder, HOME + Vector2(400.0, 0.0), Boulder.Size.HILL)
	var mtn_b: Boulder = _make_boulder(holder, HOME + Vector2(800.0, 0.0), Boulder.Size.MOUNTAIN)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rock_foot: Vector2 = _foot_size(rock_b)
	var hill_foot: Vector2 = _foot_size(hill_b)
	var mtn_foot: Vector2 = _foot_size(mtn_b)
	ctx.check(rock_foot.x < hill_foot.x and hill_foot.x < mtn_foot.x
			and rock_foot.y < hill_foot.y and hill_foot.y < mtn_foot.y,
		"boulder SIZES build strictly larger solid footprints (rock " + str(rock_foot) + " < hill " + str(hill_foot) + " < mountain " + str(mtn_foot) + ")",
		"boulder footprints did not grow with size (rock " + str(rock_foot) + ", hill " + str(hill_foot) + ", mtn " + str(mtn_foot) + ")")
	var rock_h: float = _visual_height(rock_b)
	var hill_h: float = _visual_height(hill_b)
	var mtn_h: float = _visual_height(mtn_b)
	ctx.check(rock_h < hill_h and hill_h < mtn_h,
		"boulder SIZES build strictly taller visual silhouettes (rock " + str(rock_h) + " < hill " + str(hill_h) + " < mtn " + str(mtn_h) + ")",
		"boulder visual heights did not grow with size (rock " + str(rock_h) + ", hill " + str(hill_h) + ", mtn " + str(mtn_h) + ")")
	ctx.check(Boulder.Size.size() == 3,
		"three authorable sizes exist (Boulder.Size: ROCK, HILL, MOUNTAIN)",
		"Boulder.Size enum did not expose exactly 3 sizes (" + str(Boulder.Size.size()) + ")")

	# --- SOLID: a body driven into a boulder is STOPPED; a non-colliding one passes through ----------
	# p_solid is a real Player (collision_mask includes the `world` bit the boulder body sits on), driven
	# RIGHT into a boulder 70 px ahead. It must be BLOCKED -- never reaching the boulder's center. p_ghost
	# is an identical player with the world bit CLEARED from its mask, driven into an identical boulder: it
	# passes straight THROUGH (ends well past the boulder). Same boulder, opposite mask -> proves the
	# boulder's solid body is what blocks, not some unrelated stop.
	var p_solid: Player = _spawn_player(holder, HOME + Vector2(0.0, 4000.0))
	var block_b: Boulder = _make_boulder(holder, p_solid.global_position + Vector2(70.0, 0.0), Boulder.Size.ROCK)
	var solid_start_x: float = p_solid.global_position.x
	_drive_right(p_solid, 60)
	for _i in range(60):
		await ctx.tree.physics_frame
	p_solid.input_override = null
	ctx.check(p_solid.global_position.x > solid_start_x + 2.0 and p_solid.global_position.x < block_b.global_position.x
			and is_instance_valid(block_b),
		"SOLID: player pushed toward a boulder MOVED but was BLOCKED before its center (start " + str(solid_start_x) + " -> " + str(p_solid.global_position.x) + " < boulder x " + str(block_b.global_position.x) + ")",
		"player was NOT blocked by the boulder (x=" + str(p_solid.global_position.x) + ", boulder x=" + str(block_b.global_position.x) + ")")
	ctx.check(block_b.collision_layer & 1 != 0 and block_b.collision_mask == 0,
		"boulder body sits on the `world` collision layer (bit 1) and masks nothing -- a passive solid obstacle",
		"boulder collision layer/mask wrong (layer " + str(block_b.collision_layer) + ", mask " + str(block_b.collision_mask) + ")")

	var p_ghost: Player = _spawn_player(holder, HOME + Vector2(0.0, 6000.0))
	p_ghost.collision_mask = p_ghost.collision_mask & ~1  # drop the world bit -> phase through solids
	var ghost_b: Boulder = _make_boulder(holder, p_ghost.global_position + Vector2(70.0, 0.0), Boulder.Size.ROCK)
	_drive_right(p_ghost, 60)
	for _i in range(60):
		await ctx.tree.physics_frame
	p_ghost.input_override = null
	ctx.check(p_ghost.global_position.x > ghost_b.global_position.x + 10.0,
		"control: a body NOT masking `world` phases straight through the same boulder (ended past it at " + str(p_ghost.global_position.x) + ") -- confirms the block was the solid body",
		"control body did not pass through (x=" + str(p_ghost.global_position.x) + ", boulder x=" + str(ghost_b.global_position.x) + ")")

	# --- UNMINEABLE: no harvest chokepoint exists, and a real MINE strike does nothing --------------
	# Structural: a boulder is NOT a HarvestableBody and carries NO Hurtbox / Material / HealthComponent /
	# any Area2D -- so there is literally no monitoring party for a player_hitbox to route damage through.
	var mine_b: Boulder = _make_boulder(holder, HOME + Vector2(0.0, 8000.0), Boulder.Size.HILL)
	await ctx.tree.physics_frame
	# Route the HarvestableBody check through a Node ref: a statically-typed `Boulder is HarvestableBody`
	# is a COMPILE error in Godot 4.7 (the types are provably unrelated), which is itself the point --
	# a Boulder is NOT in the harvestable hierarchy at all.
	var mine_node: Node = mine_b
	ctx.check(not (mine_node is HarvestableBody)
			and mine_b.get_node_or_null("Hurtbox") == null
			and mine_b.get_node_or_null("Material") == null
			and mine_b.get_node_or_null("HealthComponent") == null
			and _any_area2d(mine_b) == null,
		"UNMINEABLE by construction: boulder is not a HarvestableBody and has NO Hurtbox/Material/HealthComponent/Area2D -- no chokepoint a pick/axe could route through",
		"boulder exposed a harvest chokepoint (Hurtbox/Material/Health/Area2D present)")

	# Functional: place a STRONG MINE Hitbox (would shatter a rock) overlapping the boulder and step
	# several physics frames. With no monitoring Hurtbox nothing fires -- assert the boulder stays valid,
	# in-tree, and ZERO drops appeared. A pick does nothing.
	var strong: Hitbox = Hitbox.new()
	strong.power = 99
	strong.break_threshold = 1
	strong.wear_max = 4
	strong.harvest_type = Harvest.Type.MINE
	var strong_dura: DurabilityComponent = DurabilityComponent.new()
	strong.durability = strong_dura
	strong.add_child(strong_dura)
	holder.add_child(strong)
	strong.global_position = mine_b.global_position
	for _i in range(6):
		await ctx.tree.physics_frame
	ctx.check(is_instance_valid(mine_b) and mine_b.is_inside_tree() and _drops(holder).size() == 0,
		"a strong MINE strike overlapping the boulder did NOTHING: boulder still standing, ZERO stone yielded, not freed",
		"boulder reacted to a mine strike (valid=" + str(is_instance_valid(mine_b)) + ", drops=" + str(_drops(holder).size()) + ")")

	# --- STREAMING DETERMINISM: existing-kind counts UNCHANGED; boulders reproduce identically -------
	_assert_generator_determinism(ctx)
	await _assert_roundtrip_identical(ctx)

	holder.queue_free()
	await ctx.tree.physics_frame


## Prove the boulder Kind is DRAWN LAST and shifted NO earlier draw: for a scan of coords, the live
## generator's TREE/MINERAL/ENEMY/BUSH/PEBBLE counts must equal an INDEPENDENT replay of the exact
## pre-boulder draw sequence (a boulder-free generator). If boulders had been inserted before pebbles the
## pebble/bush counts would diverge. Also proves boulder entries are appended LAST in the entries array,
## that regeneration is byte-identical, and that sizes derive deterministically with real variety.
func _assert_generator_determinism(ctx: TestContext) -> void:
	var counts_match: bool = true
	var boulders_last: bool = true
	var regen_identical: bool = true
	var chunks_with_boulders: int = 0
	var total_boulders: int = 0
	var sizes_seen: Dictionary = {}
	for cx in range(0, 24):
		for cy in range(0, 24):
			var coord: Vector2i = Vector2i(cx, cy)
			var cd: ChunkData = ChunkGenerator.generate(coord, SEED)

			# (a) existing-kind counts == the boulder-free replay of the same seeded sequence
			var live: Dictionary = _kind_counts(cd)
			var ref: Dictionary = _replay_pre_boulder_counts(coord, SEED)
			for k in ref.keys():
				if int(live[k]) != int(ref[k]):
					counts_match = false

			# (b) every BOULDER entry sits AFTER every non-boulder entry (append-last ordering)
			var last_non_boulder: int = -1
			var first_boulder: int = 999999
			for i in range(cd.entries.size()):
				if int(cd.entries[i]["type"]) == ChunkData.Kind.BOULDER:
					first_boulder = mini(first_boulder, i)
				else:
					last_non_boulder = maxi(last_non_boulder, i)
			if first_boulder != 999999 and first_boulder <= last_non_boulder:
				boulders_last = false

			# (c) regeneration is byte-identical for the boulder entries; tally variety
			var b1: Array = _boulder_entries(cd)
			var b2: Array = _boulder_entries(ChunkGenerator.generate(coord, SEED))
			if b1 != b2:
				regen_identical = false
			if b1.size() > 0:
				chunks_with_boulders += 1
				total_boulders += b1.size()
				for be in b1:
					sizes_seen[int(be[2])] = true  # be = [x, y, size]; size is index 2

	ctx.check(counts_match,
		"determinism: TREE/MINERAL/ENEMY/BUSH/PEBBLE counts are byte-identical to a boulder-free replay of the same seed across 576 chunks -- adding BOULDER shifted NO existing draw",
		"an existing-kind count diverged from the pre-boulder replay -- boulder generation perturbed the seeded sequence")
	ctx.check(boulders_last,
		"determinism: every BOULDER entry is appended AFTER all TREE/MINERAL/ENEMY/BUSH/PEBBLE entries (drawn LAST)",
		"a BOULDER entry was not appended last -- draw order changed")
	ctx.check(regen_identical,
		"determinism: regenerating a coord yields byte-identical boulder entries (type/pos/size) -- pure, no RNG/Time/OS in the derivation",
		"boulder entries were not reproducible across two regenerations of the same coord")
	ctx.check(chunks_with_boulders >= 1 and total_boulders >= 1 and sizes_seen.size() >= 2,
		"boulders are present and VARIED across the region: " + str(total_boulders) + " boulders in " + str(chunks_with_boulders) + " chunks, " + str(sizes_seen.size()) + " distinct sizes (sparse, not litter)",
		"boulder presence/variety wrong (boulders=" + str(total_boulders) + " chunks=" + str(chunks_with_boulders) + " sizes=" + str(sizes_seen.size()) + ")")


## Prove a boulder chunk reproduces IDENTICAL boulders (positions + sizes) after a real unload/reload
## through a live ChunkManager -- boulders are permanent + never dirtied, so reload == deterministic
## regenerate. Mirrors the C3b round-trip shape of test_streaming.gd without weakening it.
func _assert_roundtrip_identical(ctx: TestContext) -> void:
	var manager: ChunkManager = ChunkManager.new()
	manager.load_radius = 1
	manager.world_seed = SEED
	ctx.tree.root.add_child(manager)
	var mover: Node2D = Node2D.new()
	ctx.tree.root.add_child(mover)
	manager.target = mover

	var focus: Vector2i = _find_boulder_chunk(SEED)
	if focus.x == _SCAN_MISS:
		ctx.check(false, "", "no boulder chunk found in the scan window (seed " + str(SEED) + ")")
		manager.queue_free()
		mover.queue_free()
		await ctx.tree.physics_frame
		return

	# Activate the boulder chunk and snapshot its live boulders (local pos + size).
	mover.global_position = WorldScale.chunk_origin(focus) + Vector2(10.0, 10.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var before: Array = _boulders_in(manager.active_container(focus))

	# Hop far away so the chunk UNLOADS (container freed), then hop back so it RELOADS.
	mover.global_position = WorldScale.chunk_origin(focus + Vector2i(40, 40)) + Vector2(10.0, 10.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var unloaded: bool = manager.active_container(focus) == null
	mover.global_position = WorldScale.chunk_origin(focus) + Vector2(10.0, 10.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var after: Array = _boulders_in(manager.active_container(focus))

	ctx.check(before.size() >= 1 and unloaded and before == after,
		"round-trip: a boulder chunk unloaded then reloaded reproduces IDENTICAL boulders (" + str(before.size()) + " boulders, same pos+size) -- permanent terrain regenerates byte-identically, no leak",
		"boulders did not round-trip identically (before " + str(before) + " / unloaded " + str(unloaded) + " / after " + str(after) + ")")

	manager.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame


## Sentinel for a scan that found no matching chunk.
const _SCAN_MISS: int = -999999


## Per-Kind entry counts of a generated chunk, for the kinds the boulder addition must NOT have disturbed.
func _kind_counts(cd: ChunkData) -> Dictionary:
	var c: Dictionary = {"tree": 0, "mineral": 0, "enemy": 0, "bush": 0, "pebble": 0}
	for e in cd.entries:
		match int(e["type"]):
			ChunkData.Kind.TREE: c["tree"] += 1
			ChunkData.Kind.MINERAL: c["mineral"] += 1
			ChunkData.Kind.ENEMY: c["enemy"] += 1
			ChunkData.Kind.BUSH: c["bush"] += 1
			ChunkData.Kind.PEBBLE: c["pebble"] += 1
	return c


## Independently REPLAY ChunkGenerator's pre-boulder draw sequence for (coord, seed) with a fresh RNG
## seeded identically, consuming the SAME draws in the SAME order (counts + the two position draws per
## entity, exactly as _rand_local does) but STOPPING before boulders. Returns the per-Kind counts a
## boulder-free generator would produce -- the regression oracle for "existing kinds unchanged".
func _replay_pre_boulder_counts(coord: Vector2i, seed_val: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = ChunkGenerator._derive_seed(coord, seed_val)
	var tree_count: int = rng.randi_range(ChunkGenerator.TREES_MIN, ChunkGenerator.TREES_MAX)
	for _i in tree_count:
		_consume_local(rng)
	var mineral_count: int = rng.randi_range(ChunkGenerator.MINERALS_MIN, ChunkGenerator.MINERALS_MAX)
	for _i in mineral_count:
		_consume_local(rng)
	var enemy_count: int = 0
	if rng.randf() < ChunkGenerator.ENEMY_CHANCE:
		enemy_count = 1
		_consume_local(rng)  # the enemy's local_pos draw (its type is a zero-draw hash)
	var bush_count: int = rng.randi_range(ChunkGenerator.BUSH_MIN, ChunkGenerator.BUSH_MAX)
	for _i in bush_count:
		_consume_local(rng)
	var pebble_count: int = rng.randi_range(ChunkGenerator.PEBBLE_MIN, ChunkGenerator.PEBBLE_MAX)
	# STOP here: whatever the boulder step draws next cannot affect these already-decided counts.
	return {"tree": tree_count, "mineral": mineral_count, "enemy": enemy_count, "bush": bush_count, "pebble": pebble_count}


## Consume exactly the two draws _rand_local makes, to keep the replay aligned with the generator.
func _consume_local(rng: RandomNumberGenerator) -> void:
	rng.randf_range(0.0, WorldScale.CHUNK_PX)
	rng.randf_range(0.0, WorldScale.CHUNK_PX)


## The BOULDER entries of a generated chunk as [ [x, y, size], ... ] in entry order -- comparable with
## == for the byte-identical regeneration check.
func _boulder_entries(cd: ChunkData) -> Array:
	var out: Array = []
	for e in cd.entries:
		if int(e["type"]) == ChunkData.Kind.BOULDER:
			var lp: Vector2 = e["local_pos"]
			out.append([lp.x, lp.y, int((e["state"] as Dictionary).get("size", -1))])
	return out


## The live Boulder instances under a chunk container as [ [pos, size], ... ], sorted for a stable,
## order-independent == compare across the unload/reload round trip.
func _boulders_in(container: Node2D) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is Boulder:
			out.append([child.position, int((child as Boulder).size)])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0].x != b[0].x:
			return a[0].x < b[0].x
		return a[0].y < b[0].y)
	return out


## Scan a bounded coord window for the first chunk whose deterministic baseline has >= 1 BOULDER entry.
func _find_boulder_chunk(seed_val: int) -> Vector2i:
	for cx in range(0, 40):
		for cy in range(0, 40):
			var c: Vector2i = Vector2i(cx, cy)
			for e in ChunkGenerator.generate(c, seed_val).entries:
				if int(e["type"]) == ChunkData.Kind.BOULDER:
					return c
	return Vector2i(_SCAN_MISS, _SCAN_MISS)


## The RectangleShape2D footprint (width, height) a live boulder built for its size.
func _foot_size(b: Boulder) -> Vector2:
	var cs: CollisionShape2D = b.get_node("CollisionShape2D") as CollisionShape2D
	return (cs.shape as RectangleShape2D).size


## The visual silhouette height (px) a live boulder built -- the vertical span of its Body polygon.
func _visual_height(b: Boulder) -> float:
	var body: Polygon2D = b.get_node("Body") as Polygon2D
	var min_y: float = 0.0
	var max_y: float = 0.0
	for p in body.polygon:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	return max_y - min_y


## First Area2D anywhere in a node's subtree, or null. Used to prove a boulder has NO harvest chokepoint.
func _any_area2d(node: Node) -> Area2D:
	if node is Area2D:
		return node as Area2D
	for child in node.get_children():
		var found: Area2D = _any_area2d(child)
		if found != null:
			return found
	return null


## The live Drop instances directly under a holder node (empty if none) -- proves an unmineable strike
## yielded nothing.
func _drops(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child is Drop:
			out.append(child)
	return out


## Instantiate a Boulder of `size` at world position `at` under the holder (immediate add so _ready runs).
func _make_boulder(holder: Node2D, at: Vector2, size: Boulder.Size) -> Boulder:
	var b: Boulder = BOULDER_SCENE.instantiate() as Boulder
	b.size = size
	holder.add_child(b)
	b.global_position = at
	return b


## Instantiate a real Player at `at`, parented so its _physics_process runs. pickup_radius 0 keeps it inert.
func _spawn_player(holder: Node2D, at: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0
	holder.add_child(player)
	player.global_position = at
	return player


## Drive a player RIGHT via the FrameInput seam for the next N frames (caller clears input_override after).
func _drive_right(player: Player, _frames: int) -> void:
	var fi: FrameInput = FrameInput.new()
	fi.move = Vector2.RIGHT
	fi.attack = false
	player.input_override = fi

# Verified against: Godot 4.7.1 (2026-07-19)
