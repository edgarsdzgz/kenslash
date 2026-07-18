class_name Player
extends CharacterBody2D
## Top-down 8-direction player with a facing-directed 3-hit sword combo.
## Movement follows recipes/topdown-movement.md; the blade follows the
## Hitbox/Hurtbox scheme in recipes/health-and-damage.md. The blade IS the
## hitbox now -- the visible silver rectangle exactly matches the collision
## shape, so there is no separate debug overlay (assetless).
##
## Input-struct driven: _simulate() consumes a FrameInput and reads NO input
## globals, so the same controller can run from the local keyboard, a networked
## peer, AI, or a test. The multiplayer guardrail -- patterns/multiplayer-architecture.md.

## Top speed in pixels per second.
@export var max_speed: float = 140.0
## How fast velocity approaches the target, in pixels/sec^2.
@export var acceleration: float = 1400.0
## How fast velocity returns to zero with no input, in pixels/sec^2.
@export var friction: float = 1200.0
## Total sweep angle of an arc hit (hits 0 and 1), in degrees. The blade travels
## from +arc/2 to -arc/2 of the facing angle (or the reverse on hit 1).
@export var arc_degrees: float = 120.0
## How long one swing (arc or lunge) lasts, in seconds. THIS IS THE ATTACK-SPEED
## STAT: lower = faster, lighter swings; an upgrade can drive it down for power
## escalation. The swing is hard-gated -- a swing must finish before the next can
## start, and presses during a swing are dropped (no buffer) -- and the combo
## window opens only at swing END, so a faster swing never shortens the grace.
@export var swing_duration: float = 0.12
## Grace window after a swing to continue the combo, in seconds. Miss it and the
## next attack restarts at hit 1.
@export var combo_window: float = 0.5
## Forward impulse fed into the decaying-knockback system on the hit-3 lunge, in
## pixels/sec. Reuses _knockback so the player slides forward briefly and stops.
@export var lunge_impulse: float = 140.0
## How fast a knockback impulse bleeds back to zero, in pixels/sec^2.
@export var knockback_decay: float = 1200.0

## System 3 -- tool categories (design-durability.md). The three built-in tools this
## build ships with. A future inventory/hotbar build will load ToolData resources
## dynamically instead of hardcoding these three; equip_tool() already accepts ANY
## ToolData, so these consts are just this build's starting roster.
const SWORD_DATA: ToolData = preload("res://data/sword_data.tres")
const AXE_DATA: ToolData = preload("res://data/axe_data.tres")
const PICKAXE_DATA: ToolData = preload("res://data/pickaxe_data.tres")

## Inventory & hotbar (design-inventory.md). Flat ATK dealt while the equipped
## slot is empty -- no durability/harvest interaction (nothing to wear, no tool to
## gather with). A constant fallback stat block, NOT a real inventory item.
const UNARMED_ATK: int = 1
## Neutral fist-tint for the blade while unarmed, so the swing still reads visibly
## even with no weapon equipped.
const UNARMED_COLOR: Color = Color(0.85, 0.75, 0.65, 1.0)

## Last non-zero movement direction; kept while idle. Drives sword aim (the full
## 8-directional combo) -- unaffected by the body-facing rule below. Public and
## settable so a headless test can aim the slash without real keyboard input.
var facing: Vector2 = Vector2.RIGHT
## Last SIDE (left/right) the player faced: +1 = right, -1 = left. Drives ONLY the
## Body's left/right flip -- unlike `facing`, this does NOT change on a pure
## up/down press (no x component), so the body never flips just because the
## player moved vertically. Public and settable so a test can check it directly.
var side_facing: int = 1
## If set, replaces local input gathering each tick -- the injection point for
## networked peer input, AI, or tests. Null = read the local InputMap.
var input_override: FrameInput = null
## Respawn policy (design-playable-loop.md D1). Vector2.INF (both components infinite) =
## NO respawn point set -> reload the scene on death (the arena's round-restart, unchanged).
## A FINITE value = respawn IN PLACE here, KEEPING the streamed world (ChunkManager + its
## delta store survive). streaming_world.gd sets this to the spawn origin.
var respawn_point: Vector2 = Vector2.INF

