class_name Tank
extends Enemy
## The Elephant-Tank (design-enemies.md "1. Elephant-Tank") -- a docile brute reworked from the
## training dummy. "Don't poke the bear": it ignores the player until struck, then wakes into a
## slow, relentless, brutally-telegraphed pursuit, and calms down again once left alone.
##
## FSM (its OWN, distinct from the base IDLE/CHASE/ATTACK chaser): GRAZE -> ENRAGED -> CALM -> GRAZE.
##   * GRAZE (default): turns to watch the nearest player but NEVER approaches or strikes it. The
##     "walk right past it" docility -- only a hit changes that.
##   * ENRAGED: entered by provoke() on ANY hit (hurtbox.hit_taken -> _on_hit_taken). Pursues at a
##     VERY slow move_speed and, in reach, throws a heavily TELEGRAPHED stomp (long wind-up -> a
##     brutal, huge-knockback hit that launches the player).
##   * CALM: entered when de-aggro fires (no new hit for deaggro_time AND target out of leash
##     range). Settles for calm_settle_time, then drops back to GRAZE.
##
## ARCHITECTURE (Phase 1 of the enemy roster): this is a SUBCLASS of Enemy. The base owns the shared
## tech -- HealthComponent/Hurtbox, movement + knockback + _apply_motion, flash, death lurch, the
## four-facing Avatar, target resolve, the telegraph_windup() helper, and the tick_deaggro() clock.
## The Tank supplies only its per-type AI here by overriding _physics_process + _on_hit_taken. Phase
## 2's Swordsman will plug in the SAME way (its own subclass, or a rework of the chaser FSM in
## enemy.gd), reusing telegraph_windup() + the provoke/de-aggro backbone.
##
## The training-dummy PIN is preserved verbatim: with `stationary = true` (dummy.tscn) the tank holds
## position and never faces / pursues / stomps -- so the durability-system test legs land repeated
## fixed-spot hits and leg h stays a solid body. Its combat/durability/health stats are UNCHANGED
## from the old dummy (def 4, armor 3, hardness 7, HP 12), so those legs' exact numbers still hold.

## The Tank's three behaviour states. Named apart from the base `State` enum so the two FSMs never
## clash (the base one is unused here -- _physics_process is fully overridden).
enum TankState { GRAZE, ENRAGED, CALM }

## Settle time in CALM before returning to GRAZE, in seconds. The other Tank knobs reuse the base
## exports: move_speed (pursuit -- set VERY slow), attack_range (stomp reach), attack_duration
## (stomp active window), attack_cooldown (between stomps), telegraph_time (stomp wind-up),
## detection_range (the de-aggro LEASH: ENRAGED persists while the target stays inside it),
## deaggro_time (calm-down delay). ATK + knockback are authored on the AttackHitbox in the scene.
@export var calm_settle_time: float = 0.6

var _tank_state: TankState = TankState.GRAZE
## True only during a stomp's wind-up (telegraph playing, hitbox still cold). Read by the Tank test
## to prove the wind-up precedes the damaging hit, and used to hold position mid-telegraph.
var _telegraphing: bool = false
var _calm_elapsed: float = 0.0


