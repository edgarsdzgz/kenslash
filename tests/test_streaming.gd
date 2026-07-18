class_name TestStreaming extends RefCounted
## Streaming integration (design-world-streaming.md), self-contained -- builds its OWN
## ChunkManager setups and (for the camera leg) its own streaming_world.tscn instance,
## never touching the main.tscn combat entities:
##   C2: the ChunkManager active-set-by-proximity orchestrator -- bounded 25-chunk set
##       regardless of world size / distance travelled, correct 5x5 contents incl.
##       negative coords, camera follow;
##   C3a: REAL Tree/Rock/Enemy content spawns one-per-entry, counts match the generator,
##       a mineral instance is configured from its entry.state; zero-orphan-leak on unload;
##   C3b: delta persistence across unload/reload (mined-stays-mined, destroyed-stays-gone,
##       enemy-HP-persists, killed-enemy-stays-gone, store-is-data-not-nodes).
## Split out of the former monolithic tests/smoke_slash.gd (CONVENTIONS.md Rule 1).


func run(ctx: TestContext) -> void:
	print("[streaming] --- C2 orchestrator: bounded active set + zero-orphan-leak ---")
	var r: int = 2
	var expected: int = (2 * r + 1) * (2 * r + 1)  # 5x5 = 25

	var manager: ChunkManager = ChunkManager.new()
	manager.load_radius = r
	manager.world_seed = 7
	ctx.tree.root.add_child(manager)
	var mover: Node2D = Node2D.new()
	ctx.tree.root.add_child(mover)
	manager.target = mover
	mover.global_position = Vector2.ZERO
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	# --- Bounded active set REGARDLESS of world size -------------------------
	# Teleport the target diagonally across a 110x110-chunk span (incl. negative
	# coordinate space), stepping physics frames so the manager updates. The active
	# count must NEVER exceed 25 and must be EXACTLY 25 after each settle -- the bound
	# is load_radius, not how far the target roamed or how many chunks exist.
	var never_exceeded: bool = true
	var always_bounded: bool = true
	var steps_checked: int = 0
	for step in range(-50, 61, 7):  # chunk indices -50..60 along a diagonal
		var coord: Vector2i = Vector2i(step, -step)
		mover.global_position = WorldScale.chunk_origin(coord) \
				+ Vector2(WorldScale.CHUNK_PX * 0.5, WorldScale.CHUNK_PX * 0.5)
		await ctx.tree.physics_frame
		await ctx.tree.physics_frame
		var n: int = manager.active_chunk_count()
		steps_checked += 1
		if n > expected:
			never_exceeded = false
		if n != expected:
			always_bounded = false
	ctx.check(never_exceeded,
		"bounded active set: count NEVER exceeded " + str(expected) + " across a 110-chunk diagonal traversal (" + str(steps_checked) + " steps)",
		"active set EXCEEDED the load_radius bound -- sprawl/leak")
	ctx.check(always_bounded,
		"bounded active set: count == " + str(expected) + " at every settled step, independent of world size / distance travelled",
		"active set was not exactly " + str(expected) + " after settling at some step")

	# --- Correct active-set CONTENTS (incl. negative coords) -----------------
	var focus: Vector2i = Vector2i(-13, 8)  # deep in negative-x space
	mover.global_position = WorldScale.chunk_origin(focus) + Vector2(10, 10)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var want: Dictionary = {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			want[focus + Vector2i(dx, dy)] = true
	var got: Array[Vector2i] = manager.active_coords()
	var contents_ok: bool = got.size() == want.size()
	if contents_ok:
		for c in got:
			if not want.has(c):
				contents_ok = false
				break
	ctx.check(contents_ok and got.size() == expected,
		"active set is exactly the 5x5 block centered on chunk " + str(focus) + " (incl. negative coords), " + str(got.size()) + " chunks",
		"active set contents wrong at " + str(focus) + " (got " + str(got.size()) + " coords)")

	# --- C3a: REAL content spawns, one instance per ChunkData entry ----------
	# The manager is settled with the 25-chunk active set around `focus`. Regenerate the
	# SAME coords through the deterministic generator to compute how many Tree/Rock/Enemy
	# entries SHOULD exist, then count the real instances actually under the live chunk
	# containers. Exact equality per Kind proves entry -> real-scene instancing (not a
	# stand-in), and that the generator drives it. Deterministic (seed 7), so the numbers
	# are fixed, not flaky.
	var exp_tree: int = 0
	var exp_rock: int = 0
	var exp_enemy: int = 0
	for coord in manager.active_coords():
		var cd: ChunkData = ChunkGenerator.generate(coord, manager.world_seed)
		for e in cd.entries:
			match int(e["type"]):
				ChunkData.Kind.TREE: exp_tree += 1
				ChunkData.Kind.MINERAL: exp_rock += 1
				ChunkData.Kind.ENEMY: exp_enemy += 1
	var got_tree: int = 0
	var got_rock: int = 0
	var got_enemy: int = 0
	for container in manager.get_children():
		for child in container.get_children():
			# Order matters: Rock extends StaticBody2D, so test Rock first; Enemy is a
			# CharacterBody2D; Tree has no class_name (native-class clash) so it is the
			# remaining StaticBody2D content.
			if child is Enemy:
				got_enemy += 1
			elif child is Rock:
				got_rock += 1
			elif child is StaticBody2D:
				got_tree += 1
	ctx.check(got_tree == exp_tree and got_tree >= 1,
		"real Tree instances match generated entries and are present (" + str(got_tree) + " == " + str(exp_tree) + ", >=1)",
		"Tree instance count wrong (" + str(got_tree) + " vs expected " + str(exp_tree) + ")")
	ctx.check(got_rock == exp_rock and got_rock >= 1,
		"real Rock instances match generated entries and are present (" + str(got_rock) + " == " + str(exp_rock) + ", >=1)",
		"Rock instance count wrong (" + str(got_rock) + " vs expected " + str(exp_rock) + ")")
	ctx.check(got_enemy == exp_enemy and got_enemy >= 1,
		"real Enemy instances match generated entries and appear given the enemy chance (" + str(got_enemy) + " == " + str(exp_enemy) + ", >=1)",
		"Enemy instance count wrong (" + str(got_enemy) + " vs expected " + str(exp_enemy) + ")")

	# --- C3a: a mineral instance is CONFIGURED from its entry.state ----------
	# Drive a synthetic MINERAL entry through the SAME ChunkContent.spawn() the manager
	# uses, with a NON-default integrity (2, distinct from the scene default 4 -- so a
	# broken wiring could not pass by coincidence). After _ready the Rock's Material
	# DurabilityComponent must reflect integrity 2, and its Hurtbox the streamed hardness 6.
	var synth_entry: Dictionary = {
		"type": ChunkData.Kind.MINERAL,
		"local_pos": Vector2(10, 20),
		"state": {"integrity": 2},
	}
	var synth_rock: Rock = ChunkContent.spawn(synth_entry) as Rock
	ctx.tree.root.add_child(synth_rock)
	await ctx.tree.physics_frame  # let rock.gd._ready() push integrity/hardness onto its children
	var synth_mat: DurabilityComponent = synth_rock.get_node("Material") as DurabilityComponent
	var synth_hurt: Hurtbox = synth_rock.get_node("Hurtbox") as Hurtbox
	ctx.check(synth_mat.current_durability == 2 and synth_mat.max_durability == 2,
		"mineral instance integrity configured from entry.state.integrity=2 (Material " + str(synth_mat.current_durability) + "/" + str(synth_mat.max_durability) + ", not the default 4)",
		"mineral integrity not wired from entry.state (got " + str(synth_mat.current_durability) + "/" + str(synth_mat.max_durability) + ")")
	ctx.check(synth_hurt.hardness == 6 and synth_rock.position == Vector2(10, 20),
		"mineral instance took the streamed hardness 6 and its entry local_pos (10, 20)",
		"mineral hardness/position not wired (hardness " + str(synth_hurt.hardness) + ", pos " + str(synth_rock.position) + ")")
	synth_rock.queue_free()
	await ctx.tree.physics_frame

	# --- ZERO-ORPHAN-LEAK on unload ------------------------------------------
	# Settle at a baseline center and snapshot the node population. Then drive the
	# target on a LONG round trip that activates+deactivates MANY far chunks, then
	# return to the EXACT baseline center. ChunkGenerator is deterministic, so the
	# same center regenerates an identical population -- so if freed chunks' Nodes
	# were actually released (not orphaned), every count returns to baseline.
	var base_center: Vector2i = Vector2i(3, -4)
	mover.global_position = WorldScale.chunk_origin(base_center) + Vector2(5, 5)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame  # let any deferred queue_free from the move above resolve
	var nodes_before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var containers_before: int = manager.get_child_count()
	var content_before: int = _count_content_roots(manager)

	for step in range(0, 40):  # walk far away, crossing ~40 fresh chunks
		mover.global_position = WorldScale.chunk_origin(Vector2i(400 + step * 4, -400 - step * 4))
		await ctx.tree.physics_frame
	mover.global_position = WorldScale.chunk_origin(base_center) + Vector2(5, 5)  # come back
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame  # let the far chunks' deferred queue_free resolve

	var nodes_after: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var containers_after: int = manager.get_child_count()
	var content_after: int = _count_content_roots(manager)

	ctx.check(containers_after == expected,
		"zero-leak: manager holds exactly " + str(expected) + " live chunk containers after the round trip (was " + str(containers_before) + ")",
		"manager container count drifted (" + str(containers_before) + " -> " + str(containers_after) + ", expected " + str(expected) + ")")
	ctx.check(content_after == content_before,
		"zero-leak: real content-root population returned to baseline " + str(content_before) + " after activating+freeing many chunks of REAL trees/rocks/enemies (deterministic regen, freed cleanly)",
		"content-root population drifted (" + str(content_before) + " -> " + str(content_after) + ")")
	ctx.check(nodes_after == nodes_before,
		"zero-orphan-leak: total scene node count returned to baseline " + str(nodes_before) + " -- deactivated chunks' REAL content subtrees were FREED, not leaked",
		"scene node count leaked across the round trip (" + str(nodes_before) + " -> " + str(nodes_after) + ")")
	ctx.check(orphans_after <= orphans_before,
		"zero-orphan-leak: orphan node count did not grow (" + str(orphans_before) + " -> " + str(orphans_after) + ")",
		"orphan nodes leaked across the round trip (" + str(orphans_before) + " -> " + str(orphans_after) + ")")

	# Tear down the bare orchestrator setup before the camera leg's own scene loads.
	manager.queue_free()
	mover.queue_free()
	await ctx.tree.physics_frame

	# --- Camera follow smoke: the real streaming_world.tscn --------------------
	# Instantiate the shipped scene (Camera2D childed to Player) and confirm the camera
	# tracks the player after a teleport -- proves wandering a world larger than the
	# screen works -- and that the scene's own ChunkManager streams a bounded set.
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	ctx.check(sw_scene != null,
		"streaming_world.tscn loads",
		"streaming_world.tscn failed to load")
	if sw_scene != null:
		var sw: Node2D = sw_scene.instantiate()
		ctx.tree.root.add_child(sw)
		await ctx.tree.physics_frame
		await ctx.tree.physics_frame
		var sw_player: Node2D = sw.get_node("Player") as Node2D
		var sw_cam: Camera2D = sw_player.get_node("Camera2D") as Camera2D
		sw_player.global_position = Vector2(1234, -987)  # wander off-screen
		await ctx.tree.physics_frame
		await ctx.tree.physics_frame
		var cam_gap: float = sw_cam.global_position.distance_to(sw_player.global_position)
		ctx.check(cam_gap < 1.0,
			"camera follows the player (gap " + str(cam_gap) + " px after a 1234,-987 teleport)",
			"camera did not track the player (gap " + str(cam_gap) + " px)")
		var sw_mgr: ChunkManager = sw.get_node("ChunkManager") as ChunkManager
		ctx.check(sw_mgr.active_chunk_count() == expected,
			"streaming_world scene streams a bounded " + str(expected) + "-chunk set around its player",
			"streaming_world scene active count wrong (" + str(sw_mgr.active_chunk_count()) + ")")
		sw.queue_free()
		await ctx.tree.physics_frame

	# ==========================================================================
	# C3b: DELTA PERSISTENCE across unload/reload -- the Milestone C payoff.
	# Drive a FRESH manager directly (its own target Node2D, never the main.tscn
	# entities and never the pure-traversal manager above): mutate real content,
	# force the containing chunk to DEACTIVATE (triggering write-back into the
	# in-memory store), then REACTIVATE it, and assert the delta SURVIVED --
	# explicitly contrasting C3a's regen-fresh-on-revisit. load_radius 1 (a 3x3 = 9
	# active set) so a short hop moves the focus chunk out of range and back.
	# ==========================================================================
	print("[streaming] --- C3b delta write-back: mined/destroyed/killed persist across reload ---")
	var seed_b: int = 7
	var dm: ChunkManager = ChunkManager.new()
	dm.load_radius = 1
	dm.world_seed = seed_b
	ctx.tree.root.add_child(dm)
	var dmover: Node2D = Node2D.new()
	ctx.tree.root.add_child(dmover)
	dm.target = dmover

	# --- Mined rock STAYS mined + destroyed rock STAYS gone -------------------
	# A chunk with >= 2 minerals: partial-mine the FIRST rock to integrity 2 (survives),
	# fully mine the LAST rock to 0 (destroyed -> queue_free). After a round trip the
	# reloaded first rock must read 2 (NOT the regen-fresh 4) and the destroyed one must
	# NOT reappear (its entry marked gone + skipped).
	var m_focus: Vector2i = _find_chunk(seed_b, 2, false, Vector2i(_SCAN_MISS, _SCAN_MISS), 0)
	ctx.check(m_focus.x != _SCAN_MISS,
		"C3b setup: found a chunk with >= 2 minerals at " + str(m_focus) + " (seed " + str(seed_b) + ")",
		"could not find a >= 2-mineral chunk to test delta persistence")
	dmover.global_position = WorldScale.chunk_origin(m_focus) + Vector2(20, 20)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var m_container: Node2D = dm.active_container(m_focus)
	var rocks: Array = _rocks_in(m_container)
	var rocks_before: int = rocks.size()
	var mined_mat: DurabilityComponent = (rocks[0] as Rock).get_node("Material") as DurabilityComponent
	mined_mat.wear(mined_mat.current_durability - 2)  # partial-mine -> integrity 2 (survives)
	var doomed_mat: DurabilityComponent = (rocks[rocks_before - 1] as Rock).get_node("Material") as DurabilityComponent
	doomed_mat.wear(doomed_mat.current_durability)    # fully mine -> 0 -> broke -> queue_free
	await ctx.tree.physics_frame  # let the doomed rock's deferred queue_free resolve (is_instance_valid flips)

	# Hop away so m_focus leaves the 3x3 active set (write-back), then hop back (reload).
	dmover.global_position = WorldScale.chunk_origin(m_focus + Vector2i(20, 20)) + Vector2(20, 20)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	dmover.global_position = WorldScale.chunk_origin(m_focus) + Vector2(20, 20)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var rocks2: Array = _rocks_in(dm.active_container(m_focus))
	var reloaded_integrity: int = -1
	if rocks2.size() > 0:
		reloaded_integrity = ((rocks2[0] as Rock).get_node("Material") as DurabilityComponent).current_durability
	ctx.check(reloaded_integrity == 2,
		"C3b mined-stays-mined: reloaded rock integrity == 2 (the reduced delta, NOT the regen-fresh 4) -- store persisted the mutation across unload/reload",
		"reloaded rock integrity was " + str(reloaded_integrity) + ", expected 2 (delta lost -> C3a regen-fresh regression)")
	ctx.check(rocks2.size() == rocks_before - 1,
		"C3b destroyed-stays-gone: the fully-mined rock did NOT respawn (rocks " + str(rocks_before) + " -> " + str(rocks2.size()) + "; entry marked gone + skipped on reload)",
		"destroyed rock reappeared on reload (rocks " + str(rocks_before) + " -> " + str(rocks2.size()) + ")")

	# --- Enemy HP persists across reload + a KILLED enemy stays gone ----------
	# A chunk with an enemy, at Chebyshev distance >= 4 from m_focus so their 3x3 neighborhoods
	# never co-activate (keeps the two scenarios' mutations independent -- the seed-agnostic fix
	# for the case where the same coord would satisfy both queries). Damage it to HP 2,
	# round-trip, assert it reloads at HP 2 (not full 6). Then kill it (HP 0), round-trip again,
	# assert it does NOT respawn.
	var e_focus: Vector2i = _find_chunk(seed_b, 0, true, m_focus, 4)
	ctx.check(e_focus.x != _SCAN_MISS,
		"C3b setup: found an enemy chunk at " + str(e_focus) + " (>= 4 chunks from mineral focus " + str(m_focus) + ", seed " + str(seed_b) + ")",
		"could not find an enemy chunk to test HP persistence")
	dmover.global_position = WorldScale.chunk_origin(e_focus) + Vector2(20, 20)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var enemy_e: Enemy = _enemy_in(dm.active_container(e_focus))
	var e_full: int = -1
	if enemy_e != null:
		var e_health: HealthComponent = enemy_e.get_node("HealthComponent") as HealthComponent
		e_full = e_health.max_health
		e_health.take_damage(e_full - 2)  # -> HP 2

	dmover.global_position = WorldScale.chunk_origin(e_focus + Vector2i(20, 20)) + Vector2(20, 20)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	dmover.global_position = WorldScale.chunk_origin(e_focus) + Vector2(20, 20)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var enemy_e2: Enemy = _enemy_in(dm.active_container(e_focus))
	var reloaded_hp: int = -1
	if enemy_e2 != null:
		reloaded_hp = (enemy_e2.get_node("HealthComponent") as HealthComponent).current_health
	ctx.check(reloaded_hp == 2,
		"C3b enemy-hp-persists: reloaded enemy spawned at stored HP 2 (not full " + str(e_full) + ") -- HealthComponent delta survived unload/reload via the store",
		"reloaded enemy HP was " + str(reloaded_hp) + ", expected 2 (HP delta lost)")

	# Kill the reloaded enemy (HP -> 0), round-trip, and assert it is gone for good.
	if enemy_e2 != null:
		(enemy_e2.get_node("HealthComponent") as HealthComponent).take_damage(2)  # -> 0 -> died
	await ctx.tree.physics_frame
	dmover.global_position = WorldScale.chunk_origin(e_focus + Vector2i(20, 20)) + Vector2(20, 20)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	dmover.global_position = WorldScale.chunk_origin(e_focus) + Vector2(20, 20)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(_enemy_in(dm.active_container(e_focus)) == null,
		"C3b killed-enemy-stays-gone: a killed enemy does NOT respawn on reload (entry marked gone via hp<=0 capture)",
		"a killed enemy reappeared on reload")

	# --- Store is DATA, not nodes --------------------------------------------
	# After roaming several chunks and returning, the LIVE active set is still the bounded 9;
	# meanwhile _store retains ChunkData for every visited coord (incl. the mutated focuses) as
	# cold data -- store growth added ZERO resident chunk Nodes.
	ctx.check(dm.active_chunk_count() == 9,
		"C3b store-is-data-not-nodes: live active set still bounded at 9 chunks after all the roaming (store growth added ZERO resident chunk Nodes)",
		"active set drifted from the load_radius 1 bound (" + str(dm.active_chunk_count()) + " != 9)")
	ctx.check(dm.has_stored(m_focus) and dm.has_stored(e_focus) and dm.stored_chunk_count() > dm.active_chunk_count(),
		"C3b store retention: _store holds ChunkData for visited coords incl. " + str(m_focus) + " and " + str(e_focus) + " (stored " + str(dm.stored_chunk_count()) + " > active " + str(dm.active_chunk_count()) + ") -- cold DATA that carried the deltas, not Nodes",
		"store did not retain visited coords as cold data (stored " + str(dm.stored_chunk_count()) + ", active " + str(dm.active_chunk_count()) + ")")

	dm.queue_free()
	dmover.queue_free()
	await ctx.tree.physics_frame



## Sentinel returned by _find_chunk when no matching chunk is found in the scan window.
const _SCAN_MISS: int = -999999


## Scan a bounded coord window for a chunk whose deterministic ChunkGenerator baseline has at
## least `min_minerals` mineral entries and (if `want_enemy`) an enemy entry, at Chebyshev
## distance >= `min_dist` from `avoid` (pass Vector2i(_SCAN_MISS, _SCAN_MISS) to disable the
## avoid filter). Returns its coord, or Vector2i(_SCAN_MISS, _SCAN_MISS) if none in range.
## Deterministic given the seed.
func _find_chunk(seed_val: int, min_minerals: int, want_enemy: bool, avoid: Vector2i, min_dist: int) -> Vector2i:
	for cx in range(0, 40):
		for cy in range(0, 40):
			var c: Vector2i = Vector2i(cx, cy)
			if avoid.x != _SCAN_MISS and maxi(absi(c.x - avoid.x), absi(c.y - avoid.y)) < min_dist:
				continue
			var cd: ChunkData = ChunkGenerator.generate(c, seed_val)
			var minerals: int = 0
			var has_enemy: bool = false
			for e in cd.entries:
				match int(e["type"]):
					ChunkData.Kind.MINERAL: minerals += 1
					ChunkData.Kind.ENEMY: has_enemy = true
			if minerals >= min_minerals and (has_enemy or not want_enemy):
				return c
	return Vector2i(_SCAN_MISS, _SCAN_MISS)


## The live Rock instances directly under a chunk container (empty if the container is null).
func _rocks_in(container: Node2D) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is Rock:
			out.append(child)
	return out


## The first live Enemy instance under a chunk container, or null (also null if container null).
func _enemy_in(container: Node2D) -> Enemy:
	if container == null:
		return null
	for child in container.get_children():
		if child is Enemy:
			return child as Enemy
	return null


## Sum the direct-child count of every active chunk container under the manager -- the
## live content-ROOT population (one root per ChunkData entry: a Tree/Rock/Enemy scene
## root). Each root is itself a heavy subtree, but their COUNT still equals the total
## entry count across active chunks, so a same-center round trip must return it to
## baseline exactly. The deep per-node guarantee is covered separately by
## Performance.OBJECT_NODE_COUNT. Used by the zero-orphan-leak check.
func _count_content_roots(manager: ChunkManager) -> int:
	var total: int = 0
	for container in manager.get_children():
		total += container.get_child_count()
	return total

# Verified against: Godot 4.7.1 (2026-07-17)