## Which hit of the combo the NEXT attack() will play: 0 -> arc A, 1 -> arc B,
## 2 -> lunge. Advances each swing and wraps 2 -> 0. Public so a test can read it.
var _combo_index: int = 0
var _attacking: bool = false
## Latched true when the ACTIVE tool's durability hits 0. While broken, attack() is
## a no-op (no swing, so no HP damage and no further wear) until repair -- later.
## Re-derived from the active DurabilityComponent's is_broken() on every equip_tool()
## call, so switching to a fresh (unbroken) tool un-gates attacks immediately.
var _sword_broken: bool = false
## The tool currently equipped (System 3, design-durability.md). Set by equip_tool();
## defaulted to the sword at the end of _ready so existing combo/attack behavior is
## unchanged out of the box.
var _active_tool: ToolData = null
## The active tool's RUNTIME wear component -- whichever DurabilityComponent is
## currently wired into the Sword Hitbox's `durability`.
var _active_durability: DurabilityComponent = null
## Per-tool runtime DurabilityComponent, keyed by ToolData.resource_path. Seeded in
## _ready with the three built-in tools' scene-authored nodes (durability is per-tool,
## never shared -- the resource-sharing trap, patterns/resource-driven-design.md). A
## ToolData equipped later with no entry here gets a fresh DurabilityComponent
## instantiated on demand (see _durability_for) -- the chokepoint the next (inventory)
## build calls into instead of reinventing tool-switching.
var _durability_by_tool: Dictionary = {}
## Inventory & hotbar (design-inventory.md). Pure logic object, standalone
## testable (`Inventory.new()` with no player/scene needed). Public so a test can
## drive equip-by-slot-index end-to-end, and so number keys / scroll / Q/E / G can
## all funnel through it from a single chokepoint (_apply_equipped below).
var inventory: Inventory = Inventory.new()
## Controlled movement velocity, kept separate from knockback so the two do not
## compound frame to frame.
var _move_velocity: Vector2 = Vector2.ZERO
## Decaying knockback impulse, added on top of movement. Also carries the lunge.
var _knockback: Vector2 = Vector2.ZERO
## Looping tween that blinks the avatar while invincible; null when not blinking.
var _blink_tween: Tween = null
## Active blade-sweep tween; killed on death so a mid-swing death leaves no blade.
var _swing_tween: Tween = null

@onready var _body: Polygon2D = $Body
@onready var _sword_pivot: Node2D = $SwordPivot
@onready var _sword: Hitbox = $SwordPivot/Sword
@onready var _sword_shape: CollisionShape2D = $SwordPivot/Sword/CollisionShape2D
## The sword's runtime wear (System 2). equip_tool() wires whichever tool's
## DurabilityComponent is active into the Sword Hitbox so the Hurtbox chokepoint can
## wear it; when it breaks, the blade is gated.
@onready var _sword_durability: DurabilityComponent = $SwordDurability
## Same runtime wear for the axe and pickaxe -- current durability is per-tool,
## never shared. equip_tool() swaps whichever of these (or an on-demand one) is
## active into the Sword Hitbox's `durability`.
@onready var _axe_durability: DurabilityComponent = $AxeDurability
@onready var _pickaxe_durability: DurabilityComponent = $PickaxeDurability
## Solid silver blade. It IS the hitbox extent (visual == collision), shown only
## during a swing.
@onready var _blade: Polygon2D = $SwordPivot/Sword/Blade
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: Hurtbox = $Hurtbox
## One-shot grace timer: while it runs, the next attack continues the combo; on
## timeout the combo resets to hit 1.
@onready var _combo_reset_timer: Timer = $ComboResetTimer


