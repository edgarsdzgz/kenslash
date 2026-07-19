class_name Combat
extends RefCounted
## The sword-combo subsystem, extracted from player.gd (recipes/health-and-damage.md, the
## facing-directed 3-hit combo). Owns the combo STATE (_combo_index, _attacking, the active
## blade-sweep tween) and drives one swing. The player keeps a thin facade (attack /
## _combo_index / _attacking) that forwards here so tests and _simulate read/write player.X
## unchanged.
##
## SWING DIRECTIONS (the SWORD is the exception to "all swings chop down"): ONLY a combo
## weapon (the sword, has_combo) varies its direction across the 3-hit combo -- hit 0 is the
## overhead DOWN-slash (top -> bottom on screen), hit 1 the RISING UP-slash (the reverse arc,
## bottom -> top), hit 2 the forward THRUST (lunge). A non-combo tool (axe/pickaxe) only ever
## reaches _combo_index 0, so it keeps the single overhead down-chop. UNARMED (no tool) is a
## separate quick forward JAB (_punch), never an arc. A subtle scale-based PERSPECTIVE cue
## sells depth on the flat blade during a swing (thrust stretches + narrows to read as going
## INTO the scene; arcs shrink from near to far) and is RESET in _end_swing so no swing leaves
## a distorted blade.
##
## RefCounted, NOT a Node -- exactly like components/equipment.gd, components/interaction.gd,
## and components/pickup.gd. A Combat Node add_child'd to the player would bump the global
## Performance.OBJECT_NODE_COUNT (or ORPHAN count), which the streaming zero-orphan-leak
## assertion prints as a literal baseline -- breaking the "same 194 assertions, byte-identical"
## refactor anchor. As a RefCounted it is invisible to both node monitors.
##
## "Call down" wiring (patterns/scene-composition.md): a RefCounted can neither create tweens/
## timers nor own scene nodes, so the player "calls down" everything the swing manipulates --
## the SwordPivot (rotated to aim the blade), the Blade Polygon2D (shown during a swing), the
## Sword's CollisionShape2D (the hitbox, enabled during a swing), and the one-shot
## ComboResetTimer -- plus the player ITSELF, because the swing must call player.create_tween()
## / player.get_tree().create_timer() (a RefCounted has no tree), read player.facing and the
## @export tunables (arc_degrees / swing_duration / combo_window / lunge_impulse -- left on the
## player so the scene/tuning stays discoverable), read the gates player._sword_broken /
## player._combo_enabled (themselves Equipment facades), and set player._knockback for the
## hit-3 lunge slide. This object never reaches up beyond those named handles.


## Which hit of the combo the NEXT attack() will play: 0 -> arc A, 1 -> arc B, 2 -> lunge.
## Advances each swing and wraps 2 -> 0. Exposed via the player's _combo_index facade (get+set)
## so a test can force a specific swing (`player._combo_index = 2`) and read the result.
var _combo_index: int = 0
## True while a swing is in flight; gates re-entry (a press mid-swing is dropped, no buffer).
## Exposed via the player's _attacking facade so a test's drain loop (`if not player._attacking`)
## and _respawn_in_place (which clears it) read/write it unchanged.
var _attacking: bool = false
## Active blade-sweep tween; killed on death (cancel_swing) so a mid-swing death leaves no blade.
var _swing_tween: Tween = null

