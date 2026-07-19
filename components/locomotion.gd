class_name Locomotion
extends RefCounted
## Movement + sprint + dodge subsystem, extracted from player.gd (design-controls.md) to keep the
## player under its line cap -- same RefCounted "call down" pattern as components/combat.gd. Owns
## the controlled move-velocity (_move_velocity, exposed back through a player facade so tests and
## _respawn_in_place keep reading player._move_velocity), the HOLD-sprint speed multiply, and the
## DODGE dash (a short high-speed burst with i-frames + enemy phase-through).
##
## RefCounted, NOT a Node -- like every other components/*.gd -- so it never bumps the streaming
## node-count / orphan baseline. It "calls up" to the player for the movement tunables (max_speed /
## acceleration / friction), the live encumbrance factor, and `facing`, and it "calls down" onto the
## player's Hurtbox (dodge i-frames) and its own Stamina ref (sprint drain / dodge spend / gating).
##
## The player's _simulate stays the orchestrator (facing, side_facing, avatar, knockback, attack);
## it delegates ONLY the velocity computation here via simulate(), then adds knockback and calls
## move_and_slide itself.

## Sprint speed multiplier, applied ON TOP of the already-encumbrance-scaled walk speed (weight
## always matters: overloaded-sprint < light-sprint, overloaded-sprint > overloaded-walk).
const SPRINT_MULT: float = 1.5
## Dodge dash duration in seconds -- a tiny burst, not a sustained run.
const DODGE_TIME: float = 0.18
## Dodge dash speed in px/sec. 320 * 0.18s ~= 58 px ~= 1.3 tiles (WorldScale.TILE 40) -- well
## above the 140 walk speed so the dash reads as a distinct lunge, not a fast step.
const DODGE_SPEED: float = 320.0
## Cooldown after a dash before another dodge may start (gates dodge-spam).
const DODGE_COOLDOWN: float = 0.4
## Seconds between afterimage "ghost" drops while dashing (components/dash_trail.gd). ~0.05s over the
## 0.18s dash yields ~3-4 ghosts along the path (plus the one dropped at dash start). VISUAL ONLY --
## the cadence never touches the dash mechanics.
const GHOST_INTERVAL: float = 0.05

## Controlled movement velocity (walk / sprint / dash), kept separate from the player's knockback
## so the two never compound. Exposed via the player's _move_velocity facade (get+set).
var _move_velocity: Vector2 = Vector2.ZERO
## True while a dodge dash is in flight; gates re-entry and drives the velocity override.
var _dodging: bool = false
## Seconds left in the current dash; when it reaches 0 the dash ends and the cooldown starts.
var _dodge_time_left: float = 0.0
## Seconds left on the post-dash cooldown; a dodge is blocked while > 0.
var _dodge_cooldown_left: float = 0.0
## Locked-in dash direction (captured at dash start from move input, else facing).
var _dodge_dir: Vector2 = Vector2.RIGHT
## The player's collision_mask saved at dash start and restored at dash end, so the phase-through
## (clearing the enemy-body bit) never loses the world bit or leaks past the dash.
var _saved_mask: int = 0
## Time accumulated toward the next afterimage drop while dashing (components/dash_trail.gd). Reset
## at dash start; ghosts drop each time it crosses GHOST_INTERVAL. Purely a VISUAL cadence clock.
var _ghost_accum: float = 0.0

## The player CharacterBody2D (host): read max_speed / acceleration / friction / facing and the
## live inventory.encumbrance_factor() off it, and toggle its collision_mask for phase-through.
var _player: CharacterBody2D = null
## The player's Hurtbox -- its dodge_invincible flag is raised for the dash (i-frames) and lowered
## after, without touching the normal post-hit i-frame timer.
var _hurtbox: Hurtbox = null
## The player's avatar Body Polygon2D -- the afterimage ghosts copy its CURRENT polygon / color /
## scale.x each drop (components/dash_trail.gd). VISUAL source only; never written here.
var _body: Polygon2D = null
## The player's Stamina pool -- sprint drains it per frame, a dodge spends dodge_cost, and
## can_sprint() / current gate both.
var _stamina: Stamina = null


## Wire the host + the player's Hurtbox + the shared Stamina pool + the avatar Body (the player
## "calls down" in its _ready, after it creates the Stamina). The Body is the VISUAL source the dash
## afterimages copy; it is read, never written. Mirrors Combat.setup().
func setup(player: CharacterBody2D, hurtbox: Hurtbox, stamina: Stamina, body: Polygon2D) -> void:
	_player = player
	_hurtbox = hurtbox
	_stamina = stamina
	_body = body
	_saved_mask = player.collision_mask