func _ready() -> void:
	# The enemy AI resolves its target through this group, so it never needs a
	# hard node path to the player.
	add_to_group("player")
	# Parent wires its own components ("call down"); the Hurtbox never reaches
	# for the HealthComponent itself, and nothing is wired via the inspector.
	_hurtbox.health = _health
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	# Hit feedback: knockback on any hit, and blink for the i-frame window.
	_hurtbox.hit_taken.connect(_on_hit_taken)
	_hurtbox.invincibility_started.connect(_on_invincibility_started)
	_hurtbox.invincibility_ended.connect(_on_invincibility_ended)
	# Combo continue-window: on timeout the next swing restarts at hit 1.
	_combo_reset_timer.timeout.connect(_on_combo_reset)
	# System 3 -- tool categories (design-durability.md). Seed the per-tool durability
	# map with the three built-in tools' scene-authored components, then equip the
	# sword by default so existing combo/attack behavior is unchanged out of the box.
	_durability_by_tool[SWORD_DATA.resource_path] = _sword_durability
	_durability_by_tool[AXE_DATA.resource_path] = _axe_durability
	_durability_by_tool[PICKAXE_DATA.resource_path] = _pickaxe_durability
	# Inventory & hotbar (design-inventory.md). Auto-populate the starting loadout
	# in TOOL-PRIORITY order -- add_tool() itself just fills first-empty, so the
	# priority ordering comes from the order these three calls happen in.
	inventory.add_tool(SWORD_DATA)
	inventory.add_tool(AXE_DATA)
	inventory.add_tool(PICKAXE_DATA)
	# equipped_index defaults to 0 (the sword), so this reproduces the prior
	# hardcoded equip_tool(SWORD_DATA) default via the SAME chokepoint the
	# inventory-driven input (number keys / scroll / Q/E) also calls into.
	_apply_equipped()


## Equip a tool: swap its stats onto the Sword Hitbox (atk/power/break_threshold/
## wear_max/harvest_type -- Systems 1/2/3), swap its OWN runtime DurabilityComponent
## into hitbox.durability (each tool's wear is independent, never shared), retint the
## blade, and re-latch the broken-gate to whichever tool is now active. Directly
## callable -- this is the ONE chokepoint the next build (inventory/hotbar) calls into
## instead of reinventing tool-switching. Not gated behind real input this build; a
## headless test calls it directly to switch tools mid-run.
func equip_tool(tool: ToolData) -> void:
	if tool == null:
		return
	var dura: DurabilityComponent = _durability_for(tool)
	# Stop listening for the PREVIOUS tool's break before wiring the new one, so a
	# broken axe re-latching does not also fire off the sword's stale connection.
	if _active_durability != null and _active_durability.broke.is_connected(_on_tool_broke):
		_active_durability.broke.disconnect(_on_tool_broke)
	_active_tool = tool
	_active_durability = dura
	if not _active_durability.broke.is_connected(_on_tool_broke):
		_active_durability.broke.connect(_on_tool_broke)
	# A previously-broken tool re-equipped must re-latch the gate immediately -- its
	# `broke` signal already fired in the past and will not fire again.
	_sword_broken = _active_durability.is_broken()
	_sword.durability = _active_durability
	_sword.atk = tool.atk
	_sword.power = tool.power
	_sword.break_threshold = tool.break_threshold
	_sword.wear_max = tool.wear_max
	_sword.harvest_type = tool.harvest_type
	_blade.color = tool.blade_color


## Inventory & hotbar chokepoint (design-inventory.md): reads whatever the
## inventory currently has equipped and applies it to the Sword Hitbox -- a real
## ToolData via the EXISTING equip_tool(), or the unarmed fallback via
## _apply_unarmed() when the equipped slot is empty. Number keys, scroll, and Q/E
## all funnel through this ONE method so equip behaves identically no matter which
## input triggered it. Directly callable by a test with no real input needed.
func _apply_equipped() -> void:
	var tool: ToolData = inventory.equipped_tool()
	if tool != null:
		equip_tool(tool)
	else:
		_apply_unarmed()


