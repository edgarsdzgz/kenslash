class_name TestCharger extends RefCounted
## Charger behaviour (design-enemies.md "3. Charger"), Phase 3 of the enemy roster. Self-contained and
## DETERMINISTIC: it spawns its own Charger (enemy/charger.tscn) plus a stand-in player target at REMOTE
## coords, sets charger._target directly (so the shared main.tscn player in the "player" group is never
## picked), and steps physics frames -- no keyboard, no reliance on the shared fixture. Simulated
## contact hits are delivered by calling a Hurtbox's _on_area_entered directly (the SAME deterministic
## pattern the Tank/Swordsman legs and tests/test_controls.gd use). Legs:
##   a. TRACK: a target in range is APPROACHED at a slow walk, then it commits to WINDUP.
##   a2. Point-blank counter-play: a target INSIDE charge_min_range is BACKED AWAY FROM / wound up on,
##       never nuzzled forever (the no-counterplay dead zone is closed).
##   b. WINDUP is TELEGRAPHED: _telegraphing with a COLD (disabled) hitbox, NO damage during the tell,
##      and the charge direction is LOCKED toward the player's position at windup start.
##   c. CHARGE: it dashes in a STRAIGHT line and OVERSHOOTS past the player's start position; the hitbox
##      is LIVE and (on a simulated contact) deals its big damage + knockback.
##   d. RECOVER: after the dash it is vulnerable (COLD hitbox, no attack, takes a hit) for the recover
##      window, then returns to TRACK.
##   e. FACING: the arrow-triangle Body points ALONG its facing (up/down/left/right), not swapped to a
##      rectangle when vertical.
## Registered in tests/smoke_slash.gd after the Swordsman module.

const CHARGER_SCENE_PATH: String = "res://enemy/charger.tscn"
const PLAYER_SCENE_PATH: String = "res://player/player.tscn"


func run(ctx: TestContext) -> void:
	print("[charger] --- Charger dash-bruiser: TRACK/WINDUP/CHARGE/RECOVER (design-enemies.md) ---")
	var charger_scene: PackedScene = load(CHARGER_SCENE_PATH)
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	if charger_scene == null or player_scene == null:
		ctx.check(false, "", "charger/player scene failed to load (test_charger)")
		return

	await _track_approaches_then_windup(ctx, charger_scene, player_scene)
	await _pointblank_backs_off(ctx, charger_scene, player_scene)
	await _windup_telegraphed_and_locked(ctx, charger_scene, player_scene)
	await _charge_overshoots_and_hits(ctx, charger_scene, player_scene)
	await _recover_then_track(ctx, charger_scene, player_scene)
	await _arrow_points_along_facing(ctx, charger_scene, player_scene)


## e. FACING: the arrow-triangle Body points ALONG its facing -- up when facing up, down when facing
## down, and left/right -- instead of the base swap-to-rectangle. With a target on each axis beyond
## charge_range (so it stays in TRACK), asserts _body.rotation == facing.angle() and scale.x stays 1.
func _arrow_points_along_facing(ctx: TestContext, charger_scene: PackedScene, player_scene: PackedScene) -> void:
	var charger: Charger = _spawn_charger(ctx, charger_scene, Vector2(62000, 62000))
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(62300, 62000))
	charger._target = target
	# TUNING sanity (design-enemies.md): the dash-bruiser is worth more XP than the plain base-dummy
	# default (20) -- a scene-authored xp_reward, harder enemy for more XP. Documents the charger.tscn value.
	ctx.check(charger.xp_reward > 20,
		"Charger xp_reward (" + str(charger.xp_reward) + ") exceeds the base default 20 (dash-bruiser worth more XP)",
		"Charger xp_reward not raised above the base default (got " + str(charger.xp_reward) + ")")
	await ctx.tree.physics_frame  # warm-up frame: let the charger notice the target before measuring facing
	var ok: bool = true
	# Rotating the visual arrow Body must NEVER rotate the collision hitbox or the hurtbox: in TRACK the
	# AttackHitbox is only aimed during windup/charge, and the Hurtbox is never aimed -- both stay at
	# rotation 0 through every facing (the Body spin is visual-only; _update_avatar touches the Body alone).
	var collision_static: bool = true
	var detail: String = ""
	var collision_detail: String = ""
	var probes: Array = [
		["up", Vector2(0, -300), -PI / 2.0],
		["down", Vector2(0, 300), PI / 2.0],
		["right", Vector2(300, 0), 0.0],
		["left", Vector2(-300, 0), PI],
	]
	for probe in probes:
		target.global_position = charger.global_position + (probe[1] as Vector2)
		await ctx.tree.physics_frame
		var rot: float = charger._body.rotation
		if absf(angle_difference(rot, probe[2] as float)) > 0.01 or not is_equal_approx(charger._body.scale.x, 1.0):
			ok = false
			detail += " " + str(probe[0]) + "(rot=" + str(rot) + " want=" + str(probe[2]) + " sx=" + str(charger._body.scale.x) + ")"
		if not is_zero_approx(charger._attack_hitbox.rotation) or not is_zero_approx(charger._hurtbox.rotation):
			collision_static = false
			collision_detail += " " + str(probe[0]) + "(atk=" + str(charger._attack_hitbox.rotation) + " hurt=" + str(charger._hurtbox.rotation) + ")"
	ctx.check(ok,
		"arrow Body points ALONG facing up/down/left/right (scale.x 1, not swapped to a rectangle)",
		"charger arrow did not point along facing:" + detail)
	ctx.check(collision_static,
		"rotating the arrow Body leaves the AttackHitbox + Hurtbox rotation at 0 through TRACK (visual-only spin)",
		"charger Body rotation leaked into the collision hitbox/hurtbox:" + collision_detail)
	charger.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## a. TRACK: with a target just beyond charge_range it walks in SLOWLY (closing the gap) and, once inside
