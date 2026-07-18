class_name TestForage extends RefCounted
## Milestone E4 forageable bushes + the 'f'-interaction framework (design-items.md
## "Interaction 'f'"): a Bush is a plain Node2D (no collision) the player WALKS THROUGH; when
## the player is within the Interaction subsystem's reach a HUD prompt appears, and pressing
## the action button (the test drives the same public player.interact() path) harvests it --
## removing the bush instantly and adding Sticks + Fiber to the inventory.
##
## Self-contained: instantiates real player/player.tscn + world/bush.tscn under a private holder
## in a REMOTE coordinate region (far from every other module's content AND the shared main
## player, whose _interaction radius would otherwise reach in), so no cross-module interaction
## leaks. The HUD-prompt leg instantiates the shipped streaming_world.tscn (like test_hud) and
## first relocates its player to a spot with NO generated bush in reach, so the injected bush is
## the sole prompt driver -- deterministic given the fixed world seed.

const STICK: ItemData = preload("res://data/stick.tres")
const FIBER: ItemData = preload("res://data/fiber.tres")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const BUSH_SCENE: PackedScene = preload("res://world/bush.tscn")

## A remote base coordinate, well beyond any other module's content and any interact radius, so
## this scenario's players/bushes never reach (or are reached by) another test's entities.
const BASE: Vector2 = Vector2(-30000.0, -30000.0)


