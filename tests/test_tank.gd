class_name TestTank extends RefCounted
## Elephant-Tank behaviour (design-enemies.md "1. Elephant-Tank"), Phase 1 of the enemy roster.
## Self-contained and DETERMINISTIC: it spawns its own Tank (enemy/dummy.tscn, now driven by
## tank.gd) plus a stand-in player target at REMOTE coords, sets tank._target directly (so the
## shared main.tscn player in the "player" group is never picked), and steps physics frames -- no
## keyboard, no reliance on the shared fixture. Legs:
##   a. GRAZE ignores a nearby player -- stays GRAZE, does not approach it, does not attack.
##   b. A hit (provoke) flips it to ENRAGED and it now SLOWLY pursues (closes distance).
##   c. De-aggro: with no new hit AND the target out of leash range it settles back to GRAZE.
##   d. The stomp is TELEGRAPHED (a wind-up with a COLD hitbox precedes the damaging hit) and, when
##      it lands, deals its brutal damage + huge knockback that launches the target.
## Registered in tests/smoke_slash.gd after the other self-contained modules.

## The Tank scene doubles as the durability fixture; instance it for the free behaviour Tank too.
const TANK_SCENE_PATH: String = "res://enemy/dummy.tscn"
const PLAYER_SCENE_PATH: String = "res://player/player.tscn"


func run(ctx: TestContext) -> void:
	print("[tank] --- Elephant-Tank GRAZE/ENRAGED/CALM + telegraphed stomp (design-enemies.md) ---")
	var tank_scene: PackedScene = load(TANK_SCENE_PATH)
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	if tank_scene == null or player_scene == null:
		ctx.check(false, "", "tank/player scene failed to load (test_tank)")
		return

	await _graze_ignores(ctx, tank_scene, player_scene)
	await _provoke_pursues(ctx, tank_scene, player_scene)
	await _deaggro_calms(ctx, tank_scene, player_scene)
	await _stomp_telegraphed(ctx, tank_scene, player_scene)


## a. GRAZE (default) ignores the player entirely: watches it but never approaches or strikes.
func _graze_ignores(ctx: TestContext, tank_scene: PackedScene, player_scene: PackedScene) -> void:
	var tank: Tank = _spawn_tank(ctx, tank_scene, Vector2(40000, 40000))
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(40050, 40000))
	tank._target = target
	await ctx.tree.physics_frame
	var dist_before: float = tank.global_position.distance_to(target.global_position)
	for _i in range(24):
		await ctx.tree.physics_frame
	var dist_after: float = tank.global_position.distance_to(target.global_position)
	ctx.check(tank._tank_state == Tank.TankState.GRAZE and not tank._attacking and not tank._telegraphing
			and dist_after >= dist_before - 1.0,
		"GRAZE ignores a nearby player: stays GRAZE, does not approach (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + "), no attack",
		"GRAZE did not ignore the player (state=" + str(tank._tank_state) + " attacking=" + str(tank._attacking) + " dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + ")")
	tank.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## b. provoke() (as a hit would) flips GRAZE -> ENRAGED, and it then pursues the target -- slowly
## but relentlessly closing the gap.
func _provoke_pursues(ctx: TestContext, tank_scene: PackedScene, player_scene: PackedScene) -> void:
	var tank: Tank = _spawn_tank(ctx, tank_scene, Vector2(42000, 42000))
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(42200, 42000))  # in leash (320), out of reach (70)
	tank._target = target
	await ctx.tree.physics_frame
	tank.provoke()
	ctx.check(tank._tank_state == Tank.TankState.ENRAGED,
		"a hit (provoke) wakes the brute: GRAZE -> ENRAGED",
		"provoke did not enrage the tank (state=" + str(tank._tank_state) + ")")
	var dist_before: float = tank.global_position.distance_to(target.global_position)
	for _i in range(40):
		await ctx.tree.physics_frame
	var dist_after: float = tank.global_position.distance_to(target.global_position)
	ctx.check(dist_after < dist_before - 2.0 and tank._tank_state == Tank.TankState.ENRAGED,
		"ENRAGED tank slowly pursues the player (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + ")",
		"ENRAGED tank did not pursue (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + " state=" + str(tank._tank_state) + ")")
	tank.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## c. De-aggro: once ENRAGED, with NO new hit and the target driven beyond the leash range for
