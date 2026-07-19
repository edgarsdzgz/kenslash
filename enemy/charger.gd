class_name Charger
extends Enemy
## The Charger (design-enemies.md "3. Charger") -- a dash-bruiser, Phase 3 of the enemy roster. Not a
## beeline chaser and not a stand-and-swing dueler: it stalks at a SLOW walk, STOPS to telegraph a
## committed dash, then DASHES fast in a STRAIGHT line PAST where you were, and is left stunned +
## vulnerable in the follow-through. A threat you READ (sidestep the tell / the line) and PUNISH (the
## recovery), never out-DPS.
##
## FSM (its OWN, distinct from the base IDLE/CHASE/ATTACK chaser, the Tank's GRAZE/ENRAGED/CALM, and
## the Swordsman's spacing machine): TRACK -> WINDUP -> CHARGE -> RECOVER -> TRACK.
##   * TRACK   -- pursue the player at a SLOW walk (move_speed, set low). Once within charge_range it
##                commits to a dash: -> WINDUP. (charge_min_range keeps it from winding up point-blank.)
##   * WINDUP  -- STOP + telegraph for telegraph_time (~0.6s, the shared telegraph_windup flash tell)
##                while LOCKING the charge line toward the player's position AT THIS MOMENT. The dash
##                commits to that bearing -- it does NOT re-home -- so a sidestep during the tell beats
##                it. The AttackHitbox stays COLD for the whole wind-up (no damage during the tell).
##   * CHARGE  -- DASH fast (charge_speed) in a STRAIGHT line along the locked _charge_dir for a fixed
##                charge_distance, OVERSHOOTING past where the player was. The AttackHitbox is LIVE the
##                whole dash -> its high ATK + big knockback launch anything it runs through.
##   * RECOVER -- ~recover_time (~1s) stunned + vulnerable: no attack (COLD hitbox), easy to punish,
##                then back to TRACK to line up the next dash.
##
## ARCHITECTURE (Phase 3 of the enemy roster): a SUBCLASS of Enemy, mirroring enemy/tank.gd (Phase 1)
## and enemy/swordsman.gd (Phase 2). The base owns the shared tech -- HealthComponent/Hurtbox, movement
## + knockback + _apply_motion, flash, death lurch, the four-facing Avatar, target resolve, and the
## telegraph_windup() helper. The Charger supplies only its per-type dash AI here by overriding
## _physics_process (the base chaser loop is fully replaced). It is a STANDALONE type used via its own
## enemy/charger.tscn (and tests/test_charger.gd) -- NOT wired into chunk generation this phase; which
## enemy types spawn where is a later "encounter variety" decision, so chunk_content.gd is untouched.
##
## The `stationary` PIN is honored verbatim (same early-out as the base and the other types): a pinned
## Charger holds position and never tracks / winds up / dashes -- just a passive knockback-bleeding
## target -- for robustness in any shared fixture.

## The Charger's four dash-cycle states. Named apart from the base `State` enum so the two FSMs never
## clash (the base one is unused here -- _physics_process is fully overridden).
enum ChargerState { TRACK, WINDUP, CHARGE, RECOVER }

## --- Charge knobs (design-enemies.md "3. Charger"; the difficulty levers) -----------------------
## Distance in px at which TRACK commits to a dash (STOP + telegraph). The engage ring.
@export var charge_range: float = 160.0
## Too-close floor in px: inside this it does NOT wind up (a dash needs room to build; point-blank it
## keeps tracking instead of committing to a whiff).
@export var charge_min_range: float = 26.0
## Dash speed in px/sec -- FAST (well above move_speed and the player's 140, so the dash reads as a
## committed lunge you dodge, not a chase you outrun).
@export var charge_speed: float = 430.0
## Fixed dash length in px. Set LONGER than charge_range so the dash OVERSHOOTS past where the player
## was -- the straight-line follow-through that leaves it exposed. Not homing.
@export var charge_distance: float = 210.0
## Stunned + vulnerable follow-through after a dash, in seconds (~1s). The punish window. The wind-up
## uses the base `telegraph_time` (set ~0.6 on the scene); move_speed is the SLOW walk. These four are
## the difficulty knobs (wind-up time, dash speed, dash distance, recover time).
@export var recover_time: float = 1.0

## Current dash-cycle state. Public so the test can drive/read it deterministically.
var _charger_state: ChargerState = ChargerState.TRACK
## Seconds elapsed in the current state -- drives the WINDUP / RECOVER timed transitions.
var _state_elapsed: float = 0.0
## The LOCKED dash bearing, fixed at WINDUP start toward the player's position then. CHARGE commits to
## this -- it never re-homes -- so a sidestep during the tell dodges the dash.
var _charge_dir: Vector2 = Vector2.RIGHT
## Position captured at CHARGE start; the dash ends once it has travelled charge_distance from here.
var _charge_start: Vector2 = Vector2.ZERO
## True only during the WINDUP tell (telegraph playing, hitbox still COLD). Read by the test to prove
## the wind-up precedes the live hitbox and no damage lands during the tell.
var _telegraphing: bool = false