func run(ctx: TestContext) -> void:
	print("[forage] --- E4 forage bushes: proximity prompt, harvest yields Sticks+Fiber, walk-through, HUD prompt ---")
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	# --- Proximity prompt: in reach shows the verb, beyond reach shows nothing ---------------
	# p_near sits ON a bush (20 px < the ~40 px interact reach) -> "Harvest"; p_far is 2000 px
	# away with its own bush 200 px off (beyond reach) -> "". Step physics frames so each
	# player's _interaction.process() runs (setting the nearby node) before we read the prompt.
	var p_near: Player = _spawn_player(holder, BASE)
	var bush_near: Bush = _make_bush(holder, BASE + Vector2(20.0, 0.0))
	var p_far: Player = _spawn_player(holder, BASE + Vector2(2000.0, 0.0))
	var _bush_far: Bush = _make_bush(holder, BASE + Vector2(2200.0, 0.0))
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(p_near.interaction_prompt() == "Harvest",
		"player within reach of a bush reads the bush's verb via interaction_prompt() (\"" + p_near.interaction_prompt() + "\" == \"Harvest\")",
		"in-reach interaction_prompt() wrong (\"" + p_near.interaction_prompt() + "\")")
	ctx.check(p_far.interaction_prompt() == "",
		"player with the nearest bush BEYOND reach reads an empty interaction_prompt()",
		"out-of-reach interaction_prompt() should be empty (\"" + p_far.interaction_prompt() + "\")")

	# --- Harvest: gives Sticks + Fiber and removes the bush instantly ------------------------
	# p_near's nearby node is bush_near (set above). interact() -- the test-callable path the
	# action button also drives -- harvests it: the bush frees, and exactly yield_count_a Sticks
	# + yield_count_b Fiber land in the inventory.
	var want_stick: int = bush_near.yield_count_a
	var want_fiber: int = bush_near.yield_count_b
	p_near.interact()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(not is_instance_valid(bush_near),
		"harvest removed the bush instantly (queue_freed)",
		"bush was not freed by harvest")
	ctx.check(_count_of(p_near, STICK) == want_stick and _count_of(p_near, FIBER) == want_fiber,
		"harvest added exactly " + str(want_stick) + " Stick + " + str(want_fiber) + " Fiber to the inventory (stick=" + str(_count_of(p_near, STICK)) + ", fiber=" + str(_count_of(p_near, FIBER)) + ")",
		"harvest yield wrong (stick=" + str(_count_of(p_near, STICK)) + ", fiber=" + str(_count_of(p_near, FIBER)) + ")")

	# --- Walk-through: the bush has NO collision, so the player passes straight through it ----
	# Drive a fresh player RIGHT (via input_override, the FrameInput seam) at a bush 60 px ahead
	# for 60 frames. With no solid body on the bush, move_and_slide is never blocked, so the
	# player ends PAST the bush's x -- and the bush is untouched (no action button was pressed).
	var p_walk: Player = _spawn_player(holder, BASE + Vector2(4000.0, 0.0))
	var bush_block: Bush = _make_bush(holder, p_walk.global_position + Vector2(60.0, 0.0))
	var block_x: float = bush_block.global_position.x
	var fi: FrameInput = FrameInput.new()
	fi.move = Vector2.RIGHT
	fi.attack = false
	p_walk.input_override = fi
	for _i in range(60):
		await ctx.tree.physics_frame
	p_walk.input_override = null
	ctx.check(p_walk.global_position.x > block_x + 10.0 and is_instance_valid(bush_block),
		"player WALKED THROUGH the bush (ended past its x " + str(block_x) + " at " + str(p_walk.global_position.x) + ") -- no collision body blocked it, bush untouched",
		"player was blocked by the bush or the bush was disturbed (x=" + str(p_walk.global_position.x) + ", block_x=" + str(block_x) + ", bush_valid=" + str(is_instance_valid(bush_block)) + ")")

	# Done with the private-holder scenarios; free them before the streaming leg.
	holder.queue_free()
	await ctx.tree.physics_frame

	# --- HUD prompt shows the bound key + verb on the shipped streaming_world.tscn -----------
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	ctx.check(sw_scene != null,
		"streaming_world.tscn loads (hosts the E4 HUD prompt)",
		"streaming_world.tscn failed to load")
	if sw_scene == null:
		return
	var sw: Node2D = sw_scene.instantiate()
	ctx.tree.root.add_child(sw)
	var sw_player: Player = sw.get_node("Player") as Player
	var hud: Hud = sw.get_node("HUD") as Hud
	sw_player.set("pickup_radius", 0.0)  # no magnet interference (no drops here regardless)
	await ctx.settle_idle()

	# Relocate the player to a spot with NO generated bush in interact reach, so the injected
	# bush below is the SOLE prompt driver (deterministic for the fixed seed; nudge if occupied).
	var spot: Vector2 = Vector2(3000.0, 3000.0)
	sw_player.global_position = spot
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	await ctx.settle_idle()
	var tries: int = 0
	while hud.prompt_text() != "" and tries < 16:
		spot += Vector2(213.0, 149.0)
		sw_player.global_position = spot
		await ctx.tree.physics_frame
		await ctx.tree.physics_frame
		await ctx.settle_idle()
		tries += 1
	ctx.check(hud.prompt_text() == "",
		"HUD prompt is clear at a bush-free spot (baseline before injecting a bush)",
		"could not find a spot with no bush in reach (prompt \"" + hud.prompt_text() + "\")")

	# Inject a bush next to the player -> the HUD prompt shows "[<key>] Harvest".
	var sw_bush: Bush = BUSH_SCENE.instantiate()
	sw.add_child(sw_bush)
	sw_bush.global_position = spot + Vector2(15.0, 0.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	await ctx.settle_idle()
	ctx.check(hud.prompt_text().contains("Harvest") and hud.prompt_text().contains("[F]"),
		"HUD shows the interaction prompt with the bound key and verb (\"" + hud.prompt_text() + "\")",
		"HUD interaction prompt wrong (\"" + hud.prompt_text() + "\")")

	# Move the bush out of reach -> the prompt clears.
	sw_bush.global_position = spot + Vector2(6000.0, 0.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	await ctx.settle_idle()
	ctx.check(hud.prompt_text() == "",
		"HUD prompt CLEARS once the bush leaves interact reach (\"" + hud.prompt_text() + "\")",
		"HUD prompt did not clear when the bush moved away (\"" + hud.prompt_text() + "\")")

	sw.queue_free()
	await ctx.tree.physics_frame


## Instantiate a real Player at `at`, parented under the private holder so its _physics_process
## (and thus the interaction scan) actually runs. Returns the live instance.
func _spawn_player(holder: Node2D, at: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	holder.add_child(player)
	player.global_position = at
	return player


## Instantiate a Bush at world position `at` under the holder. add_child is immediate (test code,
## not mid-signal), so _ready runs and the bush joins the "interactables" group before the next
## physics frame; global_position is set right after so it is placed exactly.
func _make_bush(holder: Node2D, at: Vector2) -> Bush:
	var bush: Bush = BUSH_SCENE.instantiate() as Bush
	holder.add_child(bush)
	bush.global_position = at
	return bush


## Total count of `item` across every inventory slot (proves the yield actually landed).
func _count_of(player: Player, item: ItemData) -> int:
	var total: int = 0
	for i in range(player.inventory.slots.size()):
		if player.inventory.item_at(i) == item:
			total += player.inventory.count_at(i)
	return total

# Verified against: Godot 4.7.1 (2026-07-18)