## The player CharacterBody2D (host): the swing calls player.create_tween() /
## player.get_tree().create_timer() (a RefCounted has neither), reads player.facing + the
## @export tunables + the broken/combo gates, and sets player._knockback for the lunge.
var _player: Node2D = null
## The SwordPivot Node2D -- rotated to aim the blade for each swing.
var _sword_pivot: Node2D = null
## The Blade Polygon2D -- shown during a swing, hidden after (and on a cancelled/death swing).
var _blade: Polygon2D = null
## The Sword's CollisionShape2D (the hitbox extent) -- enabled during a swing, disabled after.
var _sword_shape: CollisionShape2D = null
## The Sword Hitbox itself (the CollisionShape2D's parent) -- the Area2D whose `atk` the Hurtbox reads on
## overlap. Cached in setup() so a MELEE_DAMAGE talent can add its bonus onto this swing's atk (Part 2.2b)
## WITHOUT player.gd growing a field/facade. Equipment owns the BASE atk (per equipped tool); this only
## adds/removes the talent bonus for the swing's duration, leaving that base untouched between swings.
var _sword_hitbox: Hitbox = null
## The MELEE_DAMAGE talent bonus currently ADDED onto _sword_hitbox.atk (Part 2.2b). Tracked so the exact
## amount added at swing start is the exact amount removed at swing end/cancel -- so a cancelled swing (a
## mid-swing death) can never leave the bonus double-stacked onto the next swing. 0 between swings.
var _melee_bonus_applied: int = 0
## The one-shot ComboResetTimer -- started at swing END to hold the continue-window open, and
## stopped when a swing begins so the window cannot expire mid-swing.
var _combo_reset_timer: Timer = null

## Perspective cue tuning (juice, all subtle, all RESET in _end_swing). Scale is applied to the
## visual _blade Polygon2D ONLY -- never the CollisionShape2D -- so hittability is unchanged.
const THRUST_STRETCH: float = 1.6  ## Thrust: blade grows along its length (reads as going INTO the scene).
const THRUST_NARROW: float = 0.65  ## ...and narrows across (foreshorten).
const ARC_NEAR: float = 1.15  ## Arc START (near part of the sweep) a touch bigger.
const ARC_FAR: float = 0.9  ## Arc END (far part) smaller -- a subtle depth read across the sweep.
## Unarmed jab tuning. The fist is SHORT-reach (a punch, not a sword): the pivot slides from a
## tucked pose out to `extended` (fist center ~ facing*(24 - PUNCH_BACK + PUNCH_REACH), well
## inside the sword's static 24px reach) and back, while a small fist silhouette is shown.
const FIST_SCALE: Vector2 = Vector2(0.55, 0.9)  ## Small blocky fist (scales the plain rectangle blade down).
const PUNCH_BACK: float = 18.0  ## How far the fist is tucked toward the body at jab start.
const PUNCH_REACH: float = 10.0  ## SHORT forward travel of the jab.

## Last arc sweep endpoints [start, end] pivot rotation (radians), recorded each swing so a test
## can assert hit 0 (down-slash) and hit 1 (up-slash) sweep OPPOSITE vertical ways. Thrust sets
## both to `base` (no sweep). Read via player._combat.
var _last_arc_start: float = 0.0
var _last_arc_end: float = 0.0
## Last unarmed jab's forward reach (px), recorded so a test can assert the fist thrust OUT.
var _last_punch_reach: float = 0.0
## The SwordPivot's authored rest position, captured in setup(). The punch slides the pivot for
## its thrust; _end_swing snaps it back here so no swing leaves the pivot displaced.
var _pivot_rest: Vector2 = Vector2.ZERO
## Active perspective/jab tween (blade scale for arcs/thrust, pivot slide for the punch). Killed
## in _end_swing / cancel_swing before the reset so a lingering tween cannot re-distort the blade.
var _fx_tween: Tween = null


