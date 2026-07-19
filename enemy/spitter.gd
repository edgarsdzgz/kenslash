class_name Spitter
extends Enemy
## The Spitter (design-enemies.md "4. Spitter") -- a fragile RANGED KITER, Phase 4 (final) of the enemy
## roster. It never wants to touch you: it holds a preferred distance and lobs a slow Projectile on a
## cadence, so the fight is about CLOSING the gap while dodging shots (or cornering it), not trading
## melee. LOW HP + low DEF -- punished hard the moment you reach it.
##
## FSM (its OWN, distinct from the base IDLE/CHASE/ATTACK chaser, the Tank's GRAZE/ENRAGED/CALM, and the
## Charger's TRACK/WINDUP/CHARGE/RECOVER): REPOSITION -> AIM -> FIRE -> REPOSITION.
##   * REPOSITION -- the kiting core. Each frame it maintains `preferred_range`: BACKS AWAY if the
##     player is inside (preferred_range - range_deadband), APPROACHES if beyond
##     (preferred_range + range_deadband), otherwise STRAFES sideways (circling to hold the line). Once
##     the fire clock has reached `fire_interval` AND the player is within `fire_range`, it commits: -> AIM.
##   * AIM     -- a brief readable wind-up (`aim_time`, the shared telegraph_windup flash tell): it STOPS
##     and telegraphs so the shot is fair to dodge. The FSM timer -- not the awaited tween -- drives the
##     commit, so the deterministic test steps frames straight through it.
##   * FIRE    -- spawns a Projectile aimed at the player's CURRENT position, resets the fire clock, and
##     returns to REPOSITION next frame. The shot is added to the PARENT (a world sibling), never
##     parented to the Spitter, so the Spitter dying does NOT kill an in-flight shot.
##
## ARCHITECTURE (Phase 4 of the enemy roster): a SUBCLASS of Enemy, mirroring tank.gd / swordsman.gd /
## charger.gd. The base owns the shared tech -- HealthComponent/Hurtbox, movement + knockback +
## _apply_motion, flash, death lurch, the four-facing Avatar, target resolve, and telegraph_windup().
## The Spitter supplies only its per-type kiting/firing AI here by overriding _physics_process (the base
## chaser loop is fully replaced). Its contact AttackHitbox (present in the scene so the base _ready
## wiring holds) stays COLD forever -- all its offense is the Projectile. It is a STANDALONE type used
## via enemy/spitter.tscn (+ tests/test_spitter.gd), NOT wired into chunk generation this phase (which
## enemy spawns where is a later "encounter variety" call), so chunk_content.gd is untouched.
##
## The `stationary` PIN is honored verbatim (same early-out as the base and the other types): a pinned
## Spitter holds position and never kites / aims / fires -- just a passive knockback-bleeding target --
## for robustness in any shared fixture.

## The reusable shot (enemy/projectile.tscn). preload so a fired shot is deterministic and needs no
## scene wiring; spawned as a sibling under get_parent(), aimed at the player.
const PROJECTILE_SCENE: PackedScene = preload("res://enemy/projectile.tscn")

## The Spitter's three kiting/firing states. Named apart from the base `State` enum so the two FSMs
## never clash (the base one is unused here -- _physics_process is fully overridden).
enum SpitterState { REPOSITION, AIM, FIRE }

## --- Kiting + firing knobs (design-enemies.md "4. Spitter"; the difficulty levers) --------------
## The distance in px the Spitter tries to hold from the player -- the heart of the kite.
@export var preferred_range: float = 220.0
## Half-width of the neutral band around preferred_range: inside it the Spitter neither advances nor
## retreats, it just STRAFES. Stops jitter from micro-corrections right at the preferred ring.
@export var range_deadband: float = 40.0
## Max distance in px from which it will commit to AIM/FIRE (its effective shooting reach). Beyond this
## it repositions but holds fire.
@export var fire_range: float = 340.0
## Seconds between shots -- the fire cadence (~1.5s). The fire clock ticks in REPOSITION.
@export var fire_interval: float = 1.5
## Seconds of readable AIM wind-up before the shot leaves (the telegraph tell). The shared
## telegraph_time base export is unused by the Spitter; this is its own aim window.
@export var aim_time: float = 0.35
## Fraction of move_speed used while STRAFING (sideways is a lighter, circling drift, not a full sprint).
@export var strafe_speed_frac: float = 0.6
## Projectile tuning: straight-line speed (px/sec, kept SLOW so it is dodgeable), ATK (the moderate
## ranged damage), and knockback impulse. These are the shot's difficulty levers.
@export var projectile_speed: float = 150.0
@export var projectile_atk: int = 2
@export var projectile_knockback: float = 120.0
## Distance in px ahead of the Spitter the shot spawns (a little muzzle offset so it clears the body).
@export var muzzle_offset: float = 16.0

