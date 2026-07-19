class_name TestPebble extends RefCounted
## Milestone E4 forageable PEBBLES on the SAME 'f'-interaction framework as the bush
## (design-items.md "Interaction 'f'"): a Pebble is a plain Node2D (no collision) the player
## WALKS THROUGH; when the player is within the Interaction subsystem's reach a HUD prompt
## appears ("Gather"), and pressing the action button (the test drives the same public
## player.interact() path) gathers it -- removing the pebble instantly and adding exactly 1
## Stone to the inventory. No pickaxe needed (the big minable Rock still is).
##
## Self-contained: instantiates real player/player.tscn + world/pebble.tscn under a private
## holder in a REMOTE coordinate region -- far from every other module's content AND the shared
## main player, whose _interaction radius would otherwise reach in -- so no cross-module
## interaction leaks. Mirrors tests/test_forage.gd; distinct BASE keeps the two isolated.

const STONE: ItemData = preload("res://data/stone.tres")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const PEBBLE_SCENE: PackedScene = preload("res://world/pebble.tscn")

## A remote base coordinate, well beyond any other module's content (incl. test_forage's
## -30000 region) and any interact radius, so this scenario never reaches another test's entities.
const BASE: Vector2 = Vector2(-60000.0, -60000.0)


func run(ctx: TestContext) -> void:
	print("[pebble] --- E4 forage pebbles: proximity prompt, gather yields 1 Stone, walk-through ---")
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	# --- Proximity prompt: in reach shows the verb, beyond reach shows nothing ---------------
	# p_near sits ON a pebble (20 px < the ~40 px interact reach) -> "Gather"; p_far is 2000 px
	# away with its own pebble 200 px off (beyond reach) -> "". Step physics frames so each
	# player's _interaction.process() runs (setting the nearby node) before we read the prompt.
	var p_near: Player = _spawn_player(holder, BASE)
	var pebble_near: Pebble = _make_pebble(holder, BASE + Vector2(20.0, 0.0))
	var p_far: Player = _spawn_player(holder, BASE + Vector2(2000.0, 0.0))
	var _pebble_far: Pebble = _make_pebble(holder, BASE + Vector2(2200.0, 0.0))
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(p_near.interaction_prompt() == "Gather",
		"player within reach of a pebble reads the pebble's verb via interaction_prompt() (\"" + p_near.interaction_prompt() + "\" == \"Gather\")",
		"in-reach interaction_prompt() wrong (\"" + p_near.interaction_prompt() + "\")")
	ctx.check(p_far.interaction_prompt() == "",
		"player with the nearest pebble BEYOND reach reads an empty interaction_prompt()",
		"out-of-reach interaction_prompt() should be empty (\"" + p_far.interaction_prompt() + "\")")

	# --- Gather: gives exactly 1 Stone and removes the pebble instantly ----------------------
	# p_near's nearby node is pebble_near (set above). interact() -- the test-callable path the
	# action button also drives -- gathers it: the pebble frees, and exactly yield_count Stone
	# lands in the inventory (one yield, unlike the bush's two).
	var want_stone: int = pebble_near.yield_count
	p_near.interact()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(not is_instance_valid(pebble_near),
		"gather removed the pebble instantly (queue_freed)",
		"pebble was not freed by gather")
	ctx.check(_count_of(p_near, STONE) == want_stone and want_stone == 1,
		"gather added exactly " + str(want_stone) + " Stone to the inventory (stone=" + str(_count_of(p_near, STONE)) + ")",
		"gather yield wrong (stone=" + str(_count_of(p_near, STONE)) + ", want " + str(want_stone) + ")")

	# --- Walk-through: the pebble has NO collision, so the player passes straight through it --
	# Drive a fresh player RIGHT (via input_override, the FrameInput seam) at a pebble 60 px
	# ahead for 60 frames. With no solid body on the pebble, move_and_slide is never blocked, so
	# the player ends PAST the pebble's x -- and the pebble is untouched (no action button press).
	var p_walk: Player = _spawn_player(holder, BASE + Vector2(4000.0, 0.0))
	var pebble_block: Pebble = _make_pebble(holder, p_walk.global_position + Vector2(60.0, 0.0))
	var block_x: float = pebble_block.global_position.x
	var fi: FrameInput = FrameInput.new()
	fi.move = Vector2.RIGHT
	fi.attack = false
	p_walk.input_override = fi
	for _i in range(60):
		await ctx.tree.physics_frame
	p_walk.input_override = null
	ctx.check(p_walk.global_position.x > block_x + 10.0 and is_instance_valid(pebble_block),
		"player WALKED THROUGH the pebble (ended past its x " + str(block_x) + " at " + str(p_walk.global_position.x) + ") -- no collision body blocked it, pebble untouched",
		"player was blocked by the pebble or the pebble was disturbed (x=" + str(p_walk.global_position.x) + ", block_x=" + str(block_x) + ", pebble_valid=" + str(is_instance_valid(pebble_block)) + ")")

	holder.queue_free()
	await ctx.tree.physics_frame


## Instantiate a real Player at `at`, parented under the private holder so its _physics_process
## (and thus the interaction scan) actually runs. Returns the live instance.
func _spawn_player(holder: Node2D, at: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	holder.add_child(player)
	player.global_position = at
	return player


## Instantiate a Pebble at world position `at` under the holder. add_child is immediate (test
## code, not mid-signal), so _ready runs and the pebble joins the "interactables" group before
## the next physics frame; global_position is set right after so it is placed exactly.
func _make_pebble(holder: Node2D, at: Vector2) -> Pebble:
	var pebble: Pebble = PEBBLE_SCENE.instantiate() as Pebble
	holder.add_child(pebble)
	pebble.global_position = at
	return pebble


## Total count of `item` across every inventory slot (proves the yield actually landed).
func _count_of(player: Player, item: ItemData) -> int:
	var total: int = 0
	for i in range(player.inventory.slots.size()):
		if player.inventory.item_at(i) == item:
			total += player.inventory.count_at(i)
	return total

# Verified against: Godot 4.7.1 (2026-07-19)
