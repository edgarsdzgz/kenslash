class_name TestPickup extends RefCounted
## Milestone E3a magnetic auto-pickup (design-items.md "Drops -- Magnetic pickup"): a Drop
## within the player's pickup_radius slides toward the player and is grabbed on contact into
## the inventory (Stardew-style, no button). Self-contained -- instantiates real
## player/player.tscn instances plus world/drop.tscn drops under a private holder, positioned
## in a REMOTE coordinate region far from every other module's content (and the shared main
## player) so no cross-module magnet reaches in or out. The pickup runs in the player's
## _physics_process, so the scenarios step physics frames between setup and assertion.
## E3a is pickup ONLY -- the 5-min lifetime cull (E3b) and chunk-persistence (E3c) are later.

const WOOD: ItemData = preload("res://data/wood.tres")
const STONE: ItemData = preload("res://data/stone.tres")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const DROP_SCENE: PackedScene = preload("res://world/drop.tscn")

## A remote base coordinate, well beyond any other module's content and pickup_radius, so this
## scenario's magnet cannot reach (or be reached by) another test's player or drops.
const BASE: Vector2 = Vector2(12000.0, 12000.0)


func run(ctx: TestContext) -> void:
	print("[pickup] --- E3a magnetic auto-pickup: pull + grab, out-of-range ignored, stacking, full ---")
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	# Three players in the remote region, spaced 1000px apart (>> pickup_radius) so each only
	# ever reaches its OWN drops even though every magnet scans the shared "drops" group.
	var p_pull: Player = _spawn_player(holder, BASE)
	var p_stack: Player = _spawn_player(holder, BASE + Vector2(1000.0, 0.0))
	var p_full: Player = _spawn_player(holder, BASE + Vector2(2000.0, 0.0))
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame  # let each _ready wire its Equipment + join groups

	# --- Magnet pull + grab, and an out-of-range drop ignored --------------------------
	# In-range wood at +50 (radius 72, grab 12): must be pulled measurably closer then grabbed
	# (freed) with 1 Wood added. A STONE at +200 (out of range) must NOT move or be collected.
	var far_drop: Drop = _make_drop(holder, STONE, 1, BASE + Vector2(200.0, 0.0))
	var far_pos: Vector2 = far_drop.global_position
	var pull_drop: Drop = _make_drop(holder, WOOD, 1, BASE + Vector2(50.0, 0.0))
	var gap0: float = p_pull.global_position.distance_to(pull_drop.global_position)  # 50, pre-physics
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var gap1: float = gap0
	if is_instance_valid(pull_drop) and not pull_drop.is_queued_for_deletion():
		gap1 = p_pull.global_position.distance_to(pull_drop.global_position)
	ctx.check(gap1 < gap0,
		"in-range drop pulled measurably closer over physics frames (" + str(gap0) + " -> " + str(gap1) + " px)",
		"in-range drop did not move closer (" + str(gap0) + " -> " + str(gap1) + " px)")

	var grabbed: bool = false
	for _i in range(40):
		await ctx.tree.physics_frame
		if not is_instance_valid(pull_drop) or pull_drop.is_queued_for_deletion():
			grabbed = true
			break
	ctx.check(grabbed and _count_of(p_pull, WOOD) == 1,
		"in-range wood drop collected (freed) and 1 Wood landed in the inventory",
		"in-range wood drop not collected (grabbed=" + str(grabbed) + ", wood=" + str(_count_of(p_pull, WOOD)) + ")")

	ctx.check(is_instance_valid(far_drop) and far_drop.global_position == far_pos and _count_of(p_pull, STONE) == 0,
		"out-of-range drop (200 px > radius) neither moved nor was collected",
		"out-of-range drop was disturbed (valid=" + str(is_instance_valid(far_drop)) + ", stone=" + str(_count_of(p_pull, STONE)) + ")")

	# --- Stacking on pickup: two Wood drops (5 + 7) merge into a single stack of 12 --------
	var stack_base: Vector2 = p_stack.global_position
	_make_drop(holder, WOOD, 5, stack_base + Vector2(40.0, 0.0))
	_make_drop(holder, WOOD, 7, stack_base + Vector2(0.0, 40.0))
	for _i in range(40):
		await ctx.tree.physics_frame
		if _count_of(p_stack, WOOD) == 12 and _slots_with(p_stack, WOOD) == 1:
			break
	ctx.check(_count_of(p_stack, WOOD) == 12 and _slots_with(p_stack, WOOD) == 1,
		"two Wood drops (5 + 7) collected into a SINGLE stack of 12 (add_item merge)",
		"stacking on pickup wrong (wood=" + str(_count_of(p_stack, WOOD)) + ", slots=" + str(_slots_with(p_stack, WOOD)) + ")")

	# --- Inventory-full leaves the drop untouched -----------------------------------------
	# Slots 0-2 hold the auto-populated tools (max_stack 1); fill the 12 remaining slots with
	# full Wood stacks (255 each) so nothing can merge and no slot is empty. A Stone in range
	# then overflows entirely: collect() returns count -> the drop is left, inventory unchanged.
	p_full.inventory.add_item(WOOD, 255 * 12)
	var full_wood: int = _count_of(p_full, WOOD)
	var stone_drop: Drop = _make_drop(holder, STONE, 1, p_full.global_position + Vector2(30.0, 0.0))
	for _i in range(30):
		await ctx.tree.physics_frame
	ctx.check(is_instance_valid(stone_drop) and not stone_drop.is_queued_for_deletion()
			and _count_of(p_full, STONE) == 0 and _count_of(p_full, WOOD) == full_wood,
		"inventory-full: an in-range Stone drop is NOT collected and the inventory is unchanged (stone stays " + str(_count_of(p_full, STONE)) + ", wood " + str(_count_of(p_full, WOOD)) + ")",
		"inventory-full drop mishandled (valid=" + str(is_instance_valid(stone_drop)) + ", stone=" + str(_count_of(p_full, STONE)) + ", wood=" + str(_count_of(p_full, WOOD)) + ")")

	# --- Teardown: free the private holder (players + any remaining drops) so nothing leaks -
	holder.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## Instantiate a real Player at `at`, parented under the private holder so its _physics_process
## (and thus the magnet) actually runs. Returns the live instance.
func _spawn_player(holder: Node2D, at: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	holder.add_child(player)
	player.global_position = at
	return player


## Instantiate a Drop carrying `item` x `count` at world position `at`. add_child is immediate
## here (test code, not mid-signal), so _ready runs and the Drop joins the "drops" group before
## the next physics frame; global_position is set right after so it is placed exactly.
func _make_drop(holder: Node2D, item: ItemData, count: int, at: Vector2) -> Drop:
	var drop: Drop = DROP_SCENE.instantiate()
	drop.setup(item, count)
	holder.add_child(drop)
	drop.global_position = at
	return drop


## Total count of `item` across every inventory slot (proves the item actually landed).
func _count_of(player: Player, item: ItemData) -> int:
	var total: int = 0
	for i in range(player.inventory.slots.size()):
		if player.inventory.item_at(i) == item:
			total += player.inventory.count_at(i)
	return total


## How many distinct slots hold `item` (1 proves a single merged stack, not scattered slots).
func _slots_with(player: Player, item: ItemData) -> int:
	var n: int = 0
	for i in range(player.inventory.slots.size()):
		if player.inventory.item_at(i) == item:
			n += 1
	return n

# Verified against: Godot 4.7.1 (2026-07-18)