## Unarmed fallback (design-inventory.md): the equipped slot is empty. Sets the
## Sword Hitbox to a low flat ATK with NO durability/harvest interaction -- power/
## break_threshold/wear_max all 0, harvest_type NONE, and `durability` left null so
## the Hurtbox chokepoint's `if hitbox.durability != null` skip means no wear is
## ever attempted (nothing to wear -- there is no weapon). Converges on the same
## Sword Hitbox fields equip_tool() sets, just with the constant fallback block
## instead of a ToolData's.
func _apply_unarmed() -> void:
	if _active_durability != null and _active_durability.broke.is_connected(_on_tool_broke):
		_active_durability.broke.disconnect(_on_tool_broke)
	_active_tool = null
	_active_durability = null
	_sword_broken = false
	_sword.durability = null
	_sword.atk = UNARMED_ATK
	_sword.power = 0
	_sword.break_threshold = 0
	_sword.wear_max = 0
	_sword.harvest_type = Harvest.Type.NONE
	_blade.color = UNARMED_COLOR


## Look up (or lazily create) the RUNTIME DurabilityComponent for `tool`, keyed by its
## resource path so a future ToolData outside the three built-in nodes (a new
## inventory item) still gets its own independent wear counter instead of reusing
## someone else's -- current durability is never stored on the shared ToolData
## resource itself (the sharing trap, patterns/resource-driven-design.md).
func _durability_for(tool: ToolData) -> DurabilityComponent:
	var key: String = tool.resource_path
	if _durability_by_tool.has(key):
		return _durability_by_tool[key]
	var dura: DurabilityComponent = DurabilityComponent.new()
	dura.max_durability = tool.max_durability
	add_child(dura)
	_durability_by_tool[key] = dura
	return dura


func _physics_process(delta: float) -> void:
	# The controller advances from an input STRUCT, never from Input directly, so a
	# networked peer / AI / test can drive the same _simulate() later.
	# _gather_input() is the ONLY place that touches the local InputMap.
	_simulate(delta, _gather_input())
	# Inventory hotkeys are their own concern (not part of the networked FrameInput
	# contract -- equip selection is a local UI action, not gameplay-simulation
	# state a peer/AI would drive), so they are read directly from the InputMap
	# here rather than routed through FrameInput.
	_process_inventory_input()


## Produce this tick's intent. Local source reads the InputMap; if input_override is
## set (networked peer input, AI, or a test) that is used instead. This is the swap
## point -- see patterns/multiplayer-architecture.md.
func _gather_input() -> FrameInput:
	if input_override != null:
		return input_override
	var fi: FrameInput = FrameInput.new()
	# get_vector is already deadzone-filtered and length-clamped to 1.0, so diagonals
	# are not sqrt(2) faster. Do NOT normalize it again.
	fi.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	fi.attack = Input.is_action_just_pressed("attack")
	return fi


## Inventory & hotbar keys (design-inventory.md): number keys 1-9,0 jump directly
## to their mapped slot (key '1' -> index 0, ... '9' -> index 8, '0' -> index 9,
## the fixed 10-position ring), ALWAYS, regardless of lock state. Q/E cycle the
## current ring by -1/+1 -- same convention as the scroll wheel (Q mirrors scroll
## up = previous, E mirrors scroll down = next). G toggles the hotbar lock. Every
## branch re-applies via the SAME _apply_equipped() chokepoint the scroll-wheel
## handler and _ready() also use, so equip behaves identically no matter which
## input triggered it.
func _process_inventory_input() -> void:
	if Input.is_action_just_pressed("tool_1"):
		inventory.equip_index(0)
		_apply_equipped()
	elif Input.is_action_just_pressed("tool_2"):
		inventory.equip_index(1)
		_apply_equipped()
	elif Input.is_action_just_pressed("tool_3"):
		inventory.equip_index(2)
		_apply_equipped()
	elif Input.is_action_just_pressed("tool_4"):
		inventory.equip_index(3)
		_apply_equipped()
	elif Input.is_action_just_pressed("tool_5"):
		inventory.equip_index(4)
		_apply_equipped()
	elif Input.is_action_just_pressed("tool_6"):
		inventory.equip_index(5)
		_apply_equipped()
	elif Input.is_action_just_pressed("tool_7"):
		inventory.equip_index(6)
		_apply_equipped()
	elif Input.is_action_just_pressed("tool_8"):
		inventory.equip_index(7)
		_apply_equipped()
	elif Input.is_action_just_pressed("tool_9"):
		inventory.equip_index(8)
		_apply_equipped()
	elif Input.is_action_just_pressed("tool_0"):
		inventory.equip_index(9)
		_apply_equipped()

	if Input.is_action_just_pressed("inventory_prev"):
		inventory.cycle(-1)
		_apply_equipped()
	elif Input.is_action_just_pressed("inventory_next"):
		inventory.cycle(1)
		_apply_equipped()

	if Input.is_action_just_pressed("toggle_hotbar_unlock"):
		inventory.hotbar_unlocked = not inventory.hotbar_unlocked
		print("[player] hotbar unlock: ", inventory.hotbar_unlocked)


