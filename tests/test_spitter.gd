class_name TestSpitter extends RefCounted
## Spitter behaviour + the reusable Projectile (design-enemies.md "4. Spitter" + "Shared tech --
## Projectile"), Phase 4 (final) of the enemy roster. Self-contained and DETERMINISTIC: it spawns its
## own Spitter (enemy/spitter.tscn) plus a stand-in player target at REMOTE coords, sets spitter._target
## directly (so the shared main.tscn player in the "player" group is never picked), and steps physics
## frames -- no keyboard, no reliance on the shared fixture. Simulated hits are delivered by calling a
## Hurtbox's _on_area_entered directly (the SAME deterministic pattern the Tank/Charger legs use). Legs:
##   a. KITE too close: a player INSIDE the preferred ring -> the Spitter backs AWAY (distance grows).
##   b. KITE too far: a player BEYOND the ring -> the Spitter approaches (distance shrinks).
##   c. KITE in band: a player at preferred_range -> it holds near preferred_range (strafes, no run-off).
##   d. FIRE cadence: after fire_interval it spawns a Projectile aimed at the player.
##   e. PROJECTILE: travels in a STRAIGHT line; on a simulated player-Hurtbox hit it deals its atk
##      damage, and on a simulated player-body contact it DESPAWNS (no leak).
##   f. PROJECTILE cull: a shot that hits nothing despawns on max range/lifetime (no leak).
## Registered in tests/smoke_slash.gd after the Charger module.

const SPITTER_SCENE_PATH: String = "res://enemy/spitter.tscn"
const PLAYER_SCENE_PATH: String = "res://player/player.tscn"
const PROJECTILE_SCENE_PATH: String = "res://enemy/projectile.tscn"


func run(ctx: TestContext) -> void:
	print("[spitter] --- Spitter ranged kiter: REPOSITION/AIM/FIRE + reusable Projectile (design-enemies.md) ---")
	var spitter_scene: PackedScene = load(SPITTER_SCENE_PATH)
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var projectile_scene: PackedScene = load(PROJECTILE_SCENE_PATH)
	if spitter_scene == null or player_scene == null or projectile_scene == null:
		ctx.check(false, "", "spitter/player/projectile scene failed to load (test_spitter)")
		return

	await _kite_too_close_backs_away(ctx, spitter_scene, player_scene)
	await _kite_too_far_approaches(ctx, spitter_scene, player_scene)
	await _kite_in_band_holds(ctx, spitter_scene, player_scene)
	await _fire_cadence_spawns_aimed_shot(ctx, spitter_scene, player_scene)
	await _projectile_travels_hits_and_despawns(ctx, player_scene, projectile_scene)
	await _projectile_culls_on_range(ctx, projectile_scene)


## a. KITE too close: a target well INSIDE preferred_range makes the Spitter BACK AWAY -- distance grows.
func _kite_too_close_backs_away(ctx: TestContext, spitter_scene: PackedScene, player_scene: PackedScene) -> void:
	var spitter: Spitter = _spawn_spitter(ctx, spitter_scene, Vector2(70000, 70000))
	spitter.fire_interval = 999.0  # isolate movement: never fire during the kite legs
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(70060, 70000))  # dist 60 << preferred 220
	spitter._target = target
	await ctx.tree.physics_frame
	var dist_before: float = spitter.global_position.distance_to(target.global_position)
	for _i in range(40):
		await ctx.tree.physics_frame
	var dist_after: float = spitter.global_position.distance_to(target.global_position)
	ctx.check(dist_after > dist_before + 4.0,
		"KITE too close: the Spitter backs AWAY from a player inside the ring (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + ")",
		"spitter did not back away (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + ")")
	spitter.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## b. KITE too far: a target BEYOND preferred_range + deadband makes the Spitter APPROACH -- distance shrinks.
