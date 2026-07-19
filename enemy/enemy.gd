class_name Enemy
extends CharacterBody2D
## A melee enemy that hunts the player. A three-state machine (IDLE -> CHASE ->
## ATTACK) drives it: idle until the player is seen, chase until in reach, then
## stop and swing a time-windowed attack hitbox on a cooldown. It still carries a
## HealthComponent + Hurtbox (it takes the player's slash) and dies at 0 HP.
##
## The state machine is an enum+match in this one script, which state-machines.md
## calls right-sized for 3-4 simple states. Upgrade path when more enemy types
## arrive with per-state enter/exit hooks or exported per-state tuning: refactor
## to the node-based FSM (StateMachine node + one State child per state).

enum State { IDLE, CHASE, ATTACK }

## Shared telegraph tint (design-enemies.md "Telegraph -> strike"): the readable amber warning
## an attack pulses on its Body during a wind-up, before its hitbox goes live. Amber so it reads
## apart from the white hit-flash and the reddish AttackVisual. Reused by every telegraphed
## attack (the Tank's stomp now; the Charger's wind-up in a later phase).
const TELEGRAPH_COLOR: Color = Color(1.0, 0.75, 0.15, 1.0)

## Player is noticed (IDLE -> CHASE) once inside this radius, in pixels.
@export var detection_range: float = 180.0
## Close enough to swing (CHASE -> ATTACK), in pixels.
@export var attack_range: float = 34.0
## Chase speed. Deliberately below the player's 140 so the player can kite.
@export var move_speed: float = 70.0
## How fast chase velocity ramps toward move_speed, in pixels/sec^2.
@export var acceleration: float = 600.0
## How fast velocity bleeds to zero when idle, in pixels/sec^2.
@export var friction: float = 800.0
## How long the attack hitbox stays live per swing, in seconds.
@export var attack_duration: float = 0.15
## Recovery after a swing before another can start, in seconds.
@export var attack_cooldown: float = 0.8
## How fast a knockback impulse bleeds back to zero, in pixels/sec^2.
@export var knockback_decay: float = 1400.0
## How far the corpse jerks in the direction of the killing blow before stopping
## abruptly (the death lurch), in pixels.
@export var death_lurch_distance: float = 26.0
## If true, this is a training dummy: it never chases or attacks (holds position),
## but still takes damage, knockback, flash, and death. For a stationary target.
@export var stationary: bool = false
## Flesh baseline this enemy's Hurtbox drops to when its armor breaks (design-
## durability.md). Only meaningful if an optional `Armor` DurabilityComponent child
## exists; a bare flesh enemy has no armor and its Hurtbox keeps its scene values.
@export var flesh_def: int = 1
@export var flesh_hardness: int = 2
## Shared aggro knobs (design-enemies.md "Aggro / provoke states") -- the fairness backbone reused
## by every PASSIVE enemy type (the Tank now; Charger/Spitter later). The IDLE/CHASE/ATTACK chaser
## predates the passive model and leaves them unused, so setting them here is inert for enemy.tscn.
## Seconds of readable wind-up a telegraphed strike plays before its hitbox goes live.
@export var telegraph_time: float = 0.9
## Seconds a provoked passive type stays hostile with NO new hit AND the target out of leash range
## before it calms back to its passive state. See tick_deaggro().
@export var deaggro_time: float = 6.0

## Set true the instant the enemy dies. A headless test reads this instead of
## racing queue_free()'s deferred deletion.
var is_dead: bool = false
## Latched once the death sequence starts, so a second `died` cannot re-trigger it.
var _dying: bool = false

var _state: State = State.IDLE
## Last direction toward the target; aims the attack hitbox like the sword. Full
## 8-directional -- unaffected by the body-facing rule below.
var _facing: Vector2 = Vector2.RIGHT
## Last SIDE (left/right) the enemy faced: +1 = right, -1 = left. Drives ONLY the
## Body's left/right flip -- does NOT change when the target is directly above or
## below (no x component), so the body never flips on vertical-only alignment.
var _side_facing: int = 1
## Direction the killing blow pushed us -- the death lurch flies this way. Defaults
## outward-right until an actual hit sets it from the striking hitbox.
var _last_hit_dir: Vector2 = Vector2.RIGHT
var _attacking: bool = false
var _on_cooldown: bool = false
var _target: Node2D = null
## Controlled movement velocity, kept separate from knockback so the two do not
## compound frame to frame.
var _move_velocity: Vector2 = Vector2.ZERO
## Decaying knockback impulse, added on top of movement.
var _knockback: Vector2 = Vector2.ZERO
## Shared de-aggro clock (design-enemies.md): time accumulated with the target continuously out of
## contact. Reset on every new hit / in-contact frame; drives the calm-down. See tick_deaggro().
var _deaggro_elapsed: float = 0.0