## Current kiting/firing state. Public so the test can drive/read it deterministically.
var _spitter_state: SpitterState = SpitterState.REPOSITION
## Seconds elapsed in the current AIM state -- drives the timed AIM -> FIRE transition.
var _state_elapsed: float = 0.0
## Seconds since the last shot -- ticks in REPOSITION; once >= fire_interval (and in range) it fires.
var _fire_elapsed: float = 0.0
## Which way it currently strafes: +1 or -1 (a perpendicular circling drift). Fixed per instance so it
## circles one way -- natural kiting, and it never runs off in a straight line (perpendicular motion
## holds the radial distance near preferred_range).
var _strafe_dir: int = 1
## True only during the AIM tell (telegraph playing, no shot yet). Read by the test to prove the aim
## wind-up precedes the shot.
var _aiming: bool = false


## Per-frame kiting/firing AI. The shared _sense() preamble (base) runs the dead / stationary-pin /
## no-target early-outs and the facing + Avatar pass; this supplies only the REPOSITION/AIM/FIRE machine
## on top. The stationary pin is honored by _sense (identical hold-position + knockback-bleed); the
## reset-to-REPOSITION-when-the-target-vanishes seam lives in the _on_no_target() override below.
func _physics_process(delta: float) -> void:
	var sense: Dictionary = _sense(delta)
	if not sense["act"]:
		return
	var dist: float = sense["dist"]

	match _spitter_state:
		SpitterState.REPOSITION:
			# Kite: maintain preferred_range (back away / approach / strafe), and tick toward the next shot.
			_do_kiting(dist, delta)
			_fire_elapsed += delta
			if _fire_elapsed >= fire_interval and dist <= fire_range:
				_enter_aim()
		SpitterState.AIM:
			# Stop and telegraph; the FSM timer drives the commit to FIRE.
			_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
			_state_elapsed += delta
			if _state_elapsed >= aim_time:
				_enter_fire()
		SpitterState.FIRE:
			# The shot was spawned on entry; return to kiting immediately.
			_enter_reposition()

	_apply_motion(delta)


## The kiting movement (design-enemies.md): steer toward a target velocity that maintains preferred_range
## -- retreat when too close, close when too far, else strafe sideways to hold the line. Ramped through
## acceleration so it eases rather than snaps.
func _do_kiting(dist: float, delta: float) -> void:
	var target_vel: Vector2
	if dist < preferred_range - range_deadband:
		target_vel = -_facing * move_speed              # too close: BACK AWAY
	elif dist > preferred_range + range_deadband:
		target_vel = _facing * move_speed               # too far: APPROACH
	else:
		var perp: Vector2 = Vector2(-_facing.y, _facing.x) * float(_strafe_dir)
		target_vel = perp * move_speed * strafe_speed_frac  # in the band: STRAFE / circle
	_move_velocity = _move_velocity.move_toward(target_vel, acceleration * delta)


## Base _sense() seam: reset to REPOSITION the frame the target goes null, so a reappearing player is
## kited fresh rather than resumed mid-aim (verbatim the old no-target branch).
func _on_no_target() -> void:
	_spitter_state = SpitterState.REPOSITION


## REPOSITION -> AIM: STOP and start the readable aim tell (fire-and-forget flash; the FSM timer owns the
## transition). Public transition path; the test can call it directly.
func _enter_aim() -> void:
	_spitter_state = SpitterState.AIM
	_state_elapsed = 0.0
	_move_velocity = Vector2.ZERO
	_aiming = true
	telegraph_windup(aim_time)


## AIM -> FIRE: spawn the shot aimed at the player's CURRENT position and reset the fire clock. Callable
## directly.
func _enter_fire() -> void:
	_spitter_state = SpitterState.FIRE
	_aiming = false
	_fire_elapsed = 0.0
	_spawn_projectile()


## FIRE -> REPOSITION: back to kiting. Callable directly.
func _enter_reposition() -> void:
	_spitter_state = SpitterState.REPOSITION
	_state_elapsed = 0.0


## Instance the reusable Projectile as a WORLD SIBLING (under get_parent(), NOT a child of the Spitter,
## so the Spitter's own death never kills an in-flight shot), position it at the muzzle, and arm it aimed
## at the player. Aim is re-read here so a target that moved during the AIM tell is tracked to the shot.
func _spawn_projectile() -> void:
	var parent: Node = get_parent()
	if parent == null or is_dead:
		return
	var aim_dir: Vector2 = _facing
	if _target != null and is_instance_valid(_target):
		var to_t: Vector2 = _target.global_position - global_position
		if to_t.length() > 0.001:
			aim_dir = to_t.normalized()
	var proj: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	parent.add_child(proj)
	proj.global_position = global_position + aim_dir * muzzle_offset
	proj.setup(aim_dir, projectile_speed, projectile_atk, projectile_knockback)

# Verified against: Godot 4.7.1 (2026-07-19)