## Wire the host + the shared SwordPivot / Blade / Sword CollisionShape2D / ComboResetTimer (the
## player "calls down" in its _ready), and take over the combo-reset timeout connection the
## player used to own -- on timeout the next swing restarts at hit 1. Mirrors Equipment.setup().
func setup(player: Node2D, sword_pivot: Node2D, blade: Polygon2D, sword_shape: CollisionShape2D,
		combo_reset_timer: Timer) -> void:
	_player = player
	_sword_pivot = sword_pivot
	_blade = blade
	_sword_shape = sword_shape
	# The Hitbox is the CollisionShape2D's parent (SwordPivot/Sword/CollisionShape2D) -- cache it so the
	# talent melee bonus can be added onto its atk per swing without reaching up into the player for _sword.
	_sword_hitbox = _sword_shape.get_parent() as Hitbox
	_combo_reset_timer = combo_reset_timer
	# Remember where the pivot rests so the punch (which slides it for the jab) can snap back.
	_pivot_rest = _sword_pivot.position
	# The combo continue-window: on timeout the next swing restarts at hit 1. Owned here now
	# (the player used to connect this in its _ready) so the combo state stays with the combo.
	_combo_reset_timer.timeout.connect(_on_combo_reset)


## Play a swing in the current facing direction, then retract the blade. Callable directly via
## the player.attack() facade -- the headless smoke test calls it, so attacking must NOT be gated
## solely behind real input. The equipped tool decides the STYLE: UNARMED (no tool) is a quick
## forward JAB (_punch); a combo weapon (the sword) chains DOWN-slash -> UP-slash -> thrust,
## pressing again within combo_window to continue; a regular tool (axe/pickaxe) does a single
## overhead down-slash per press with no chain (the tail's player._combo_enabled gate). The swing
## shape itself is still chosen by _combo_index, so a test that forces the index gets that swing.
func attack() -> void:
	if _attacking or _player._sword_broken:
		return
	_attacking = true
	# Continuing the combo: stop the reset so the window does not expire mid-swing.
	_combo_reset_timer.stop()

	if _player._is_unarmed:
		# No tool: a quick forward jab, never the sword arc/combo.
		await _punch()
	else:
		var base: float = _player.facing.angle()
		var half: float = deg_to_rad(_player.arc_degrees / 2.0)
		match _combo_index:
			0, 1:
				# The SWORD varies its DIRECTION (the exception to "all swings chop down"):
				# hit 0 is the OVERHEAD down-slash (top -> bottom on screen), hit 1 the RISING
				# up-slash (the REVERSE arc, bottom -> top). Both are screen-oriented for ANY
				# facing (_overhead_arc / _rising_arc pick the endpoints by sin, not a fixed
				# +/-half, so a facing and its mirror both read correctly). A non-combo tool
				# only ever reaches index 0, so it keeps the single overhead down-chop.
				var arc: Array = _overhead_arc(base, half) if _combo_index == 0 else _rising_arc(base, half)
				_last_arc_start = arc[0]
				_last_arc_end = arc[1]
				_sword_pivot.rotation = arc[0]
				_begin_swing()
				_perspective_arc()
				await _sweep_to(arc[1])
			2:
				# Hit 2: forward THRUST (lunge). Blade straight along facing; nudge the player
				# forward through the existing decaying-knockback system so it slides and stops.
				_last_arc_start = base
				_last_arc_end = base
				_sword_pivot.rotation = base
				_begin_swing()
				_perspective_thrust()
				_player._knockback = _player.facing * _player.lunge_impulse
				await _player.get_tree().create_timer(_player.swing_duration).timeout

	_end_swing()
	# Bail if a mid-swing death freed us out of the tree.
	if not _player.is_inside_tree():
		return
	# Only a COMBO weapon (the sword) chains: advance to the next hit and open the
	# continue-window. A regular tool (axe/pickaxe/unarmed) does NOT chain -- reset to hit 0
	# so every press is a fresh single arc swing, never advancing into arc B or the lunge.
	# (The swing TYPE above is still selected by _combo_index, so a test that forces the
	# index still gets that swing; only the auto-advance is gated.)
	if _player._combo_enabled:
		_combo_index = (_combo_index + 1) % 3
		_combo_reset_timer.start(_player.combo_window)
	else:
		_combo_index = 0
	_attacking = false


