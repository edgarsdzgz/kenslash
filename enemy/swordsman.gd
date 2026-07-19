class_name Swordsman
extends Enemy
## The Swordsman (design-enemies.md "2. Swordsman") -- the DUELER reworked from the humanoid
## chaser. Not a beeline-and-bonk chaser: it holds duel range, telegraphs 2-3 hit sword COMBOS,
## reactively DODGES the player's swing on a cooldown+punish-window loop, and grows more
## aggressive as its HP drops. A fight you READ, not out-DPS.
##
## FSM (its OWN, distinct from the base IDLE/CHASE/ATTACK chaser and the Tank's GRAZE/ENRAGED/CALM):
##   * IDLE      -- no target in detection_range: coast, do nothing (a streamed Swordsman with no
##                  player, or one that lost its target, rests here -- byte-identical to the base).
##   * APPROACH  -- target seen but beyond duel range: gap-close toward it.
##   * STRAFE    -- at duel range: circle/hold spacing (perpendicular), never beeline onto the
##                  player; after combo_interval, step in and start a COMBO.
##   * COMBO     -- a 2-3 hit sword string (mix-up: a fast 1-hit JAB vs a committed multi-hit),
##                  each hit preceded by a short telegraph_windup (COLD hitbox) then a fast strike.
##   * RECOVER   -- the ~recovery_time vulnerable PUNISH WINDOW after a combo (no dodge, no attack).
##   * DODGE     -- reactive evade: the player's swing goes active in reach/arc -> after dodge_reaction
##                  it side-steps/back-dashes with brief i-frames, on a dodge_cooldown. A fast/close
##                  or well-timed hit still lands (the reaction delay + cooldown remove omniscience).
## These are expressed as guard flags (_combo_active / _telegraphing / _recovering / _dodging /
## _dodge_on_cooldown) read straight off the situation each frame rather than a stored enum, because
## the committed actions (combo, dodge) run as awaited coroutines exactly like the Tank's stomp().
##
## ARCHITECTURE (Phase 2 of the enemy roster): a SUBCLASS of Enemy, mirroring enemy/tank.gd (Phase 1).
## The base owns the shared tech -- HealthComponent/Hurtbox, movement + knockback + _apply_motion,
## flash, death lurch, the four-facing Avatar, target resolve, the telegraph_windup() helper, and the
## base attack()/AttackHitbox. The Swordsman supplies only its per-type dueling AI here by overriding
## _physics_process (the base chaser loop is fully replaced) and adding the combo/dodge coroutines.
## enemy/enemy.tscn is re-scripted onto this class (node name "Enemy" + scene path unchanged), so
## main.tscn and the shared test fixture (ctx.enemy = main.get_node("Enemy") as Enemy) need NO change
## -- a Swordsman IS-A Enemy. Phases 3-4 (Charger, Spitter) plug in the SAME way as fresh subclasses.
##
## The `stationary` PIN is honored verbatim: with stationary = true (the flesh-damage test legs pin
## ctx.enemy) it behaves as a PASSIVE standing target -- holds position, takes hits, NO dodge, NO
## combo -- so those legs land exact tool damage (sword 5 / axe 3 / pickaxe 1) on def-1 flesh. The
## Hurtbox stays def 1 / hardness 2 (flesh): the Swordsman's toughness is EVASION + higher HP, not a
## big def (design-enemies.md), which is why the flesh legs' numbers are UNCHANGED.

## --- Spacing / movement knobs -------------------------------------------------------------
## The duel distance in px the Swordsman holds -- steps in to strike, out after, circles at this
## range instead of beelining onto the player.
@export var duel_range: float = 42.0
## Hysteresis band around duel_range: inside +/- this it just STRAFES (holds spacing); farther out it
## APPROACHES, closer in it BACKS OFF. Keeps it from jittering exactly on the ring.
@export var duel_band: float = 12.0
## Perpendicular circling speed while strafing at duel range, in px/sec (below move_speed so it reads
## as a measured circle, not a sprint).
@export var strafe_speed: float = 55.0