## the engage ring, commits to WINDUP.
func _track_approaches_then_windup(ctx: TestContext, charger_scene: PackedScene, player_scene: PackedScene) -> void:
	var charger: Charger = _spawn_charger(ctx, charger_scene, Vector2(60000, 60000))
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(60200, 60000))  # dist 200 > charge_range 160
	charger._target = target
	await ctx.tree.physics_frame
	var dist_before: float = charger.global_position.distance_to(target.global_position)
	var reached_windup: bool = false
	for _i in range(180):
		await ctx.tree.physics_frame
		if charger._charger_state == Charger.ChargerState.WINDUP:
			reached_windup = true
			break
	var dist_at_windup: float = charger.global_position.distance_to(target.global_position)
	ctx.check(reached_windup and dist_at_windup < dist_before - 2.0 and dist_at_windup <= charger.charge_range + 2.0,
		"TRACK approaches a target at a slow walk then commits to WINDUP (dist " + str(int(dist_before)) + " -> " + str(int(dist_at_windup)) + ")",
		"TRACK did not approach + wind up (reached_windup=" + str(reached_windup) + " dist " + str(int(dist_before)) + " -> " + str(int(dist_at_windup)) + ")")
	charger.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## a2. Point-blank counter-play: a target INSIDE charge_min_range is NOT nuzzled forever. The Charger
## BACKS AWAY (opposite the target) to re-open charge_range -- then can commit to a WINDUP -- instead of
## walking toward the player and never winding up (the old no-counterplay dead zone).
func _pointblank_backs_off(ctx: TestContext, charger_scene: PackedScene, player_scene: PackedScene) -> void:
	var charger: Charger = _spawn_charger(ctx, charger_scene, Vector2(68000, 68000))
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(68012, 68000))  # 12px << charge_min_range 26
	charger._target = target
	await ctx.tree.physics_frame
	var dist_start: float = charger.global_position.distance_to(target.global_position)
	var backed_off: bool = false
	var wound_up: bool = false
	var max_dist: float = dist_start
	for _i in range(60):
		await ctx.tree.physics_frame
		var d: float = charger.global_position.distance_to(target.global_position)
		max_dist = maxf(max_dist, d)
		if d > charger.charge_min_range + 5.0:
			backed_off = true
		if charger._charger_state == Charger.ChargerState.WINDUP or charger._charger_state == Charger.ChargerState.CHARGE:
			wound_up = true
			break
	ctx.check(dist_start < charger.charge_min_range and (backed_off or wound_up),
		"point-blank counter-play: from inside charge_min_range the Charger backs off / winds up, not nuzzles (dist " + str(int(dist_start)) + " -> max " + str(int(max_dist)) + ", state " + str(charger._charger_state) + ")",
		"point-blank dead zone: the Charger just closed onto the player (dist " + str(int(dist_start)) + " max " + str(int(max_dist)) + " state " + str(charger._charger_state) + ")")
	charger.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## b. WINDUP is TELEGRAPHED: the tell plays with a COLD hitbox (no damage lands during it) and the dash
