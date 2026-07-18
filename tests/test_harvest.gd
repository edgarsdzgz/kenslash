class_name TestHarvest extends RefCounted
## Milestone E2 harvest yield (design-items.md "Harvest yield"): a harvest now PRODUCES
## visible Drop entities. Self-contained -- instantiates its OWN world/tree.tscn +
## world/rock.tscn under private container Node2Ds (never the shared main.tscn refs the
## ordered combat/durability legs depend on), and drives each target's Material directly
## (deterministic, no fragile arc-timing) to assert the drops that spawn:
##   * TREE FELL -> a burst of exactly yield_amount Wood drops (count 1 each), near the
##     stump, and the tree freed;
##   * NOTHING UNTIL FELLED -- a partial chop (integrity still > 0) yields ZERO drops;
##   * MINERAL PER HIT -- N affecting mines on an integrity-N rock -> exactly N Stone drops,
##     rock freed after the last;
##   * BAND-C WHIFF -- a too-hard rock struck by a weak pick (no durability_changed) yields
##     ZERO stone, driven through the REAL Hurtbox resolution;
##   * DROP CARRIES COLOR -- a spawned drop's Body tint matches item.color.
## Drops are visual + data ONLY in E2 (no pickup / lifetime / persistence -- that is E3).

const WOOD: ItemData = preload("res://data/wood.tres")
const STONE: ItemData = preload("res://data/stone.tres")
const TREE_SCENE: PackedScene = preload("res://world/tree.tscn")
const ROCK_SCENE: PackedScene = preload("res://world/rock.tscn")


