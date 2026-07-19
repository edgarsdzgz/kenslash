class_name TestEncumbrance extends RefCounted
## design-weight.md Phase 2: the encumbrance movement slow-down proven end-to-end through the
## REAL player controller (not just the Inventory math -- that is unit-tested in test_units.gd).
## Two freshly instantiated players are driven RIGHT via input_override (the multiplayer/test
## seam) for a fixed number of physics frames: one at the STARTING loadout (7.5 / 50, ratio 0.15
## -> factor 1.0, full speed) and one stuffed OVER capacity with stone (ratio > 2 -> factor 0.4,
## the clamped floor). The over-capacity player must travel measurably LESS far, while the
## at/under-capacity player runs at the full unencumbered factor -- so every EXISTING movement leg
## (all under capacity) is unaffected. Self-contained: builds + frees its own players at remote
## coords, never touches the shared main.tscn.

## Physics frames to drive each player. Long enough that both reach terminal speed and the 1.0 vs
## 0.4 factor opens a wide distance gap, short enough that no distant body can wander into range.
const DRIVE_FRAMES: int = 40


func run(ctx: TestContext) -> void:
	print("[encumbrance] --- weight slow-down: over-capacity player travels less far ---")
	var player_scene: PackedScene = load("res://player/player.tscn")
	ctx.check(player_scene != null,
		"player.tscn loads (for the encumbrance movement legs)",
		"player.tscn failed to load")
	if player_scene == null:
		return
	var STONE: ItemData = load("res://data/stone.tres")

	# Unencumbered: the starting loadout only (7.5 / 50). Parked far from every other body so
	# nothing collides with or chases it during the drive. Magnet off -- no stray pickups.
	var light: Player = player_scene.instantiate() as Player
	light.pickup_radius = 0.0
	ctx.tree.root.add_child(light)
	light.global_position = Vector2(12000, 12000)

	# Over capacity: the same loadout + 100 stone (100.0) -> total 107.5 / 50, ratio > 2, so the
	# encumbrance factor sits at its 0.4 floor. add_item runs AFTER add_child (so _ready wired the
	# Equipment/inventory first). Parked far in the opposite direction.
	var heavy: Player = player_scene.instantiate() as Player
	heavy.pickup_radius = 0.0
	ctx.tree.root.add_child(heavy)
	heavy.global_position = Vector2(-12000, -12000)
	heavy.inventory.add_item(STONE, 100)

	# Let _ready wiring settle so both inventories are fully populated before we read factors.
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	# The controlling factors: full speed at/under capacity, floored when overloaded.
	ctx.check(light.inventory.weight_ratio() <= 1.0 and is_equal_approx(light.inventory.encumbrance_factor(), 1.0),
		"under-capacity player runs at factor 1.0 (loadout ratio " + str(light.inventory.weight_ratio()) + ")",
		"under-capacity factor not 1.0 (factor " + str(light.inventory.encumbrance_factor()) + ")")
	ctx.check(heavy.inventory.weight_ratio() > 1.0 and is_equal_approx(heavy.inventory.encumbrance_factor(), 0.4),
		"over-capacity player is encumbered to the 0.4 floor (ratio " + str(heavy.inventory.weight_ratio()) + ")",
		"over-capacity factor not floored (ratio " + str(heavy.inventory.weight_ratio()) + " factor " + str(heavy.inventory.encumbrance_factor()) + ")")

	# Drive both RIGHT for the same number of frames and compare distance travelled.
	var light_input: FrameInput = FrameInput.new()
	light_input.move = Vector2.RIGHT
	light.input_override = light_input
	var heavy_input: FrameInput = FrameInput.new()
	heavy_input.move = Vector2.RIGHT
	heavy.input_override = heavy_input

	var light_start: float = light.global_position.x
	var heavy_start: float = heavy.global_position.x
	for _i in range(DRIVE_FRAMES):
		await ctx.tree.physics_frame
	var light_dx: float = light.global_position.x - light_start
	var heavy_dx: float = heavy.global_position.x - heavy_start

	ctx.check(light_dx > 1.0 and heavy_dx > 1.0,
		"both players moved right under injected input (light " + str(int(light_dx)) + ", heavy " + str(int(heavy_dx)) + ")",
		"a player failed to move (light " + str(int(light_dx)) + ", heavy " + str(int(heavy_dx)) + ")")
	# The factor gap is 1.0 vs 0.4, so the heavy player covers well under 60% of the light one's
	# distance -- a wide, unambiguous margin that will not flake on physics-timing jitter.
	ctx.check(heavy_dx < light_dx * 0.6,
		"over-capacity player travelled measurably LESS far (heavy " + str(int(heavy_dx)) + " < 0.6 * light " + str(int(light_dx)) + ")",
		"encumbrance did not slow the heavy player (heavy " + str(int(heavy_dx)) + " vs light " + str(int(light_dx)) + ")")

	light.input_override = null
	heavy.input_override = null
	light.queue_free()
	heavy.queue_free()
	await ctx.settle_idle()

# Verified against: Godot 4.7.1 (2026-07-19)