## bearing is LOCKED toward the player's position at windup start (it does NOT re-home -- moving the
## target afterwards leaves the locked line unchanged).
func _windup_telegraphed_and_locked(ctx: TestContext, charger_scene: PackedScene, player_scene: PackedScene) -> void:
	var charger: Charger = _spawn_charger(ctx, charger_scene, Vector2(62000, 62000))
	var target: Player = _spawn_player(ctx, player_scene, Vector2(62120, 62000)) as Player  # in charge_range 160
	charger._target = target
	var target_health: HealthComponent = target.get_node("HealthComponent") as HealthComponent
	await ctx.tree.physics_frame
	var expected_dir: Vector2 = (target.global_position - charger.global_position).normalized()
	var hp_before: int = target_health.current_health

	# One TRACK frame sees the target in range and enters WINDUP; sample the tell before it elapses (0.6s).
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var in_windup: bool = charger._charger_state == Charger.ChargerState.WINDUP
	var cold: bool = charger._attack_shape.disabled
	var telegraphing: bool = charger._telegraphing
	var locked: bool = charger._charge_dir.dot(expected_dir) > 0.99
	# Prove non-homing: move the target aside -- the locked bearing must not follow it.
	target.global_position = Vector2(62000, 70000)
	await ctx.tree.physics_frame
	var still_locked: bool = charger._charge_dir.dot(expected_dir) > 0.99

	ctx.check(in_windup and telegraphing and cold and target_health.current_health == hp_before,
		"WINDUP is TELEGRAPHED: telegraphing with a COLD hitbox, no damage during the tell",
		"WINDUP tell wrong (windup=" + str(in_windup) + " telegraphing=" + str(telegraphing) + " cold=" + str(cold) + " hp " + str(hp_before) + " -> " + str(target_health.current_health) + ")")
	ctx.check(locked and still_locked,
		"the charge direction LOCKS toward the player at windup start and does not re-home",
		"charge direction not locked (locked=" + str(locked) + " still_locked=" + str(still_locked) + " dir=" + str(charger._charge_dir) + ")")
	charger.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## c. CHARGE: it dashes in a STRAIGHT line along the locked bearing and OVERSHOOTS past where the player
## was; the hitbox is LIVE, and a simulated contact deals its big damage + knockback. The target is moved
## aside once the dash starts (its body would otherwise physically block the overshoot) -- consistent
## with the non-homing dash and the intended sidestep counter-play.
func _charge_overshoots_and_hits(ctx: TestContext, charger_scene: PackedScene, player_scene: PackedScene) -> void:
	var charger: Charger = _spawn_charger(ctx, charger_scene, Vector2(64000, 64000))
	charger.telegraph_time = 0.1     # shrink the wind-up for a fast deterministic reach into CHARGE
	var target: Player = _spawn_player(ctx, player_scene, Vector2(64120, 64000)) as Player
	charger._target = target
	var target_health: HealthComponent = target.get_node("HealthComponent") as HealthComponent
	var target_hurtbox: Hurtbox = target.get_node("Hurtbox") as Hurtbox
	await ctx.tree.physics_frame

	# Step through TRACK -> WINDUP -> CHARGE.
	var reached_charge: bool = false
	for _i in range(40):
		await ctx.tree.physics_frame
		if charger._charger_state == Charger.ChargerState.CHARGE:
			reached_charge = true
			break
	var hitbox_live: bool = not charger._attack_shape.disabled
	var start_y: float = charger.global_position.y
	var player_start_x: float = target.global_position.x

	# Simulate a contact while the dash hitbox is live, then move the target clear so the overshoot runs.
	# Boost the target's HP first: the big charge ATK would otherwise drop this stand-in player to 0 and
	# fire its respawn path (a reload_current_scene error, headless) -- we only need to READ the damage.
	target_health.max_health = 100
	target_health.current_health = 100
	var hp_before: int = target_health.current_health
	var hit_knockback: Array = [0.0]
	var on_hit: Callable = func(_hb: Hitbox) -> void: hit_knockback[0] = target._knockback.length()
	target_hurtbox.hit_taken.connect(on_hit)
	target_hurtbox._on_area_entered(charger._attack_hitbox)
	target_hurtbox.hit_taken.disconnect(on_hit)
	target.global_position = Vector2(64000, 72000)

	# Let the dash finish (overshoot charge_distance, into RECOVER).
	for _i in range(80):
		await ctx.tree.physics_frame
		if charger._charger_state != Charger.ChargerState.CHARGE:
			break
	var end_x: float = charger.global_position.x
	var end_y: float = charger.global_position.y

	ctx.check(reached_charge and hitbox_live,
		"CHARGE goes LIVE: the dash hitbox is enabled during the charge",
		"charge hitbox not live (reached_charge=" + str(reached_charge) + " hitbox_live=" + str(hitbox_live) + ")")
	ctx.check(end_x > player_start_x and absf(end_y - start_y) < 4.0,
		"CHARGE dashes STRAIGHT and OVERSHOOTS past the player's start (x " + str(int(player_start_x)) + " -> ended " + str(int(end_x)) + ", dy " + str(snappedf(end_y - start_y, 0.1)) + ")",
		"charge did not overshoot straight (end_x " + str(int(end_x)) + " vs player_start_x " + str(int(player_start_x)) + " dy " + str(end_y - start_y) + ")")
	var damage_dealt: int = hp_before - target_health.current_health
	ctx.check(damage_dealt >= 5 and hit_knockback[0] >= 500.0,
		"the live dash deals its big damage (" + str(damage_dealt) + " HP) + big knockback (impulse " + str(int(hit_knockback[0])) + " >= 500, the authored ~720 dash impulse)",
		"the dash contact dealt no big damage/heavy knockback (dealt " + str(damage_dealt) + " impulse " + str(hit_knockback[0]) + ", expected impulse >= 500)")
	charger.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## d. RECOVER: the post-dash follow-through is vulnerable -- COLD hitbox, no attack, and it takes a