## Per-frame AI. Fully replaces the base chaser loop with the GRAZE/ENRAGED/CALM machine. Honors the
## same `stationary` pin as the base (identical hold-position + knockback-bleed early-out), so a
## pinned Tank is a byte-for-byte stand-in for the old dummy in the shared test fixture.
func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if stationary:
		# Pinned fixture (dummy.tscn): hold position, bleed knockback only. No facing, no pursuit,
		# no stomp -- the exact base-dummy behaviour the durability legs and leg h depend on.
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
		_apply_motion(delta)
		return

	_resolve_target()
	if _target == null:
		# No player in the tree: coast to a stop, hold GRAZE.
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
		_apply_motion(delta)
		return

	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	if dist > 0.001:
		_facing = to_target / dist
	if _facing.x > 0.0:
		_side_facing = 1
	elif _facing.x < 0.0:
		_side_facing = -1
	# Facing + Avatar track in EVERY state (a grazing beast still turns to watch you). The four-
	# facing look is driven here, before the FSM decides movement -- same rule as the base chaser.
	_avatar.update(_facing, _side_facing)

	match _tank_state:
		TankState.GRAZE:
			# Docile: ignore the player for movement/attack entirely. Just bleed to a stop.
			_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
		TankState.ENRAGED:
			# Slow, relentless pursuit; stomp when in reach.
			if dist <= attack_range:
				_move_velocity = Vector2.ZERO
				if not _attacking and not _on_cooldown and not _telegraphing:
					stomp()
			else:
				_move_velocity = _move_velocity.move_toward(_facing * move_speed, acceleration * delta)
			# Calm down after deaggro_time with no new hit AND the target beyond the leash
			# (detection_range). Never mid-attack -- a committed stomp always finishes first.
			var in_leash: bool = dist <= detection_range
			if not _attacking and not _telegraphing and tick_deaggro(delta, in_leash):
				_tank_state = TankState.CALM
				_calm_elapsed = 0.0
				print("[tank] calmed -> CALM (settling back to GRAZE)")
		TankState.CALM:
			# Brief settle, then back to docile GRAZE.
			_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
			_calm_elapsed += delta
			if _calm_elapsed >= calm_settle_time:
				_tank_state = TankState.GRAZE

	_apply_motion(delta)


## Provoke on ANY hit: keep the base knockback + death-lurch latching, then wake the brute. A hit
## while already ENRAGED just refreshes the de-aggro clock, so sustained fighting never lets it calm.
func _on_hit_taken(hitbox: Hitbox) -> void:
	super._on_hit_taken(hitbox)
	provoke()


## Turn hostile (GRAZE/CALM -> ENRAGED) and restart the calm-down countdown. Public so a hit -- or a
## test -- can wake it deterministically. Reuses the base de-aggro clock (reset_deaggro()).
func provoke() -> void:
	reset_deaggro()
	if _tank_state != TankState.ENRAGED:
		_tank_state = TankState.ENRAGED
		print("[tank] provoked -> ENRAGED")


## The telegraphed stomp (design-enemies.md): a long, readable wind-up with NO live hitbox
## (telegraph_windup), THEN the AttackHitbox goes live for attack_duration -- a brutal, huge-
## knockback hit that launches the player -- then a slow cooldown. Only ENRAGED calls it. Reuses the
## base AttackHitbox nodes; its brutal ATK + knockback are authored on that hitbox in the scene.
## Callable directly (the Tank test invokes it to prove the wind-up precedes the damaging hit).
func stomp() -> void:
	if _attacking or _on_cooldown or _telegraphing or is_dead:
		return
	# Aim the stomp at the target as the wind-up begins.
	if _target != null and is_instance_valid(_target):
		var to_target: Vector2 = _target.global_position - global_position
		if to_target.length() > 0.001:
			_facing = to_target.normalized()
	_attack_hitbox.rotation = _facing.angle()
	_move_velocity = Vector2.ZERO

	# WIND-UP: the fair warning. Hitbox stays cold for the whole telegraph.
	_telegraphing = true
	await telegraph_windup(telegraph_time)
	if not is_instance_valid(self) or is_dead:
		_telegraphing = false
		return
	_telegraphing = false

	# STRIKE: hitbox live for the window -> the launch.
	_attacking = true
	_attack_shape.disabled = false
	_attack_visual.visible = true
	await get_tree().create_timer(attack_duration).timeout
	if not is_instance_valid(self):
		return
	if is_instance_valid(_attack_shape):
		_attack_shape.disabled = true
	if is_instance_valid(_attack_visual):
		_attack_visual.visible = false
	_attacking = false

	# RECOVERY: slow cooldown between stomps.
	_on_cooldown = true
	await get_tree().create_timer(attack_cooldown).timeout
	if not is_instance_valid(self):
		return
	_on_cooldown = false

# Verified against: Godot 4.7.1 (2026-07-19)