## Return [start, end] pivot rotation for an OVERHEAD arc (top -> bottom on screen) spanning
## +/- half around `base`. Screen +y is DOWN, so the higher endpoint is the one with the
## smaller sin; start there so every facing reads as a downward chop instead of a
## facing-dependent bottom-to-top swing. The +/- half endpoints are unchanged -- only which
## one the sweep STARTS from. Ties (facing straight up/down) fall back to base-half -> base+half.
func _overhead_arc(base: float, half: float) -> Array:
	var a: float = base - half
	var b: float = base + half
	if sin(a) <= sin(b):
		return [a, b]
	return [b, a]


## Return [start, end] pivot rotation for a RISING arc (bottom -> top on screen) -- the exact
## REVERSE of _overhead_arc, so hit 1 sweeps the opposite vertical way from hit 0's down-slash.
## Screen-oriented for ANY facing by reusing the same sin-picked endpoints, just swapped.
func _rising_arc(base: float, half: float) -> Array:
	var arc: Array = _overhead_arc(base, half)
	return [arc[1], arc[0]]


## PERSPECTIVE for an ARC swing (juice): a subtle scale that starts a touch bigger (near part
## of the sweep) and shrinks across the sweep (far part), for a light depth read. Scales the
## visual _blade ONLY (never the hitbox). Tracked in _fx_tween so _end_swing can kill + reset it.
func _perspective_arc() -> void:
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_blade.scale = Vector2(ARC_NEAR, ARC_NEAR)
	_fx_tween = _player.create_tween()
	_fx_tween.tween_property(_blade, "scale", Vector2(ARC_FAR, ARC_FAR), _player.swing_duration)


## PERSPECTIVE for the THRUST (juice): the blade stretches along its length and narrows across
## as it extends "out", so it reads as going INTO the scene, then restores. Scales the visual
## _blade ONLY. Tracked in _fx_tween so _end_swing can kill + reset it (final reset snaps to ONE).
func _perspective_thrust() -> void:
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = _player.create_tween()
	_fx_tween.tween_property(_blade, "scale", Vector2(THRUST_STRETCH, THRUST_NARROW), _player.swing_duration * 0.5)
	_fx_tween.tween_property(_blade, "scale", Vector2.ONE, _player.swing_duration * 0.5)


## UNARMED jab (design-inventory.md): a SHORT forward thrust of a small fist hitbox along facing,
## then retract -- NOT the sword arc/combo. Points the fist forward (the lunge pose), shrinks the
## blade to a small fist silhouette, enables the hitbox for the WHOLE window (guaranteed overlap,
## like the lunge), and slides the pivot from a tucked pose out to a SHORT reach and back. Single
## jab: attack()'s tail (unarmed -> _combo_enabled false) never advances the combo. The UNARMED_ATK
## HP + null durability come from _apply_unarmed's hitbox stats, untouched here. _end_swing resets
## the fist scale + snaps the pivot back to rest.
func _punch() -> void:
	var facing: Vector2 = _player.facing
	_sword_pivot.rotation = facing.angle()
	_blade.scale = FIST_SCALE
	_last_punch_reach = PUNCH_REACH
	_begin_swing()
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	# Tuck the fist toward the body, jab OUT a short reach, then pull back to the tuck. The whole
	# swept range stays SHORT (inside the sword's 24px static reach) yet covers a target in front.
	var tucked: Vector2 = _pivot_rest - facing * PUNCH_BACK
	var extended: Vector2 = tucked + facing * PUNCH_REACH
	_sword_pivot.position = tucked
	_fx_tween = _player.create_tween()
	_fx_tween.tween_property(_sword_pivot, "position", extended, _player.swing_duration * 0.5)
	_fx_tween.tween_property(_sword_pivot, "position", tucked, _player.swing_duration * 0.5)
	await _player.get_tree().create_timer(_player.swing_duration).timeout


## Enable the blade collision and show the silver rectangle for a swing, and ADD the player's MELEE_DAMAGE
## talent bonus onto the Sword Hitbox's atk for this swing (Part 2.2b). Every swing path (arc / thrust /
## unarmed jab) routes through here, so the perk lands on all of them.
func _begin_swing() -> void:
	_sword_shape.disabled = false
	_blade.visible = true
	_apply_melee_bonus()