func _kite_too_far_approaches(ctx: TestContext, spitter_scene: PackedScene, player_scene: PackedScene) -> void:
	var spitter: Spitter = _spawn_spitter(ctx, spitter_scene, Vector2(72000, 72000))
	spitter.fire_interval = 999.0
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(72400, 72000))  # dist 400 >> preferred 220
	spitter._target = target
	await ctx.tree.physics_frame
	var dist_before: float = spitter.global_position.distance_to(target.global_position)
	for _i in range(40):
		await ctx.tree.physics_frame
	var dist_after: float = spitter.global_position.distance_to(target.global_position)
	ctx.check(dist_after < dist_before - 4.0,
		"KITE too far: the Spitter approaches a distant player (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + ")",
		"spitter did not approach (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + ")")
	spitter.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## c. KITE in band: a target AT preferred_range keeps the Spitter near it -- it strafes (holds the ring),
## never running off. Assert the distance stays within the deadband (plus a small tolerance) after a spell.
func _kite_in_band_holds(ctx: TestContext, spitter_scene: PackedScene, player_scene: PackedScene) -> void:
	var spitter: Spitter = _spawn_spitter(ctx, spitter_scene, Vector2(74000, 74000))
	spitter.fire_interval = 999.0
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(74220, 74000))  # dist 220 == preferred_range
	spitter._target = target
	await ctx.tree.physics_frame
	var held: bool = true
	for _i in range(60):
		await ctx.tree.physics_frame
		var d: float = spitter.global_position.distance_to(target.global_position)
		if absf(d - spitter.preferred_range) > spitter.range_deadband + 30.0:
			held = false
			break
	ctx.check(held,
		"KITE in band: the Spitter holds near preferred_range (" + str(int(spitter.preferred_range)) + "px) instead of closing or fleeing",
		"spitter did not hold the preferred ring (drifted beyond the deadband)")
	spitter.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## d. FIRE cadence: within fire_range and after fire_interval elapses, the Spitter spawns a Projectile
## aimed at the player. Shrink the cadence + aim window for a fast deterministic reach into FIRE.
func _fire_cadence_spawns_aimed_shot(ctx: TestContext, spitter_scene: PackedScene, player_scene: PackedScene) -> void:
	_clear_projectiles(ctx)
	var spitter: Spitter = _spawn_spitter(ctx, spitter_scene, Vector2(76000, 76000))
	spitter.fire_interval = 0.1
	spitter.aim_time = 0.05
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(76200, 76000))  # dist 200, in band + fire_range
	spitter._target = target
	await ctx.tree.physics_frame

	var shot: Projectile = null
	for _i in range(90):
		await ctx.tree.physics_frame
		var live: Array = ctx.tree.get_nodes_in_group("projectiles")
		if not live.is_empty():
			shot = live[0] as Projectile
			break
	var spawned: bool = shot != null and is_instance_valid(shot)
	var aimed: bool = false
	if spawned:
		var expected: Vector2 = (target.global_position - spitter.global_position).normalized()
		aimed = shot._velocity.length() > 0.001 and shot._velocity.normalized().dot(expected) > 0.9
	ctx.check(spawned and aimed,
		"FIRE cadence: after fire_interval the Spitter spawns a Projectile aimed at the player (dot " + (str(snappedf(shot._velocity.normalized().dot((target.global_position - spitter.global_position).normalized()), 0.01)) if spawned else "n/a") + ")",
		"spitter did not fire an aimed projectile (spawned=" + str(spawned) + " aimed=" + str(aimed) + ")")
	_clear_projectiles(ctx)
	spitter.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## e. PROJECTILE: a shot travels in a STRAIGHT line; a simulated player-Hurtbox hit deals its atk damage