## Advance the controlled velocity one tick from the input struct and the current facing. Returns
## whether stamina was CONSUMED this frame (sprinting or dashing) so the player can gate regen.
## Three exclusive modes: (1) already dashing -> ride the dash; (2) a fresh dodge press that passes
## the gates -> start a dash this frame; (3) otherwise -> the normal encumbrance-scaled walk, with
## the hold-sprint multiply when held+moving+able.
func simulate(delta: float, input: FrameInput, facing: Vector2) -> bool:
	# Cooldown bleeds down only while NOT dashing (it starts the instant a dash ends).
	if not _dodging and _dodge_cooldown_left > 0.0:
		_dodge_cooldown_left = maxf(0.0, _dodge_cooldown_left - delta)

	if _dodging:
		return _tick_dash(delta)

	if input.dodge and not _dodging and _dodge_cooldown_left <= 0.0 and _stamina.current >= _stamina.dodge_cost:
		_start_dash(input, facing)
		return true

	return _walk(delta, input)


## Normal ground movement: accelerate the controlled velocity toward the encumbrance-scaled target
## (or decay to zero with no input), applying the sprint multiply when the sprint action is held,
## the player is actually moving, and stamina allows. Sprinting drains stamina and returns true.
func _walk(delta: float, input: FrameInput) -> bool:
	if input.move == Vector2.ZERO:
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, _player.friction * delta)
		return false
	var sprinting: bool = input.sprint and _stamina.can_sprint()
	# Encumbrance STACKS multiplicatively: weight scales the walk target first, then sprint x1.5.
	var target_speed: float = _player.max_speed * _player.inventory.encumbrance_factor()
	if sprinting:
		target_speed *= SPRINT_MULT
	_move_velocity = _move_velocity.move_toward(input.move * target_speed, _player.acceleration * delta)
	if sprinting:
		_stamina.drain(_stamina.sprint_drain * delta)
	return sprinting


## Begin a dodge dash: spend the flat cost, lock the direction (move input if any, else facing),
## raise the dash i-frames, and clear the ENEMY-body bit from the player's collision_mask so the
## dash phases THROUGH enemies while KEEPING world collision (rocks/trees). The mask is saved first
## and restored when the dash ends. The player's blade/attack state is untouched (no dodge-cancel).
func _start_dash(input: FrameInput, facing: Vector2) -> void:
	_stamina.try_spend(_stamina.dodge_cost)
	_dodging = true
	_dodge_time_left = DODGE_TIME
	_dodge_dir = input.move.normalized() if input.move != Vector2.ZERO else facing.normalized()
	if _dodge_dir == Vector2.ZERO:
		_dodge_dir = Vector2.RIGHT
	_saved_mask = _player.collision_mask
	# Enemy bodies live on physics layer 3 (bit value 4, "enemy_body"); clearing it lets the dash
	# pass through them while the world bit (1) still blocks rocks/trees.
	_player.collision_mask &= ~4
	_hurtbox.dodge_invincible = true
	# VISUAL ONLY (design-controls.md dash read): a kick-off dust puff at the launch point + the first
	# afterimage ghost, both spawned as WORLD SIBLINGS that self-free. This touches no dash mechanic
	# (distance / i-frames / stamina / cooldown are all set above and unaffected).
	_ghost_accum = 0.0
	DustBurst.burst_at(_player.get_parent(), _player.global_position)
	DashTrail.spawn_ghost(_player, _body)


## Ride an in-flight dash: drive the controlled velocity at DODGE_SPEED along the locked direction,
## count the timer down, and end the dash (restore mask + i-frames, start the cooldown) when it
## expires. Always consuming (returns true) so regen stays paused across the dash.
func _tick_dash(delta: float) -> bool:
	_move_velocity = _dodge_dir * DODGE_SPEED
	# VISUAL ONLY: drop an afterimage ghost every GHOST_INTERVAL along the path (world sibling, self-
	# frees). Runs off a cadence clock, so it never perturbs the dash timer / distance below.
	_ghost_accum += delta
	while _ghost_accum >= GHOST_INTERVAL:
		_ghost_accum -= GHOST_INTERVAL
		DashTrail.spawn_ghost(_player, _body)
	_dodge_time_left -= delta
	if _dodge_time_left <= 0.0:
		_end_dash()
	return true


## Finish a dash: drop the i-frames, restore the saved collision_mask (re-enabling enemy-body
## collision), clear the dash flag, and open the cooldown. The residual velocity decays through the
## normal walk/friction path next frame.
func _end_dash() -> void:
	_dodging = false
	_dodge_time_left = 0.0
	_dodge_cooldown_left = DODGE_COOLDOWN
	_hurtbox.dodge_invincible = false
	_player.collision_mask = _saved_mask


## Hard-reset the locomotion state -- called from the player's _respawn_in_place so a respawn during
## a dash cannot leave phased collision or latched i-frames behind. Restores the mask/i-frames if a
## dash was live, then clears all motion + dodge state.
func reset() -> void:
	if _dodging:
		_hurtbox.dodge_invincible = false
		_player.collision_mask = _saved_mask
	_dodging = false
	_dodge_time_left = 0.0
	_dodge_cooldown_left = 0.0
	_move_velocity = Vector2.ZERO

# Verified against: Godot 4.7.1 (2026-07-19)