@onready var _body: Polygon2D = $Body
## The DOWN-facing "face" circle, a child of Body so it rides its visibility + modulate.
@onready var _face: Polygon2D = $Body/Face
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _attack_hitbox: Area2D = $AttackHitbox
@onready var _attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
## Semi-transparent overlay showing the attack reach during a swing (reddish, so
## it reads apart from the player's yellow sword).
@onready var _attack_visual: Polygon2D = $AttackHitbox/AttackVisual
## Optional worn armor (an armored dummy). Present only if the scene has an `Armor`
## DurabilityComponent child; null for a bare flesh enemy.
@onready var _armor: DurabilityComponent = get_node_or_null("Armor")

## Four-facing look (components/avatar.gd): RefCounted like the player's, made in _ready; drives
## the Body shape/flip + Face per facing. Shared verbatim with the player -- one facing rule.
var _avatar: Avatar = null


func _ready() -> void:
	# Parent wires its own components together ("call down"); the Hurtbox never
	# reaches for the HealthComponent on its own.
	_hurtbox.health = _health
	# Four-facing avatar (components/avatar.gd), the SAME component + call-down the player uses. A
	# RefCounted (NOT a child node -- a node would perturb the streaming node-count anchor). "Call
	# down" the Body + its Face child; _physics_process calls _avatar.update() each frame (except
	# a stationary dummy, which returns early and keeps its authored D-shape, unchanged).
	_avatar = Avatar.new()
	_avatar.setup(_body, _face)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	# Take knockback when the player's slash lands.
	_hurtbox.hit_taken.connect(_on_hit_taken)
	# If armored, hand the Hurtbox the armor to wear and react to its break by
	# dropping def/hardness to the flesh baseline (System 2, design-durability.md).
	if _armor != null:
		_hurtbox.armor = _armor
		_armor.broke.connect(_on_armor_broke)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if stationary:
		# Training dummy: hold position, but still slide from knockback and decay it.
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
		_apply_motion(delta)
		return

	_resolve_target()
	if _target == null:
		# No player in the tree (freed/absent): coast to a stop, stay idle.
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
		_state = State.IDLE
		_apply_motion(delta)
		return

	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	if dist > 0.001:
		_facing = to_target / dist
	# The Body's D-shape is a LEFT/RIGHT FLIP via scale.x = +/-1 (a true horizontal
	# mirror). NOT rotation: a 180deg rotation flips the base-anchored polygon
	# vertically too, shifting it down-screen. _side_facing only updates when the
	# target has an x offset -- directly-above/below alignment leaves it untouched, so
	# the body never flips on vertical-only alignment. _facing (full direction, used to
	# aim the attack hitbox) still updates above, unchanged.
	if _facing.x > 0.0:
		_side_facing = 1
	elif _facing.x < 0.0:
		_side_facing = -1
	# Four-facing look: horizontal keeps the D-shape flipped by _side_facing (unchanged); pure
	# up/down swaps in the rectangle body (and, facing DOWN, shows the face) -- see avatar.gd.
	_avatar.update(_facing, _side_facing)

	match _state:
		State.IDLE:
			_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
			if dist <= detection_range:
				_state = State.CHASE
		State.CHASE:
			if dist > detection_range:
				_state = State.IDLE
			elif dist <= attack_range:
				_move_velocity = Vector2.ZERO
				_state = State.ATTACK
			else:
				_move_velocity = _move_velocity.move_toward(_facing * move_speed, acceleration * delta)
		State.ATTACK:
			# Hold position while in range; leave to CHASE if the player kited out
			# (but never mid-swing). Swing whenever the guard is clear.
			_move_velocity = Vector2.ZERO
			if dist > attack_range and not _attacking:
				_state = State.CHASE
			elif not _attacking and not _on_cooldown:
				attack()

	_apply_motion(delta)


## Combine controlled movement with the decaying knockback impulse, move, then
## bleed the knockback down. Keeps the two velocities from compounding.
func _apply_motion(delta: float) -> void:
	velocity = _move_velocity + _knockback
	move_and_slide()
	_knockback = _knockback.move_toward(Vector2.ZERO, knockback_decay * delta)


## Resolve (or re-resolve) the player through the "player" group. Never indexes a
## null target; if the player was freed, is_instance_valid fails and it re-looks.
func _resolve_target() -> void:
	if _target != null and is_instance_valid(_target):
		return
	_target = get_tree().get_first_node_in_group("player") as Node2D


## Rotate the attack hitbox to face the target and enable it for a short window,
## then start the cooldown. Callable directly -- the headless smoke test calls
## this, mirroring the player's attack().
func attack() -> void:
	if _attacking or _on_cooldown or is_dead:
		return
	# Aim at the target at swing time so a directly-called attack still faces it.
	if _target != null and is_instance_valid(_target):
		var to_target: Vector2 = _target.global_position - global_position
		if to_target.length() > 0.001:
			_facing = to_target.normalized()
	_attacking = true
	velocity = Vector2.ZERO
	_attack_hitbox.rotation = _facing.angle()
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
	_on_cooldown = true
	await get_tree().create_timer(attack_cooldown).timeout
	if not is_instance_valid(self):
		return
	_on_cooldown = false