## landed hit -- for recover_time, then it re-arms to TRACK. Driven via a direct _enter_recover() for
## deterministic timing (recover_time shrunk); the target is parked out of charge_range so the return to
## TRACK does not instantly re-commit to a new WINDUP.
func _recover_then_track(ctx: TestContext, charger_scene: PackedScene, player_scene: PackedScene) -> void:
	var charger: Charger = _spawn_charger(ctx, charger_scene, Vector2(66000, 66000))
	charger.recover_time = 0.12
	var target: Player = _spawn_player(ctx, player_scene, Vector2(66120, 66000)) as Player
	charger._target = target
	var charger_health: HealthComponent = charger.get_node("HealthComponent") as HealthComponent
	var charger_hurtbox: Hurtbox = charger.get_node("Hurtbox") as Hurtbox
	var sword: Hitbox = target.get_node("SwordPivot/Sword") as Hitbox
	await ctx.tree.physics_frame

	charger._enter_recover()   # drop straight into the vulnerable follow-through
	var in_recover: bool = charger._charger_state == Charger.ChargerState.RECOVER
	var cold: bool = charger._attack_shape.disabled and not charger._attacking
	var hp_before: int = charger_health.current_health
	charger_hurtbox._on_area_entered(sword)   # a punish hit lands on the exposed charger
	var took_hit: bool = charger_health.current_health < hp_before
	ctx.check(in_recover and cold and took_hit,
		"RECOVER is vulnerable: COLD hitbox, no attack, and a punish hit LANDS (" + str(hp_before) + " -> " + str(charger_health.current_health) + ")",
		"recover not vulnerable (recover=" + str(in_recover) + " cold=" + str(cold) + " hp " + str(hp_before) + " -> " + str(charger_health.current_health) + ")")

	# Park the target out of charge_range so the return to TRACK does not instantly re-wind-up.
	target.global_position = Vector2(66000, 80000)
	var back_to_track: bool = false
	for _i in range(20):
		await ctx.tree.physics_frame
		if charger._charger_state == Charger.ChargerState.TRACK:
			back_to_track = true
			break
	ctx.check(back_to_track,
		"after the recover window the Charger re-arms to TRACK",
		"charger did not return to TRACK (state=" + str(charger._charger_state) + ")")
	charger.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## Instantiate a free (non-stationary) Charger at `at` so its dash FSM runs.
func _spawn_charger(ctx: TestContext, scene: PackedScene, at: Vector2) -> Charger:
	var charger: Charger = scene.instantiate() as Charger
	charger.stationary = false
	ctx.tree.root.add_child(charger)
	charger.global_position = at
	return charger


## Instantiate a magnet-off Player stand-in target (real Hurtbox + Health + knockback) at `at`.
## pickup_radius 0 so it never auto-collects; input_override null so it never self-moves.
func _spawn_player(ctx: TestContext, scene: PackedScene, at: Vector2) -> Node2D:
	var p: Player = scene.instantiate() as Player
	p.pickup_radius = 0.0
	ctx.tree.root.add_child(p)
	p.global_position = at
	return p

# Verified against: Godot 4.7.1 (2026-07-19)
