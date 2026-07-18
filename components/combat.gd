class_name Combat
extends RefCounted
## The sword-combo subsystem, extracted from player.gd (recipes/health-and-damage.md, the
## facing-directed 3-hit combo). Owns the combo STATE (_combo_index, _attacking, the active
## blade-sweep tween) and drives one swing: an overhead arc chop for hits 1 & 2, a forward
## lunge for hit 3. PURE extraction -- behavior is identical to the pre-split player.gd; the
## player keeps a thin facade (attack / _combo_index / _attacking) that forwards here so tests
## and _simulate read/write player.X unchanged.
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
## The one-shot ComboResetTimer -- started at swing END to hold the continue-window open, and
## stopped when a swing begins so the window cannot expire mid-swing.
var _combo_reset_timer: Timer = null


## Wire the host + the shared SwordPivot / Blade / Sword CollisionShape2D / ComboResetTimer (the
## player "calls down" in its _ready), and take over the combo-reset timeout connection the
## player used to own -- on timeout the next swing restarts at hit 1. Mirrors Equipment.setup().
func setup(player: Node2D, sword_pivot: Node2D, blade: Polygon2D, sword_shape: CollisionShape2D,
		combo_reset_timer: Timer) -> void:
	_player = player
	_sword_pivot = sword_pivot
	_blade = blade
	_sword_shape = sword_shape
	_combo_reset_timer = combo_reset_timer
	# The combo continue-window: on timeout the next swing restarts at hit 1. Owned here now
	# (the player used to connect this in its _ready) so the combo state stays with the combo.
	_combo_reset_timer.timeout.connect(_on_combo_reset)


## Play a swing in the current facing direction, then retract the blade. Callable directly via
## the player.attack() facade -- the headless smoke test calls it, so attacking must NOT be gated
## solely behind real input. The equipped tool decides the STYLE: a combo weapon (the sword)
## chains arc -> arc -> lunge, pressing again within combo_window to continue; a regular tool
## (axe/pickaxe/unarmed) does a single arc swing per press with no chain (the tail's
## player._combo_enabled gate). The swing shape itself is still chosen by _combo_index.
func attack() -> void:
	if _attacking or _player._sword_broken:
		return
	_attacking = true
	# Continuing the combo: stop the reset so the window does not expire mid-swing.
	_combo_reset_timer.stop()

	var base: float = _player.facing.angle()
	var half: float = deg_to_rad(_player.arc_degrees / 2.0)

	match _combo_index:
		0, 1:
			# Arc hits (1 & 2): an OVERHEAD chop -- always sweeps from the TOP of the arc down
			# to the bottom ON SCREEN, for ANY facing. Screen +y is DOWN, so we start at the
			# endpoint that is higher (smaller sin) and finish at the lower one. A fixed
			# +half -> -half instead reads top-down for one facing but BOTTOM-UP for its mirror
			# -- the "backwards" swing when facing right. Both combo arcs strike downward.
			var arc: Array = _overhead_arc(base, half)
			_sword_pivot.rotation = arc[0]
			_begin_swing()
			await _sweep_to(arc[1])
		2:
			# Hit 3: lunge. Blade straight along facing; nudge the player forward
			# through the existing decaying-knockback system so it slides and stops.
			_sword_pivot.rotation = base
			_begin_swing()
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


## Enable the blade collision and show the silver rectangle for a swing.
func _begin_swing() -> void:
	_sword_shape.disabled = false
	_blade.visible = true


## Disable the blade collision and hide the rectangle after a swing. Guarded so a
## mid-swing death that freed these nodes cannot crash the retract.
func _end_swing() -> void:
	if is_instance_valid(_sword_shape):
		_sword_shape.disabled = true
	if is_instance_valid(_blade):
		_blade.visible = false


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
	_blade.visible = false
	if is_instance_valid(_sword_shape):
		_sword_shape.disabled = true

# Verified against: Godot 4.7.1 (2026-07-18)