## Mouse wheel selection (design-inventory.md): scroll up = previous, scroll down
## = next (same ring/lock rules as Q/E). The wheel has no clean "just pressed" via
## the Input singleton -- it arrives here as a one-shot InputEventMouseButton with
## pressed=true, followed by a synthetic released on the same input flush. Acting
## only on the pressed=true edge means one notch triggers exactly one cycle, never
## two.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			inventory.cycle(-1)
			_apply_equipped()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inventory.cycle(1)
			_apply_equipped()


## Advance the controller one physics tick from an input struct. Reads NO input
## globals -- identical code runs for local, networked, AI, or test input.
func _simulate(delta: float, input: FrameInput) -> void:
	if input.move != Vector2.ZERO:
		facing = input.move
		_move_velocity = _move_velocity.move_toward(input.move * max_speed, acceleration * delta)
	else:
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, friction * delta)

	# The Body's D-shape is a LEFT/RIGHT FLIP via scale.x = +/-1 (a true horizontal
	# mirror around the vertical axis). NOT rotation: a 180deg rotation flips the
	# base-anchored polygon vertically too, dropping the shape down the screen.
	# side_facing only updates when there is an x component -- a pure up/down press
	# leaves it untouched, so the body never flips on vertical-only movement.
	# `facing` (full direction, used for sword aim) still updates from every non-zero
	# input above, unchanged.
	if input.move.x > 0.0:
		side_facing = 1
	elif input.move.x < 0.0:
		side_facing = -1
	_body.scale.x = float(side_facing)

	# Controlled movement plus a decaying knockback impulse (also the lunge slide).
	velocity = _move_velocity + _knockback
	move_and_slide()
	_knockback = _knockback.move_toward(Vector2.ZERO, knockback_decay * delta)

	if input.attack:
		attack()


## Play the next hit of the 3-hit combo in the current facing direction, then
## retract the blade. Callable directly -- the headless smoke test calls this, so
## attacking must NOT be gated solely behind real input. Pressing again within
## combo_window continues the chain; after hit 3 it wraps back to hit 1.
func attack() -> void:
	if _attacking or _sword_broken:
		return
	_attacking = true
	# Continuing the combo: stop the reset so the window does not expire mid-swing.
	_combo_reset_timer.stop()

	var base: float = facing.angle()
	var half: float = deg_to_rad(arc_degrees / 2.0)

	match _combo_index:
		0:
			# Hit 1: arc sweep, direction A (+half -> -half).
			_sword_pivot.rotation = base + half
			_begin_swing()
			await _sweep_to(base - half)
		1:
			# Hit 2: arc sweep, direction B (-half -> +half), the opposite way.
			_sword_pivot.rotation = base - half
			_begin_swing()
			await _sweep_to(base + half)
		2:
			# Hit 3: lunge. Blade straight along facing; nudge the player forward
			# through the existing decaying-knockback system so it slides and stops.
			_sword_pivot.rotation = base
			_begin_swing()
			_knockback = facing * lunge_impulse
			await get_tree().create_timer(swing_duration).timeout

	_end_swing()
	# Advance the combo and open the continue-window. Bail if a mid-swing death
	# freed us out of the tree.
	if not is_inside_tree():
		return
	_combo_index = (_combo_index + 1) % 3
	_attacking = false
	_combo_reset_timer.start(combo_window)


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
## the tween so death can cancel it.
func _sweep_to(target: float) -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.tween_property(_sword_pivot, "rotation", target, swing_duration)
	await _swing_tween.finished