func run(ctx: TestContext) -> void:
	print("[harvest] --- E2 harvest yield: fell-burst wood, per-hit stone, drops visible ---")

	# --- TREE FELL -> WOOD BURST ---------------------------------------------
	# A self-contained tree under its own holder. Drive its integrity to 0 in one blow
	# (Material.wear to current) -> broke -> _on_broke bursts yield_amount count-1 wood drops
	# as siblings under the holder. add_child is deferred, so settle a couple of frames.
	var tree_holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(tree_holder)
	var tree_node: StaticBody2D = TREE_SCENE.instantiate()
	tree_holder.add_child(tree_node)
	tree_node.global_position = Vector2(500, 500)
	await ctx.tree.physics_frame
	var tree_mat: DurabilityComponent = tree_node.get_node("Material") as DurabilityComponent
	var yield_amount: int = int(tree_node.get("yield_amount"))
	var tree_pos: Vector2 = tree_node.global_position
	tree_mat.wear(tree_mat.current_durability)  # integrity -> 0 -> felled
	await ctx.tree.physics_frame  # let the deferred add_child + positioning + queue_free resolve
	await ctx.tree.physics_frame

	var wood_drops: Array = _drops(tree_holder)
	ctx.check(wood_drops.size() == yield_amount,
		"tree fell burst exactly yield_amount Wood drops (" + str(wood_drops.size()) + " == " + str(yield_amount) + ")",
		"tree fell drop count wrong (" + str(wood_drops.size()) + " != " + str(yield_amount) + ")")

	var wood_ok: bool = true
	var near_ok: bool = true
	for d in wood_drops:
		if d.item != WOOD or d.count != 1:
			wood_ok = false
		if d.global_position.distance_to(tree_pos) > 64.0:
			near_ok = false
	ctx.check(wood_ok,
		"each felled-tree drop carries Wood x1",
		"felled-tree drop item/count wrong (expected Wood x1)")
	ctx.check(near_ok,
		"felled-tree wood drops landed near the stump (<= 64 px)",
		"felled-tree wood drops landed too far from the stump")
	# The felled tree now plays a tip-over animation before freeing, so wait it out (watchdog)
	# instead of assuming an immediate queue_free.
	var fell_watchdog: SceneTreeTimer = ctx.tree.create_timer(3.0)
	while is_instance_valid(tree_node) and fell_watchdog.time_left > 0.0:
		await ctx.tree.physics_frame
	ctx.check(not is_instance_valid(tree_node),
		"tree freed after the fell animation",
		"tree not freed after felling")

	# --- DROP CARRIES COLOR (reuse a live wood drop from the burst above) -----
	var color_ok: bool = false
	if wood_drops.size() > 0:
		var body: Polygon2D = (wood_drops[0] as Drop).get_node("Body") as Polygon2D
		color_ok = body.color == WOOD.color
	ctx.check(color_ok,
		"a spawned Wood drop's Body tint matches item.color (" + str(WOOD.color) + ")",
		"Wood drop Body tint does not match item.color")

	# --- NOTHING UNTIL FELLED ------------------------------------------------
	# A fresh tree, chopped only partway (integrity reduced but > 0) -> ZERO drops. The
	# tree's durability_changed handler only prints; drops come solely from _on_broke.
	var tree2_holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(tree2_holder)
	var tree2: StaticBody2D = TREE_SCENE.instantiate()
	tree2_holder.add_child(tree2)
	tree2.global_position = Vector2(-500, -500)
	await ctx.tree.physics_frame
	var tree2_mat: DurabilityComponent = tree2.get_node("Material") as DurabilityComponent
	tree2_mat.wear(1)  # partial chop only
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(tree2_mat.current_durability > 0 and _drops(tree2_holder).size() == 0,
		"partial chop (integrity " + str(tree2_mat.current_durability) + " > 0) yielded ZERO drops -- nothing until felled",
		"partial chop wrongly spawned " + str(_drops(tree2_holder).size()) + " drop(s) before felling")

	# --- MINERAL PER HIT -----------------------------------------------------
	# A fresh rock mined one affecting pick at a time (Material.wear(1) each) -> one Stone
	# drop per hit; the final pick reaches 0 (broke -> queue_free) yet still yields its stone
	# via durability_changed. Assert exactly N stones for N hits, and the rock freed.
	var rock_holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(rock_holder)
	var rock_node: Rock = ROCK_SCENE.instantiate()
	rock_holder.add_child(rock_node)
	rock_node.global_position = Vector2(1000, 0)
	await ctx.tree.physics_frame
	var rock_mat: DurabilityComponent = rock_node.get_node("Material") as DurabilityComponent
	var n_hits: int = rock_mat.current_durability  # integrity N
	for _i in range(n_hits):
		rock_mat.wear(1)
		await ctx.tree.physics_frame
	await ctx.tree.physics_frame  # settle the final deferred add_child + the rock's queue_free

	var stone_drops: Array = _drops(rock_holder)
	ctx.check(stone_drops.size() == n_hits,
		"mineral yielded one Stone per affecting mine (" + str(stone_drops.size()) + " == " + str(n_hits) + " hits)",
		"mineral per-hit drop count wrong (" + str(stone_drops.size()) + " != " + str(n_hits) + ")")
	var stone_ok: bool = true
	for d in stone_drops:
		if d.item != STONE or d.count != 1:
			stone_ok = false
	ctx.check(stone_ok,
		"each mined-mineral drop carries Stone x1",
		"mined-mineral drop item/count wrong (expected Stone x1)")
	ctx.check(not is_instance_valid(rock_node),
		"rock freed after the final mine",
		"rock not freed after mining out")

	# --- BAND-C WHIFF YIELDS NOTHING -----------------------------------------
	# A too-hard rock (hardness 12) struck by a weak MINE tool (power 2): over = 10 >
	# threshold -> Band C -> affects_target false, so material_durability.wear is never
	# called, durability_changed never fires, and no stone drops. Driven through the REAL
	# Hurtbox resolution (its _on_area_entered), not a fabricated Material.wear -- so the
	# gate itself is what suppresses the yield.
	var obs_holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(obs_holder)
	var obs: Rock = ROCK_SCENE.instantiate()
	obs.hardness = 12  # obsidian-hard: too hard for the weak pick
	obs_holder.add_child(obs)
	obs.global_position = Vector2(-1000, 0)
	await ctx.tree.physics_frame
	var obs_hurt: Hurtbox = obs.get_node("Hurtbox") as Hurtbox
	var weak: Hitbox = Hitbox.new()
	weak.power = 2
	weak.break_threshold = 1
	weak.wear_max = 4
	weak.harvest_type = Harvest.Type.MINE
	var weak_dura: DurabilityComponent = DurabilityComponent.new()
	weak.durability = weak_dura
	weak.add_child(weak_dura)
	obs_holder.add_child(weak)
	await ctx.tree.physics_frame
	obs_hurt._on_area_entered(weak)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(_drops(obs_holder).size() == 0,
		"Band-C whiff (too-hard rock, weak pick) yielded ZERO stone -- no affecting mine, no durability_changed",
		"Band-C whiff wrongly spawned " + str(_drops(obs_holder).size()) + " stone drop(s)")

	# --- Teardown: free the private holders (and their remaining drops) -------
	tree_holder.queue_free()
	tree2_holder.queue_free()
	rock_holder.queue_free()
	obs_holder.queue_free()
	await ctx.tree.physics_frame


## The live Drop instances directly under a holder node (empty if none).
func _drops(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child is Drop:
			out.append(child)
	return out

# Verified against: Godot 4.7.1 (2026-07-18)