## Per-frame dash AI. Fully replaces the base chaser loop with the TRACK/WINDUP/CHARGE/RECOVER machine.
## Honors the same `stationary` pin as the base (identical hold-position + knockback-bleed early-out).
func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if stationary:
		# Pinned passive target: hold position, bleed knockback only. No tracking / wind-up / dash.
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
		_apply_motion(delta)
		return

	_resolve_target()
	if _target == null:
		# No player in the tree (freed/absent): coast to a stop, hold TRACK.
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
		_charger_state = ChargerState.TRACK
		_apply_motion(delta)
		return

	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	if dist > 0.001:
		_facing = to_target / dist
	# While dashing the body commits to the LOCKED bearing, not the (now stale) live target direction --
	# the four-facing look points along the charge, reinforcing "it's going THAT way, not at you now".
	if _charger_state == ChargerState.CHARGE:
		_facing = _charge_dir
	if _facing.x > 0.0:
		_side_facing = 1
	elif _facing.x < 0.0:
		_side_facing = -1
	# The four-facing look tracks every state -- same rule as the base chaser, the Tank and the Swordsman.
	_avatar.update(_facing, _side_facing)

	_state_elapsed += delta
	match _charger_state:
		ChargerState.TRACK:
			# Slow walk toward the player; commit to a dash once inside the engage ring (but not point-blank).
			if dist <= charge_range and dist >= charge_min_range:
				_enter_windup()
			else:
				_move_velocity = _move_velocity.move_toward(_facing * move_speed, acceleration * delta)
		ChargerState.WINDUP:
			# STOP and telegraph; the base timer drives the commit. Bearing was locked on entry.
			_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
			if _state_elapsed >= telegraph_time:
				_enter_charge()
		ChargerState.CHARGE:
			# Straight-line dash along the locked bearing (NO acceleration ramp -- instant commit), until
			# it has overshot charge_distance past the start point.
			_move_velocity = _charge_dir * charge_speed
			if global_position.distance_to(_charge_start) >= charge_distance:
				_enter_recover()
		ChargerState.RECOVER:
			# Stunned + vulnerable: bleed to a stop, no attack, then re-arm.
			_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
			if _state_elapsed >= recover_time:
				_enter_track()

	_apply_motion(delta)


## TRACK -> WINDUP: STOP, lock the dash line toward the player's CURRENT position (design-enemies.md:
## the dash commits to THIS bearing and never re-homes), aim the (still COLD) hitbox down it, and fire
## the readable wind-up flash. The state timer -- not the awaited tween -- drives the commit, so the
## deterministic test can step frames to CHARGE. Public transition path; the test calls it directly.
func _enter_windup() -> void:
	_charger_state = ChargerState.WINDUP
	_state_elapsed = 0.0
	_move_velocity = Vector2.ZERO
	if _target != null and is_instance_valid(_target):
		var to_t: Vector2 = _target.global_position - global_position
		if to_t.length() > 0.001:
			_charge_dir = to_t.normalized()
	_attack_hitbox.rotation = _charge_dir.angle()
	_telegraphing = true
	# Fire-and-forget flash tell (COLD hitbox for the whole tell); the FSM timer owns the transition.
	telegraph_windup(telegraph_time)


## WINDUP -> CHARGE: capture the dash origin, aim + go LIVE on the AttackHitbox (high ATK + big
## knockback authored on the scene), and stamp the dash direction onto the hitbox. Callable directly.
func _enter_charge() -> void:
	_charger_state = ChargerState.CHARGE
	_state_elapsed = 0.0
	_telegraphing = false
	_charge_start = global_position
	_attack_hitbox.rotation = _charge_dir.angle()
	_attacking = true
	_attack_shape.disabled = false
	_attack_visual.visible = true


## CHARGE -> RECOVER: kill the dash, go COLD, and hand off to the vulnerable follow-through. Callable
## directly.
func _enter_recover() -> void:
	_charger_state = ChargerState.RECOVER
	_state_elapsed = 0.0
	_move_velocity = Vector2.ZERO
	_attacking = false
	if is_instance_valid(_attack_shape):
		_attack_shape.disabled = true
	if is_instance_valid(_attack_visual):
		_attack_visual.visible = false


## RECOVER -> TRACK: re-arm to line up the next dash. Callable directly.
func _enter_track() -> void:
	_charger_state = ChargerState.TRACK
	_state_elapsed = 0.0

# Verified against: Godot 4.7.1 (2026-07-19)
