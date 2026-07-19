extends SceneTree
## Headless smoke test ORCHESTRATOR + entry point for Milestone B1/B2 combat feel PLUS
## the durability + hardness slice PLUS System 3 tool categories PLUS inventory/hotbar
## PLUS world streaming (design-durability.md, design-inventory.md, design-world-streaming.md).
##
## This file was split out of a former 1350-line monolith per CONVENTIONS.md Rule 1. It is
## now a THIN orchestrator: it builds a shared TestContext, runs each per-system module in
## the SAME order the legs originally ran, aggregates pass/fail, and quits 0/1. The tests
## themselves live in per-system modules (each `class_name X extends RefCounted` with an
## awaitable `run(ctx)`), so `await mod.run(ctx)` drives them:
##   * tests/test_context.gd        -- TestContext: tree handle, check(), frame(), shared
##                                     main.tscn refs, and the slash_target/lunge_hit helpers.
##   * tests/test_units.gd          -- pure unit tests (resolvers, inventory, chunk-C1).
##   * tests/test_combat.gd         -- integration legs a-i on the SHARED main.tscn.
##   * tests/test_durability_tools.gd-- integration legs j-r (+ facing leg s), SAME instance,
##                                     run AFTER test_combat so leg order + shared state hold.
##   * tests/test_streaming.gd      -- C2/C3a/C3b streaming, self-contained (own ChunkManagers).
##   * tests/test_playable.gd       -- playable-loop D1: world-preserving death/respawn on the
##                                     shipped streaming_world.tscn, self-contained.
##   * tests/test_hud.gd            -- playable-loop D2: the minimal HUD reflects health/tool/
##                                     durability/hotbar on streaming_world.tscn, self-contained.
##   * tests/test_lifetime.gd       -- E3b lifetime cull: short-lived drops despawn, default-
##                                     lifetime drops survive, order is tunable; self-contained.
##
## ORDERED SHARED-SCENE CONTRACT: the combat and durability legs share ONE main.tscn instance
## with cross-leg state (resets, tool equips, positions). The orchestrator instantiates that
## scene ONCE, passes the same refs via ctx, and runs the gameplay modules in the identical
## original order. The streaming module is independent. Assertion messages were moved VERBATIM.
##
## Overlap detection resolves on physics frames, so we await a few before reading.
## queue_free is deferred, so we read plain flags/health captured from signals.
##
## Run: <godot_console> --headless --path <proj> -s res://tests/smoke_slash.gd
## Exit 0 = every assertion passed; exit 1 = any failure.


func _initialize() -> void:
	_run()