## Add this swing's MELEE_DAMAGE talent bonus onto the Sword Hitbox's atk, read off the OWNING player's
## CharacterSheet (never hardcoded). Guard-removes any stale add first (defensive: a prior cancelled swing)
## so the bonus can never double-stack, then records + applies the fresh sum. Deterministic integer, no
## Time/OS/RNG. The Hurtbox reads atk on overlap DURING the swing, so it sees the boosted value.
func _apply_melee_bonus() -> void:
	if _sword_hitbox == null:
		return
	_sword_hitbox.atk -= _melee_bonus_applied
	_melee_bonus_applied = _player.character().melee_damage_bonus()
	_sword_hitbox.atk += _melee_bonus_applied


## Remove whatever MELEE_DAMAGE bonus this swing added, restoring the equipment-owned base atk. Called at
## swing end AND on a mid-swing cancel (death), so the base is always restored regardless of how the swing
## ended. Idempotent -- subtracts exactly what was added, then zeroes the tracker.
func _clear_melee_bonus() -> void:
	if _sword_hitbox != null:
		_sword_hitbox.atk -= _melee_bonus_applied
	_melee_bonus_applied = 0


## Disable the blade collision and hide the rectangle after a swing, and RESET the perspective/
## jab transforms (kill any live fx tween, restore blade scale/skew to default, snap the pivot
## back to rest) so no swing leaves a distorted blade or a displaced pivot. Guarded so a
## mid-swing death that freed these nodes cannot crash the retract.
func _end_swing() -> void:
	# Restore the equipment-owned base atk (remove this swing's talent bonus) before the visual reset.
	_clear_melee_bonus()
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	if is_instance_valid(_sword_shape):
		_sword_shape.disabled = true
	if is_instance_valid(_blade):
		_blade.visible = false
		_blade.scale = Vector2.ONE
		_blade.skew = 0.0
	if is_instance_valid(_sword_pivot):
		_sword_pivot.position = _pivot_rest


## Tween the pivot rotation to `target` over swing_duration and await it, tracking
## the tween so death can cancel it. Uses the player to create the tween (a RefCounted cannot).
func _sweep_to(target: float) -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = _player.create_tween()
	_swing_tween.tween_property(_sword_pivot, "rotation", target, _player.swing_duration)
	await _swing_tween.finished


## Combo grace window expired: the next attack restarts at hit 1.
func _on_combo_reset() -> void:
	_combo_index = 0


## Cancel an in-flight swing and leave NO blade behind -- called from the player's death handler
## so a mid-swing death pops the avatar with no lingering blade. Kills the sweep tween, hides the
## blade, and disables the hitbox (the sword-shape disable is guarded, matching the pre-split
## death path exactly). The body-hide stays on the player; only the blade concern lives here.
func cancel_swing() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	# Also kill any live perspective/jab tween so it cannot re-distort the blade or slide the
	# pivot after the cancel (the coroutine that would have called _end_swing is leaked below).
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	# Tween.kill() does NOT emit `finished`, so the attack() coroutine suspended on
	# `await _swing_tween.finished` never resumes and would leave _attacking latched true. Clear it
	# HERE so the combat state is always consistent after a cancel, regardless of the leaked coroutine.
	_attacking = false
	# A mid-swing cancel skips _end_swing, so restore the base atk here too (remove any applied bonus).
	_clear_melee_bonus()
	if is_instance_valid(_blade):
		_blade.visible = false
		_blade.scale = Vector2.ONE
		_blade.skew = 0.0
	if is_instance_valid(_sword_shape):
		_sword_shape.disabled = true
	if is_instance_valid(_sword_pivot):
		_sword_pivot.position = _pivot_rest

# Verified against: Godot 4.7.1 (2026-07-19)