## --- Combo knobs (design-enemies.md "Offense") --------------------------------------------
## Seconds strafing at duel range before it steps in and starts a combo (the aggression cadence;
## shortens as HP drops -- see effective_combo_interval()).
@export var combo_interval: float = 0.9
## Hits in a COMMITTED combo string (the mix-up's big, punishable option; the JAB is always 1 hit).
@export var combo_hits: int = 3
## Seconds between the strikes within one combo (the fast execution after each tell).
@export var combo_gap: float = 0.12
## Seconds of readable wind-up (COLD hitbox) before EACH combo strike -- a short flash, not the
## Tank's long stomp tell. Reuses the shared telegraph_windup() helper.
@export var combo_windup: float = 0.22
## The vulnerable PUNISH WINDOW after a combo, in seconds: no dodge, no attack (design decision).
@export var recovery_time: float = 0.6
## Seconds the gap-closer step-in velocity is MAINTAINED at the start of a combo (skipping the
## friction bleed in _physics_process), so the Swordsman actually CLOSES distance to start the
## string instead of the once-set velocity dying to ~0 within the first windup. Tunable.
@export var combo_stepin_time: float = 0.18

## --- Reactive-dodge knobs (DECIDED: cooldown + punish window) ------------------------------
## Minimum seconds between dodges: a second swing inside this window is NOT dodged and LANDS.
@export var dodge_cooldown: float = 1.2
## Reaction DELAY before the evade fires, in seconds -- a fast/close or well-timed hit beats it and
## lands. This is what removes omniscient dodging.
@export var dodge_reaction: float = 0.15
## How long the side-step/back-dash (and its i-frames) lasts, in seconds.
@export var dodge_duration: float = 0.2
## Evade burst speed, in px/sec (a quick hop out of the swing).
@export var dodge_speed: float = 260.0
## Px reach within which the player's active swing is treated as threatening (their blade reach plus
## this body). Beyond it the Swordsman need not flinch.
@export var dodge_detect_range: float = 60.0
## Cone gate: the player must be facing roughly at the Swordsman (facing . toward-me >= this) for the
## swing to count as incoming. ~0.2 is a wide ~78deg half-cone.
@export var dodge_detect_dot: float = 0.2

## --- Escalation knobs (design-enemies.md "Escalation") ------------------------------------
## HP ratio at/below which aggression is MAX (1.0). From full HP (ratio 1 -> aggression 0) it ramps
## up to here. Drives shorter dodge cooldowns and faster combo cadence at low HP.
@export var aggression_low_hp: float = 0.4
## Floor the effective dodge cooldown / combo interval scale to at max aggression (0.5 = halved).
@export var aggression_scale: float = 0.5

## True during a combo string (any of its telegraph/strike/gap sub-steps). Read by the test.
var _combo_active: bool = false
## True only during a combo strike's wind-up (telegraph playing, hitbox still COLD). Proves the tell
## precedes the live hitbox.
var _telegraphing: bool = false
## True during the post-combo RECOVERY (punish) window.
var _recovering: bool = false
## True while a dodge's evade burst (and its i-frames) is live.
var _dodging: bool = false
## Latched for the whole dodge_cooldown (including reaction + burst) so it cannot re-dodge.
var _dodge_on_cooldown: bool = false
## Number of dodges performed -- a deterministic counter the test asserts (a dodge DID / did NOT fire).
var _dodge_count: int = 0
## Direction of the current evade burst; _physics_process drives _move_velocity along it while dodging.
var _dodge_dir: Vector2 = Vector2.RIGHT
## Strafe clock: seconds held at duel range; on reaching effective_combo_interval() a combo starts.
var _strafe_elapsed: float = 0.0
## Mix-up toggle: alternates a fast 1-hit JAB and a committed multi-hit combo so the player cannot
## pre-commit to one punish. Deterministic (a toggle, not RNG) so the headless suite stays stable.
var _next_is_jab: bool = false
## Seconds left in the combo step-in window; while > 0 (and mid-combo) _physics_process drives the
## step-in velocity instead of bleeding to a stop, so the gap-closer actually moves. Set on start_combo.
var _stepin_left: float = 0.0
## Locked step-in bearing (toward the target at combo start); paired with _stepin_left.
var _stepin_dir: Vector2 = Vector2.RIGHT


## Per-frame dueling AI. The shared _sense() preamble (base) runs the dead / stationary-pin / no-target
## early-outs and the facing + Avatar pass (a circling dueler still watches you); this supplies only the
## spacing + dodge/combo machine on top. The stationary pin is honored by _sense, so a pinned Swordsman
## is a passive stand-in target for the flesh-damage legs -- NO dodge, NO combo while pinned.
func _physics_process(delta: float) -> void:
	var sense: Dictionary = _sense(delta)
	if not sense["act"]:
		return
	var dist: float = sense["dist"]

	# Reactive dodge FIRST: an incoming swing is answered before any movement decision this frame.
	if should_dodge():
		_begin_dodge()

	if _dodging:
		# The evade burst owns movement while it runs (the coroutine clears _dodging when done).
		_move_velocity = _dodge_dir * dodge_speed
	elif _combo_active and _stepin_left > 0.0:
		# Gap-closer step-in: for its short window drive the LOCKED step-in velocity (skipping the
		# _busy() friction bleed below) so a starting combo actually CLOSES distance instead of the
		# once-set velocity dying to ~0 before the first windup ends ("you can't just back away").
		_stepin_left -= delta
		_move_velocity = _stepin_dir * move_speed
	elif _busy():
		# Committed to an own action (combo strike / recovery) -- hold position, bleed to a stop.
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
	elif dist > detection_range:
		# Target out of engage range -> IDLE: coast, reset the strafe clock.
		_strafe_elapsed = 0.0
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)
	else:
		_duel_movement(delta, dist)

	_apply_motion(delta)