## (target HP boosted so we only READ the hit, avoiding the death/respawn path); a simulated player-body
## contact DESPAWNS it (no leak). Drives the hurtbox/body seams directly for deterministic timing.
func _projectile_travels_hits_and_despawns(ctx: TestContext, player_scene: PackedScene, projectile_scene: PackedScene) -> void:
	_clear_projectiles(ctx)
	var target: Player = _spawn_player(ctx, player_scene, Vector2(78000, 78000)) as Player
	var target_health: HealthComponent = target.get_node("HealthComponent") as HealthComponent
	var target_hurtbox: Hurtbox = target.get_node("Hurtbox") as Hurtbox
	target_health.max_health = 100
	target_health.current_health = 100

	var proj: Projectile = projectile_scene.instantiate() as Projectile
	ctx.tree.root.add_child(proj)
	proj.global_position = Vector2(78200, 78000)
	proj.setup(Vector2.RIGHT, 150.0, 2, 120.0)  # travel +X, atk 2, knockback 120
	var start: Vector2 = proj.global_position
	for _i in range(10):
		await ctx.tree.physics_frame
	var travelled_straight: bool = proj.global_position.x > start.x + 4.0 and absf(proj.global_position.y - start.y) < 1.0
	ctx.check(travelled_straight,
		"PROJECTILE travels in a STRAIGHT line (x " + str(int(start.x)) + " -> " + str(int(proj.global_position.x)) + ", dy " + str(snappedf(proj.global_position.y - start.y, 0.1)) + ")",
		"projectile did not travel straight (start " + str(start) + " -> " + str(proj.global_position) + ")")

	# Damage: drive the player Hurtbox's resolve with the shot as the incoming Hitbox (it IS one).
	var hp_before: int = target_health.current_health
	target_hurtbox._on_area_entered(proj)
	var damage_dealt: int = hp_before - target_health.current_health
	ctx.check(damage_dealt == proj.atk,
		"PROJECTILE deals its atk on the player's Hurtbox (" + str(damage_dealt) + " HP, atk " + str(proj.atk) + ")",
		"projectile hit did not deal its atk (dealt " + str(damage_dealt) + " atk " + str(proj.atk) + ")")

	# Despawn on hit: the player-body contact seam culls the shot -- no leak.
	proj._on_body_entered(target)
	for _i in range(4):
		await ctx.tree.physics_frame
	ctx.check(not is_instance_valid(proj),
		"PROJECTILE DESPAWNS on a player-body hit (freed, no leak)",
		"projectile did not despawn on hit (still valid)")
	target.queue_free()
	await ctx.settle_idle()


## f. PROJECTILE cull: a shot that hits nothing self-despawns once it exceeds max_range -- the drop-style
## bounded, leak-free cull. Shrink max_range so it culls in a few frames.
func _projectile_culls_on_range(ctx: TestContext, projectile_scene: PackedScene) -> void:
	_clear_projectiles(ctx)
	var proj: Projectile = projectile_scene.instantiate() as Projectile
	proj.max_range = 40.0
	ctx.tree.root.add_child(proj)
	proj.global_position = Vector2(80000, 80000)
	proj.setup(Vector2.RIGHT, 150.0, 2, 120.0)  # 150px/sec crosses 40px in ~4-5 physics frames
	var culled: bool = false
	for _i in range(30):
		await ctx.tree.physics_frame
		if not is_instance_valid(proj):
			culled = true
			break
	ctx.check(culled,
		"PROJECTILE culls itself on max range/lifetime when it hits nothing (freed, no leak)",
		"projectile did not cull on max range (still valid after max_range exceeded)")
	_clear_projectiles(ctx)
	await ctx.settle_idle()


## Instantiate a free (non-stationary) Spitter at `at` so its kiting/firing FSM runs.
func _spawn_spitter(ctx: TestContext, scene: PackedScene, at: Vector2) -> Spitter:
	var spitter: Spitter = scene.instantiate() as Spitter
	spitter.stationary = false
	ctx.tree.root.add_child(spitter)
	spitter.global_position = at
	return spitter


## Instantiate a magnet-off Player stand-in target (real Hurtbox + Health + knockback) at `at`.
## pickup_radius 0 so it never auto-collects; input_override null so it never self-moves.
func _spawn_player(ctx: TestContext, scene: PackedScene, at: Vector2) -> Node2D:
	var p: Player = scene.instantiate() as Player
	p.pickup_radius = 0.0
	ctx.tree.root.add_child(p)
	p.global_position = at
	return p


## Free every live shot so a leg leaves no projectile behind (keeps the group counts clean between legs
## and never perturbs any later baseline). queue_free is deferred; callers settle before re-reading.
func _clear_projectiles(ctx: TestContext) -> void:
	for p in ctx.tree.get_nodes_in_group("projectiles"):
		if is_instance_valid(p):
			p.queue_free()

# Verified against: Godot 4.7.1 (2026-07-19)