## Shared telegraph -> strike backbone (design-enemies.md). Pulse the Body to the amber warning
## tint and back over `duration` seconds -- a readable wind-up any COMMITTED attack plays before
## its hitbox goes live -- then return so the caller strikes. Awaitable: a subclass does
## `await telegraph_windup(telegraph_time)` and only THEN enables its AttackHitbox, so the player
## always gets a fair "tell". Reused by the Tank's stomp now (and the Charger's wind-up later).
## Restores WHITE on completion; a zero/negative duration is a no-op (fires with no wind-up).
func telegraph_windup(duration: float) -> void:
	if duration <= 0.0 or not is_instance_valid(_body):
		return
	var warn: Tween = create_tween()
	warn.tween_property(_body, "modulate", TELEGRAPH_COLOR, duration * 0.5)
	warn.tween_property(_body, "modulate", Color.WHITE, duration * 0.5)
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(_body):
		_body.modulate = Color.WHITE


## Shared de-aggro clock (design-enemies.md "Aggro / provoke states"). A provoked passive type
## calls this each physics frame with whether the target is still in CONTACT (in leash range this
## frame, OR hit this frame -- provoke() zeroes the clock). While in contact the clock stays 0;
## once the target is continuously out of contact for `deaggro_time`, it returns true, signalling
## the subclass to drop back to its passive state. Reusable by any passive type; the chaser never
## calls it.
func tick_deaggro(delta: float, in_contact: bool) -> bool:
	if in_contact:
		_deaggro_elapsed = 0.0
		return false
	_deaggro_elapsed += delta
	return _deaggro_elapsed >= deaggro_time


## Zero the de-aggro clock (a fresh provoke / new hit restarts the calm-down countdown).
func reset_deaggro() -> void:
	_deaggro_elapsed = 0.0


## Armor durability hit 0: the plate is gone. Drop the Hurtbox to the flesh baseline
## so both HP mitigation (def) and hardness fall -- softer hits from here on.
func _on_armor_broke() -> void:
	_hurtbox.def = flesh_def
	_hurtbox.hardness = flesh_hardness
	print("[enemy] armor broke -- def/hardness drop to flesh (", flesh_def, "/", flesh_hardness, ")")


func _on_damaged(_amount: int, current: int) -> void:
	print("[enemy] took damage, health now ", current)
	# Overbright modulate clamps every pixel to white, then tween back.
	_body.modulate = Color(10.0, 10.0, 10.0)
	var tween: Tween = create_tween()
	tween.tween_property(_body, "modulate", Color.WHITE, 0.25)


## Take a knockback impulse away from the hitbox that struck us (the player's
## sword). Magnitude comes from the attacker's hitbox data. Also latches the hit
## direction so the death lurch can fly the corpse the way the blow pushed.
func _on_hit_taken(hitbox: Hitbox) -> void:
	var dir: Vector2 = global_position - hitbox.global_position
	if dir.length() > 0.001:
		var away: Vector2 = dir.normalized()
		_last_hit_dir = away
		_knockback = away * hitbox.knockback


## Death sequence (does NOT freeze the game): let the player pass through the
## corpse, jerk it out in the direction of the killing blow with an abrupt stop,
## blink it to read as defeated, then remove it. Distinct from the player's
## circle-pop death. Latched so a second `died` cannot re-run it.
func _on_died() -> void:
	if _dying:
		return
	_dying = true
	is_dead = true # the _physics_process early-return already halts AI/movement.
	print("[enemy] died -- death lurch + blink, then free")

	# Player passes THROUGH the corpse, and it stops taking / dealing hits.
	$CollisionShape2D.set_deferred("disabled", true)
	_hurtbox.set_deferred("monitoring", false)
	if is_instance_valid(_attack_shape):
		_attack_shape.set_deferred("disabled", true)
	if is_instance_valid(_attack_visual):
		_attack_visual.visible = false

	# Zero the motion forces so they do not fight the lurch tween.
	_move_velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	velocity = Vector2.ZERO

	# JERK-STOP lurch: shoot out along the killing-blow direction and stop hard
	# (QUINT ease-out), NOT the gradual _knockback decay.
	var lurch_target: Vector2 = global_position + _last_hit_dir * death_lurch_distance
	var lurch_tween: Tween = create_tween()
	lurch_tween.tween_property(self, "global_position", lurch_target, 0.12) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	# BLINK the body on/off to read as defeated, concurrent with the lurch.
	var blink_tween: Tween = create_tween().set_loops()
	blink_tween.tween_callback(_body.set_visible.bind(false))
	blink_tween.tween_interval(0.08)
	blink_tween.tween_callback(_body.set_visible.bind(true))
	blink_tween.tween_interval(0.08)

	await get_tree().create_timer(0.35).timeout
	if is_instance_valid(blink_tween):
		blink_tween.kill()
	if is_instance_valid(self):
		queue_free()

# Verified against: Godot 4.7.1 (2026-07-19)
