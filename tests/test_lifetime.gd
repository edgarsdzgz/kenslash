class_name TestLifetime extends RefCounted
## Milestone E3b lifetime cull (design-items.md "Lifetime / cull"): a Drop despawns after its
## `lifetime` (default 300s = 5 REAL-minutes, tunable) -- the anti-Project-Zomboid cull that
## keeps ground litter bounded (patterns/persistent-world-scaling-pitfalls.md). Aging rides the
## Drop's own _physics_process; because a live Drop only exists as a node while its chunk is
## active, that inherently ages "only while loaded". This module is PURE CULL -- no player, no
## magnet. Chunk-persistence (resume aging on reload, E3c) is NOT exercised here.
##
## Self-contained: drops live under a private holder parented to ctx.tree.root (so their
## _physics_process actually runs), in a REMOTE coordinate region far from every other module's
## content and players -- mirroring how test_pickup isolates at ~12000,12000 -- so no stray E3a
## magnet could ever reach these drops. Frame counts are derived from the physics tick rate so
## the timing is deterministic headless, with margin so the run does not flake.

const WOOD: ItemData = preload("res://data/wood.tres")
const DROP_SCENE: PackedScene = preload("res://world/drop.tscn")

## A remote base coordinate, well beyond any other module's content, so nothing here interacts
## with (or is reached by) another test's players or drops.
const BASE: Vector2 = Vector2(-14000.0, -14000.0)

## A SHORT lifetime (well under one physics second) so the despawn happens within a handful of
## deterministic physics frames instead of the real 300s default.
const SHORT_LIFETIME: float = 0.1
## A slightly longer (but still short) lifetime, used only for the ordering/tunability check.
const MID_LIFETIME: float = 0.3


func run(ctx: TestContext) -> void:
	print("[lifetime] --- E3b lifetime cull: despawn at lifetime, alive before, tunable order ---")
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	# Derive frame counts from the actual physics tick so the timing is exact headless. A drop
	# with SHORT_LIFETIME needs ceil(SHORT_LIFETIME * tps) frames to reach its lifetime; step a
	# few extra so we are comfortably PAST it (0.1s -> ~6 frames; STEP_FRAMES ~12 = ~0.2s). That
	# same 0.2s is still astronomically short of the 300s default, so "alive before lifetime"
	# stays a real assertion rather than a trivially-true one.
	var tps: int = Engine.physics_ticks_per_second
	var short_frames: int = int(ceil(SHORT_LIFETIME * float(tps)))
	var step_frames: int = short_frames + 6

	# --- Despawn at lifetime: a SHORT-lifetime drop is freed after enough frames pass ---------
	var doomed: Drop = _make_drop(holder, SHORT_LIFETIME, BASE)
	var despawned: bool = false
	for _i in range(step_frames):
		await ctx.tree.physics_frame
		if _is_gone(doomed):
			despawned = true
			break
	ctx.check(despawned,
		"short-lifetime drop (" + str(SHORT_LIFETIME) + "s) despawned within " + str(step_frames) + " physics frames",
		"short-lifetime drop still present after " + str(step_frames) + " physics frames (valid=" + str(is_instance_valid(doomed)) + ")")

	# --- Alive before lifetime: a default 300s drop survives the SAME number of frames ---------
	var survivor: Drop = _make_drop(holder, 300.0, BASE + Vector2(200.0, 0.0))
	for _i in range(step_frames):
		await ctx.tree.physics_frame
	ctx.check(is_instance_valid(survivor) and not survivor.is_queued_for_deletion(),
		"default-lifetime drop (300s) is STILL alive after " + str(step_frames) + " physics frames (aged only ~" + str(step_frames) + "/" + str(tps) + "s, far below 300s)",
		"default-lifetime drop wrongly despawned after " + str(step_frames) + " frames")

	# --- Tunability / order: of two short drops, the SHORTER lifetime frees FIRST --------------
	# 0.1s (~6 frames) vs 0.3s (~18 frames). After step_frames (~12 = ~0.2s) the 0.1s drop is
	# past its lifetime and gone, while the 0.3s drop has NOT yet reached its lifetime.
	var sooner: Drop = _make_drop(holder, SHORT_LIFETIME, BASE + Vector2(400.0, 0.0))
	var later: Drop = _make_drop(holder, MID_LIFETIME, BASE + Vector2(600.0, 0.0))
	for _i in range(step_frames):
		await ctx.tree.physics_frame
	ctx.check(_is_gone(sooner) and is_instance_valid(later) and not later.is_queued_for_deletion(),
		"tunable lifetime respected: the " + str(SHORT_LIFETIME) + "s drop freed first while the " + str(MID_LIFETIME) + "s drop is still alive",
		"lifetime ordering wrong (sooner gone=" + str(_is_gone(sooner)) + ", later valid=" + str(is_instance_valid(later)) + ")")

	# --- Teardown: free the private holder (any surviving drops) so nothing leaks downstream ---
	holder.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## Instantiate a Drop carrying 1 Wood with the given `lifetime`, parented under the private
## holder (so its _physics_process runs) at world position `at`. add_child is immediate here
## (test code, not mid-signal), so _ready runs before the next physics frame; global_position is
## set right after so the drop is placed exactly. Aging starts on the first physics frame.
func _make_drop(holder: Node2D, lifetime: float, at: Vector2) -> Drop:
	var drop: Drop = DROP_SCENE.instantiate()
	drop.setup(WOOD, 1)
	drop.lifetime = lifetime
	holder.add_child(drop)
	drop.global_position = at
	return drop


## True once a drop has despawned -- either fully freed (invalid) or queued for deletion this
## frame. The parameter is intentionally UNTYPED: once a drop is freed, passing it to a
## `Drop`-typed parameter raises a "previously freed" type-check error before the body runs, so
## we take it loosely and let is_instance_valid short-circuit before any method call. Mirrors the
## freed-mid-iteration guard the magnet uses in player.gd _process_pickups.
func _is_gone(drop) -> bool:
	return not is_instance_valid(drop) or drop.is_queued_for_deletion()

# Verified against: Godot 4.7.1 (2026-07-18)