## deaggro_time, it passes through CALM and returns to GRAZE (timings shrunk for a fast, deterministic
## check).
func _deaggro_calms(ctx: TestContext, tank_scene: PackedScene, player_scene: PackedScene) -> void:
	var tank: Tank = _spawn_tank(ctx, tank_scene, Vector2(44000, 44000))
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(44100, 44000))
	tank._target = target
	tank.deaggro_time = 0.1     # shrink the calm-down delay for the test
	tank.calm_settle_time = 0.05
	await ctx.tree.physics_frame
	tank.provoke()
	ctx.check(tank._tank_state == Tank.TankState.ENRAGED,
		"tank enraged before the de-aggro check",
		"tank not enraged before de-aggro (state=" + str(tank._tank_state) + ")")
	# Player flees far beyond the leash (detection_range 320); no further hits land.
	target.global_position = Vector2(60000, 60000)
	for _i in range(30):
		await ctx.tree.physics_frame
	ctx.check(tank._tank_state == Tank.TankState.GRAZE,
		"de-aggro: no new hit + target out of range settled the tank back to GRAZE",
		"tank did not calm back to GRAZE (state=" + str(tank._tank_state) + ")")
	tank.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## d. The telegraphed stomp: a readable wind-up with a COLD hitbox precedes the damaging hit, then
## the strike deals brutal damage + huge knockback. Driven by a DIRECT stomp() call on a pinned tank
## for deterministic timing (telegraph_time shrunk); knockback is captured on the target Hurtbox's
## hit_taken (the exact hit frame, before it decays).
func _stomp_telegraphed(ctx: TestContext, tank_scene: PackedScene, player_scene: PackedScene) -> void:
	var tank: Tank = _spawn_tank(ctx, tank_scene, Vector2(46000, 46000))
	tank.stationary = true         # pin: only the direct stomp() acts, no auto-AI interference
	tank.telegraph_time = 0.15     # shrink the wind-up for a fast check
	var target: Player = _spawn_player(ctx, player_scene, Vector2(46050, 46000)) as Player
	tank._target = target
	var target_health: HealthComponent = target.get_node("HealthComponent") as HealthComponent
	var target_hurtbox: Hurtbox = target.get_node("Hurtbox") as Hurtbox
	await ctx.tree.physics_frame

	var hp_before: int = target_health.current_health
	var hit_knockback: Array = [0.0]
	var on_hit: Callable = func(_hb: Hitbox) -> void: hit_knockback[0] = target._knockback.length()
	target_hurtbox.hit_taken.connect(on_hit)

	tank.stomp()  # fire the stomp coroutine; do NOT await -- sample the wind-up first
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame  # ~0.033s < telegraph_time 0.15 -> still winding up
	ctx.check(tank._telegraphing and tank._attack_shape.disabled and target_health.current_health == hp_before,
		"stomp WIND-UP: telegraphing with a COLD hitbox (no damage yet during the tell)",
		"stomp had no cold wind-up (telegraphing=" + str(tank._telegraphing) + " shape_disabled=" + str(tank._attack_shape.disabled) + " hp " + str(hp_before) + " -> " + str(target_health.current_health) + ")")

	for _i in range(24):  # let the wind-up (0.15s) + strike window (0.2s) elapse
		await ctx.tree.physics_frame
	target_hurtbox.hit_taken.disconnect(on_hit)
	ctx.check(target_health.current_health < hp_before,
		"the stomp LANDED brutal damage when it struck (" + str(hp_before) + " -> " + str(target_health.current_health) + ")",
		"the stomp dealt no damage (" + str(hp_before) + " -> " + str(target_health.current_health) + ")")
	ctx.check(hit_knockback[0] >= 500.0,
		"the stomp LAUNCHED the target with huge knockback (impulse " + str(int(hit_knockback[0])) + " >= 500, the authored ~620 stomp impulse)",
		"the stomp knockback was not the authored heavy impulse (impulse " + str(hit_knockback[0]) + ", expected >= 500)")
	tank.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## Instantiate a behaviour Tank (non-stationary by default so its FSM runs) at `at`.
func _spawn_tank(ctx: TestContext, scene: PackedScene, at: Vector2) -> Tank:
	var tank: Tank = scene.instantiate() as Tank
	tank.stationary = false
	ctx.tree.root.add_child(tank)
	tank.global_position = at
	return tank


## Instantiate a magnet-off Player (a stand-in target with a real Hurtbox + Health + knockback) at
## `at`. pickup_radius 0 so it never auto-collects; input_override left null so it never self-moves.
func _spawn_player(ctx: TestContext, scene: PackedScene, at: Vector2) -> Node2D:
	var p: Player = scene.instantiate() as Player
	p.pickup_radius = 0.0
	ctx.tree.root.add_child(p)
	p.global_position = at
	return p

# Verified against: Godot 4.7.1 (2026-07-19)