## Combo grace window expired: the next attack restarts at hit 1.
func _on_combo_reset() -> void:
	_combo_index = 0


## Active tool's durability hit 0: gate the blade. attack() no-ops until repair
## (later), so a broken tool deals no HP damage and takes no further wear.
func _on_tool_broke() -> void:
	_sword_broken = true
	print("[player] ", _active_tool.display_name, " broke -- attacks disabled until repaired")


## Flash white on a hit, then tween back -- same overbright trick the enemy uses.
func _on_damaged(_amount: int, current: int) -> void:
	print("[player] took damage, health now ", current)
	_body.modulate = Color(10.0, 10.0, 10.0)
	var tween: Tween = create_tween()
	tween.tween_property(_body, "modulate", Color.WHITE, 0.25)


## Take a knockback impulse away from whatever hitbox struck us. Magnitude is the
## attacker's data, so different attacks can shove harder or softer.
func _on_hit_taken(hitbox: Hitbox) -> void:
	var dir: Vector2 = global_position - hitbox.global_position
	if dir.length() > 0.001:
		_knockback = dir.normalized() * hitbox.knockback


## Blink the avatar on/off for the whole i-frame window so the player can read
## that they are temporarily invulnerable. Toggles visibility (not modulate) so it
## never fights the white hit-flash tween.
func _on_invincibility_started() -> void:
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	_blink_tween = create_tween().set_loops()
	_blink_tween.tween_callback(func() -> void: _body.visible = false)
	_blink_tween.tween_interval(0.08)
	_blink_tween.tween_callback(func() -> void: _body.visible = true)
	_blink_tween.tween_interval(0.08)


func _on_invincibility_ended() -> void:
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	_body.visible = true


## On death: stop the level, pop the avatar into a burst of circles, then restart
## the round. Guarded so a queued-free player cannot touch the tree afterward.
func _on_died() -> void:
	print("[player] died")
	# Stop the level. SceneTreeTimer defaults to process_always, and the burst is
	# PROCESS_MODE_ALWAYS, so both keep running while everything else freezes.
	get_tree().paused = true
	# Stop any i-frame blink so it cannot re-show the body mid-burst.
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	# Kill an in-flight blade sweep so a mid-swing death leaves no blade behind.
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	# The avatar "pops": hide it and its blade, replace with the burst.
	_body.visible = false
	_blade.visible = false
	if is_instance_valid(_sword_shape):
		_sword_shape.disabled = true
	var burst: DeathBurst = DeathBurst.new()
	burst.color = _body.color
	get_parent().add_child(burst)
	burst.global_position = global_position
	burst.play()
	await burst.finished
	# Small beat on the empty, frozen level, then branch on the respawn policy.
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree():
		return
	# A FINITE respawn point -> respawn in place and KEEP the streamed world. Vector2.INF
	# (the default) -> reload the scene, the arena's unchanged round-restart.
	if is_finite(respawn_point.x) and is_finite(respawn_point.y):
		_respawn_in_place()
	else:
		get_tree().paused = false
		get_tree().reload_current_scene()


## Respawn in place at respawn_point WITHOUT reloading the scene, so the streamed world
## (ChunkManager + its delta store) stays intact (design-playable-loop.md D1). Unpause,
## reposition, revive to full HP, clear motion/combo/attack state, drop any latched
## i-frames, and restore a fresh unbroken pose -- fully playable again, able to die AGAIN.
func _respawn_in_place() -> void:
	get_tree().paused = false
	global_position = respawn_point
	_health.revive()
	_knockback = Vector2.ZERO
	_move_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	_combo_index = 0
	_attacking = false
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	# Real-play death arrives through the Hurtbox, latching i-frames; clear so damage lands.
	_hurtbox.is_invincible = false
	_body.visible = true
	_body.modulate = Color.WHITE
	_blade.visible = false
	if is_instance_valid(_sword_shape):
		_sword_shape.disabled = true

# Verified against: Godot 4.7.1 (2026-07-17)