func _run() -> void:
	var ctx: TestContext = TestContext.new()
	ctx.tree = self

	# --- PURE UNIT tests: resolvers, inventory, streaming C1 (no scene needed) ---
	TestUnits.new().run(ctx)

	# --- Shared main.tscn instance for the ordered gameplay legs -----------------
	var main_scene: PackedScene = load("res://main.tscn")
	if main_scene == null:
		_fail("could not load res://main.tscn")
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)

	var player: Player = main.get_node("Player") as Player
	var enemy: Enemy = main.get_node("Enemy") as Enemy
	if player == null or enemy == null:
		_fail("player or enemy missing from main scene")
		return

	ctx.main = main
	ctx.player = player
	ctx.enemy = enemy
	ctx.dummy = main.get_node("Dummy") as Enemy
	ctx.player_health = player.get_node("HealthComponent") as HealthComponent
	ctx.enemy_health = enemy.get_node("HealthComponent") as HealthComponent
	ctx.dummy_health = ctx.dummy.get_node("HealthComponent") as HealthComponent
	ctx.sword_dura = player.get_node("SwordDurability") as DurabilityComponent
	ctx.axe_dura = player.get_node("AxeDurability") as DurabilityComponent
	ctx.pickaxe_dura = player.get_node("PickaxeDurability") as DurabilityComponent

	# E3a HAZARD 2: the ordered combat/durability legs mine rocks and fell the tree ADJACENT
	# to THIS shared player (harvesting requires adjacency -> the drops spawn inside a magnet
	# radius, so spatial isolation is infeasible), and leg r asserts inventory slots 3-5 stay
	# EMPTY. With the magnet live, this player would auto-collect those harvest drops (breaking
	# leg r) AND free the drops that then linger in main.tscn -- the very nodes the streaming
	# zero-orphan-leak baseline counts (HAZARD 1). So pickup is suppressed on this incidental
	# player; the litter stays put, byte-identical to the pre-magnet baseline. The magnet
	# itself is proven in isolation by tests/test_pickup.gd.
	player.pickup_radius = 0.0

	# Let _ready wiring (group registration, component hookup) settle.
	await physics_frame
	await physics_frame

	# --- Ordered gameplay legs on the SHARED main.tscn instance ------------------
	# test_combat (a-i) MUST run before test_durability_tools (j-r/s): they reuse the
	# same refs and the same mutated state in the original leg order.
	await TestCombat.new().run(ctx)
	await TestDurabilityTools.new().run(ctx)

	# --- Streaming (self-contained: builds its own ChunkManager setups) ----------
	await TestStreaming.new().run(ctx)

	# --- Playable loop D1 (self-contained: instantiates streaming_world.tscn) -----
	await TestPlayable.new().run(ctx)

	# --- Playable loop D2 HUD (self-contained: instantiates streaming_world.tscn) -
	await TestHud.new().run(ctx)

	# --- Meadow ground (self-contained: instantiates streaming_world.tscn) --------
	await TestGround.new().run(ctx)

	# --- Elevation + inside/outside FOUNDATION (self-contained: own player + trigger, remote) ---
	await TestElevation.new().run(ctx)

	# --- Progression: XP + level curve + two-currency banking (self-contained: pure instances + own player) ---
	await TestProgression.new().run(ctx)

	# --- XP award hooks (kill/fell/mine/forage) + level boundary + HUD readout (self-contained, remote) ---
	await TestXpAward.new().run(ctx)

	# --- Boulder terrain Environment #2 (self-contained: own holders/players/boulders + ChunkManager) ---
	await TestBoulder.new().run(ctx)

	# --- Encumbrance E-weight (self-contained: own two players driven at remote coords) ---
	await TestEncumbrance.new().run(ctx)

	# --- Harvest yield E2 (self-contained: own tree/rock instances under private holders) -
	await TestHarvest.new().run(ctx)

	# --- Magnetic auto-pickup E3a (self-contained: own player + drops far from origin) ----
	await TestPickup.new().run(ctx)

	# --- Lifetime cull E3b (self-contained: own short-lived drops far from origin) --------
	await TestLifetime.new().run(ctx)

	# --- Drop chunk-persistence E3c (self-contained: own ChunkManager in a remote region) -
	await TestDropPersist.new().run(ctx)

	# --- Forage bushes + 'f'-interaction E4 (self-contained: own players/bushes remote) ---
	await TestForage.new().run(ctx)

	# --- Forage pebbles E4 (self-contained: own players/pebbles in a distinct remote region) -
	await TestPebble.new().run(ctx)

	# --- Player controls: stamina + sprint + dodge (self-contained: own players/enemies remote) ---
	await TestControls.new().run(ctx)

	# --- Elephant-Tank behaviour: GRAZE/ENRAGED/CALM + telegraphed stomp (self-contained, remote) ---
	await TestTank.new().run(ctx)

	# --- Swordsman dueler: telegraphed combos + reactive dodge (cooldown+punish) + spacing + escalation ---
	await TestSwordsman.new().run(ctx)

	# --- Charger dash-bruiser: TRACK/WINDUP/CHARGE/RECOVER + locked straight-line overshoot ---
	await TestCharger.new().run(ctx)

	# --- Spitter ranged kiter: REPOSITION/AIM/FIRE + the reusable Projectile (travel/hit/cull) ---
	await TestSpitter.new().run(ctx)

	if ctx.all_pass:
		print("[PASS] smoke_slash: combat + combo + death + bodies + input seam + durability + streaming + playable + hud + encumbrance + harvest + pickup + lifetime + drop-persist + forage + pebble + controls + elevation + boulder + tank + swordsman + charger + spitter -- all passed")
		quit(0)
	else:
		_fail("one or more assertions failed")


func _fail(reason: String) -> void:
	print("[FAIL] ", reason)
	quit(1)

# Verified against: Godot 4.7.1 (2026-07-18)
