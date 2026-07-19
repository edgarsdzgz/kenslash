class_name TestEncumbrance extends RefCounted
## design-weight.md Phase 2: the encumbrance movement slow-down proven end-to-end through the
## REAL player controller, PLUS the discrete-tier factor/tier math (the GENTLE scheme). The unit
## leg asserts encumbrance_factor()/encumbrance_tier() across every tier band and its boundaries;
## the movement leg drives two freshly instantiated players RIGHT via input_override (the
## multiplayer/test seam) for a fixed number of physics frames: one at the STARTING loadout
## (7.5 / 50, ratio 0.15 -> NORMAL, factor 1.0, full speed) and one stuffed deep into ULTRA with
## stone (ratio > 3 -> factor 0.25). The over-capacity player must travel measurably LESS far,
## while the at/under-capacity player runs at the full unencumbered factor -- so every EXISTING
## movement leg (all under capacity) is unaffected. Self-contained: builds + frees its own players
## at remote coords, never touches the shared main.tscn.

## Physics frames to drive each player. Long enough that both reach terminal speed and the 1.0 vs
## 0.25 factor opens a wide distance gap, short enough that no distant body can wander into range.
const DRIVE_FRAMES: int = 40


func run(ctx: TestContext) -> void:
	print("[encumbrance] --- weight slow-down: tiers + over-capacity player travels less far ---")
	_tier_unit_legs(ctx)

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

	# Over capacity: the same loadout + 200 stone (200.0) -> total 207.5 / 50, ratio > 3, so the
	# encumbrance factor sits at the ULTRA 0.25 crawl -- a wide, unambiguous gap from the light
	# player. add_item runs AFTER add_child (so _ready wired the Equipment/inventory first). Parked
	# far in the opposite direction.
	var heavy: Player = player_scene.instantiate() as Player
	heavy.pickup_radius = 0.0
	ctx.tree.root.add_child(heavy)
	heavy.global_position = Vector2(-12000, -12000)
	heavy.inventory.add_item(STONE, 200)

	# Let _ready wiring settle so both inventories are fully populated before we read factors.
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	# The controlling factors: full speed at/under capacity, the ULTRA crawl when deeply overloaded.
	ctx.check(light.inventory.weight_ratio() <= 1.0 and is_equal_approx(light.inventory.encumbrance_factor(), 1.0)
			and light.inventory.encumbrance_tier() == Inventory.Encumbrance.NORMAL,
		"under-capacity player runs at NORMAL factor 1.0 (loadout ratio " + str(light.inventory.weight_ratio()) + ")",
		"under-capacity factor not 1.0 (factor " + str(light.inventory.encumbrance_factor()) + ")")
	ctx.check(heavy.inventory.weight_ratio() > 3.0 and is_equal_approx(heavy.inventory.encumbrance_factor(), 0.25)
			and heavy.inventory.encumbrance_tier() == Inventory.Encumbrance.ULTRA,
		"over-capacity player is ULTRA-encumbered to the 0.25 crawl (ratio " + str(heavy.inventory.weight_ratio()) + ")",
		"over-capacity factor not the ULTRA crawl (ratio " + str(heavy.inventory.weight_ratio()) + " factor " + str(heavy.inventory.encumbrance_factor()) + ")")

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
	# The factor gap is 1.0 vs 0.25, so the heavy player covers well under 60% of the light one's
	# distance -- a wide, unambiguous margin that will not flake on physics-timing jitter.
	ctx.check(heavy_dx < light_dx * 0.6,
		"over-capacity player travelled measurably LESS far (heavy " + str(int(heavy_dx)) + " < 0.6 * light " + str(int(light_dx)) + ")",
		"encumbrance did not slow the heavy player (heavy " + str(int(heavy_dx)) + " vs light " + str(int(light_dx)) + ")")

	light.input_override = null
	heavy.input_override = null
	light.queue_free()
	heavy.queue_free()
	await ctx.settle_idle()


## Pure Inventory math for the GENTLE tier scheme -- no scene needed. Capacity 10, stone (1.0 each)
## so stone count == ratio * 10. Walks every band + its inclusive upper boundary: 0.5/1.0 -> NORMAL
## 1.0; 1.5/2.0 -> OVER 0.75; 2.5/3.0 -> SUPER 0.50; 3.5/5.0 -> ULTRA 0.25. Confirms both the factor
## and the tier enum at each representative ratio, including that thresholds fall to the LIGHTER tier.
func _tier_unit_legs(ctx: TestContext) -> void:
	var STONE: ItemData = load("res://data/stone.tres")
	# ratio -> (expected factor, expected tier). Stone count = ratio * 10 against capacity 10.
	var cases: Array = [
		[0.5, 1.0, Inventory.Encumbrance.NORMAL],
		[1.0, 1.0, Inventory.Encumbrance.NORMAL],
		[1.5, 0.75, Inventory.Encumbrance.OVER],
		[2.0, 0.75, Inventory.Encumbrance.OVER],
		[2.5, 0.50, Inventory.Encumbrance.SUPER],
		[3.0, 0.50, Inventory.Encumbrance.SUPER],
		[3.5, 0.25, Inventory.Encumbrance.ULTRA],
		[5.0, 0.25, Inventory.Encumbrance.ULTRA],
	]
	for case in cases:
		var ratio: float = case[0]
		var want_factor: float = case[1]
		var want_tier: int = case[2]
		var inv: Inventory = Inventory.new()
		inv.carry_capacity = 10.0
		inv.add_item(STONE, int(ratio * 10.0))
		ctx.check(is_equal_approx(inv.encumbrance_factor(), want_factor) and inv.encumbrance_tier() == want_tier,
			"encumbrance tier: ratio " + str(ratio) + " -> factor " + str(want_factor) + " tier " + str(want_tier),
			"encumbrance tier wrong at ratio " + str(ratio) + " (factor " + str(inv.encumbrance_factor()) + " tier " + str(inv.encumbrance_tier()) + ")")

# Verified against: Godot 4.7.1 (2026-07-19)