## APPROACH / STRAFE / BACK-OFF spacing at duel range, plus the strafe-timed step-in that starts a
## combo. Only runs when free (not dodging, not mid-combo/recovery). The hysteresis band keeps it from
## flip-flopping on the exact duel ring.
func _duel_movement(delta: float, dist: float) -> void:
	if dist > duel_range + duel_band:
		# APPROACH: gap-close toward the player (the "you can't just back away" pressure).
		_strafe_elapsed = 0.0
		_move_velocity = _move_velocity.move_toward(_facing * move_speed, acceleration * delta)
	elif dist < duel_range - duel_band:
		# Too close: BACK OFF to re-open duel range (spacing, never crowding onto the player).
		_strafe_elapsed = 0.0
		_move_velocity = _move_velocity.move_toward(-_facing * move_speed, acceleration * delta)
	else:
		# In the band: STRAFE (circle perpendicular), holding spacing. After the (HP-scaled) interval,
		# step in and open a combo.
		var perp: Vector2 = Vector2(-_facing.y, _facing.x)
		_move_velocity = _move_velocity.move_toward(perp * strafe_speed, acceleration * delta)
		_strafe_elapsed += delta
		if _strafe_elapsed >= effective_combo_interval():
			_strafe_elapsed = 0.0
			start_combo()


# --- Combo (design-enemies.md "Offense": telegraphed 2-3 hit strings + mix-ups + recovery) -------

## Run a sword combo: a mix-up of a fast 1-hit JAB and a committed multi-hit string, each hit a short
## telegraph_windup (COLD hitbox) then a fast strike, closed by the vulnerable RECOVERY punish window.
## Callable directly (the test invokes it to prove the tell precedes the live hitbox + the recovery).
## `hits` < 0 picks the mix-up automatically; a caller/test may force a specific count.
func start_combo(hits: int = -1) -> void:
	if _combo_active or _dodging or _recovering or _attacking or is_dead:
		return
	if hits < 0:
		hits = 1 if _next_is_jab else combo_hits
		_next_is_jab = not _next_is_jab
	_combo_active = true
	# Gap-closer step-in as the string opens: lock a bearing toward the target and MAINTAIN it for
	# combo_stepin_time (see _physics_process), so a combo starts on top of the player rather than at
	# max reach. Setting the velocity once is not enough -- friction bleeds it to ~0 within ~0.12s
	# (< combo_windup), so the step-in barely moved; the maintained window is the actual fix.
	_stepin_left = 0.0
	if _target != null and is_instance_valid(_target):
		var to_t: Vector2 = _target.global_position - global_position
		if to_t.length() > 0.001:
			_stepin_dir = to_t.normalized()
			_stepin_left = combo_stepin_time
			_move_velocity = _stepin_dir * move_speed

	for i in range(hits):
		if not is_instance_valid(self) or is_dead:
			break
		_aim_hitbox_at_target()
		# WIND-UP: the fair tell. Hitbox stays COLD for the whole (HP-scaled) telegraph.
		_telegraphing = true
		await telegraph_windup(effective_windup())
		if not is_instance_valid(self) or is_dead:
			_telegraphing = false
			_combo_active = false
			return
		_telegraphing = false
		# STRIKE: hitbox live for the window.
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
		if i < hits - 1:
			await get_tree().create_timer(combo_gap).timeout
			if not is_instance_valid(self) or is_dead:
				_combo_active = false
				return

	# RECOVERY: the punish window -- vulnerable, no dodge, no attack.
	_recovering = true
	await get_tree().create_timer(recovery_time).timeout
	if not is_instance_valid(self):
		return
	_recovering = false
	_combo_active = false


## Aim the base AttackHitbox at the current target (rotate to face it), so a combo strike lands where
## the player is. Mirrors the aim step in Enemy.attack() / Tank.stomp().
func _aim_hitbox_at_target() -> void:
	if _target != null and is_instance_valid(_target):
		var to_t: Vector2 = _target.global_position - global_position
		if to_t.length() > 0.001:
			_facing = to_t.normalized()
	_attack_hitbox.rotation = _facing.angle()


# --- Reactive dodge (DECIDED: cooldown + reaction delay + punish window) -------------------------

## Whether an incoming player swing should be dodged THIS frame: off-cooldown, not already dodging,
## not committed to an own action, not pinned, and the player's active swing is in reach + arc.
## Public so the test can assert the detection reads the player's attack state directly.
func should_dodge() -> bool:
	if _dodging or _dodge_on_cooldown or _busy() or is_dead or stationary:
		return false
	return _player_attack_threatens()


## True if the target is a Player mid-swing (_attacking) with the Swordsman inside the swing's reach
## and arc. Reads the player's ATTACK STATE (its _attacking flag + facing) -- the reactive trigger.
func _player_attack_threatens() -> bool:
	var p: Player = _target as Player
	if p == null or not is_instance_valid(p) or not p._attacking:
		return false
	var to_me: Vector2 = global_position - p.global_position
	var d: float = to_me.length()
	if d > dodge_detect_range:
		return false
	if d > 0.001 and p.facing.dot(to_me / d) < dodge_detect_dot:
		return false
	return true


## Launch the evade coroutine in a side-step-and-back direction out of the swing's line.
func _begin_dodge() -> void:
	var away: Vector2 = Vector2.ZERO
	if _target != null and is_instance_valid(_target):
		var to_t: Vector2 = _target.global_position - global_position
		if to_t.length() > 0.001:
			to_t = to_t.normalized()
			# Side-step perpendicular, biased slightly BACK from the player -- out of the blade's arc.
			var perp: Vector2 = Vector2(-to_t.y, to_t.x)
			away = (perp - to_t * 0.3).normalized()
	if away == Vector2.ZERO:
		away = -_facing
	_run_dodge(away)


## The evade: after dodge_reaction (so a fast/close hit still lands), burst along `dir` with brief
## i-frames (Hurtbox.dodge_invincible, the SAME dash-i-frame lever the player's dodge uses), then hold
## the rest of the (HP-scaled) cooldown. A zero reaction raises the i-frames the SAME frame (used by
## the deterministic test).
func _run_dodge(dir: Vector2) -> void:
	_dodge_on_cooldown = true
	var cooldown: float = effective_dodge_cooldown()
	if dodge_reaction > 0.0:
		await get_tree().create_timer(dodge_reaction).timeout
		if not is_instance_valid(self) or is_dead or stationary:
			_dodge_on_cooldown = false
			return
	_dodging = true
	_dodge_dir = dir
	_dodge_count += 1
	_hurtbox.dodge_invincible = true
	await get_tree().create_timer(dodge_duration).timeout
	if not is_instance_valid(self):
		return
	_hurtbox.dodge_invincible = false
	_dodging = false
	var remain: float = maxf(0.0, cooldown - dodge_reaction - dodge_duration)
	if remain > 0.0:
		await get_tree().create_timer(remain).timeout
		if not is_instance_valid(self):
			return
	_dodge_on_cooldown = false


# --- Escalation: more aggressive as HP drops --------------------------------------------------

## 0 at full HP, ramping to 1 at/below aggression_low_hp. Drives the shorter cooldowns / faster combos.
func aggression() -> float:
	if _health == null or _health.max_health <= 0:
		return 0.0
	var ratio: float = float(_health.current_health) / float(_health.max_health)
	var span: float = maxf(0.001, 1.0 - aggression_low_hp)
	return clampf((1.0 - ratio) / span, 0.0, 1.0)


## Dodge cooldown scaled DOWN by aggression (down to aggression_scale of the base at max aggression).
func effective_dodge_cooldown() -> float:
	return dodge_cooldown * lerpf(1.0, aggression_scale, aggression())


## Strafe->combo interval scaled DOWN by aggression -- a low-HP Swordsman opens combos sooner.
func effective_combo_interval() -> float:
	return combo_interval * lerpf(1.0, aggression_scale, aggression())


## Combo wind-up scaled DOWN by aggression -- low-HP combos come out faster (a shorter tell).
func effective_windup() -> float:
	return combo_windup * lerpf(1.0, aggression_scale, aggression())


## True while committed to an own action (combo strike or recovery). Neither dodge nor a new combo may
## start while busy -- that commitment is exactly what the player punishes.
func _busy() -> bool:
	return _combo_active or _telegraphing or _recovering or _attacking

# Verified against: Godot 4.7.1 (2026-07-19)
