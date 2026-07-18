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

## Magnetic auto-pickup tunables (E3a, design-items.md "Drops -- Magnetic pickup"). The magnet
## ALGORITHM lives in components/pickup.gd (a RefCounted) which reads these three off the player
## each frame; they MUST stay as @export node fields (not move onto the component) because a test
## disables the magnet with `player.pickup_radius = 0.0` the SAME frame the scene is instantiated,
## BEFORE _ready creates _pickup -- only a plain node field accepts that pre-_ready write (see
## pickup.gd). Range in px a ground Drop is pulled from; ~72 is a couple tiles (WorldScale.TILE
## 40). 0 DISABLES pickup -- the lever a test uses when its player must sit amid un-collectable litter.
@export var pickup_radius: float = 72.0
## How fast a pulled Drop homes toward the player, in px/sec.
@export var pickup_pull_speed: float = 180.0
## Contact distance in px: once a pulled Drop is this close it is collected into the inventory.
@export var pickup_grab_radius: float = 12.0

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
## Equipment subsystem (E1a, components/equipment.gd): owns the inventory, the per-tool
## durability map, the active-tool/broken-gate state, and the inventory input. Created
## and wired in _ready. The forwarding facade below (inventory / _active_durability /
## _sword_broken getters + equip_tool / _apply_equipped) keeps `player.X` reads working
## for the tests and the HUD without them knowing the subsystem moved.
var _equipment: Equipment = null
var _interaction: Interaction = null  ## E4 (components/interaction.gd): pure-logic 'f'-harvest RefCounted (node-free like _equipment), made in _ready.
var _pickup: Pickup = null  ## E3a (components/pickup.gd): magnetic auto-pickup RefCounted (node-free like _equipment), made in _ready.
var _combat: Combat = null  ## Sword-combo subsystem (components/combat.gd): owns _combo_index/_attacking/the swing tween, made in _ready.
## Controlled movement velocity, kept separate from knockback so the two do not
## compound frame to frame.
var _move_velocity: Vector2 = Vector2.ZERO
## Decaying knockback impulse, added on top of movement. Also carries the lunge.
var _knockback: Vector2 = Vector2.ZERO
## Looping tween that blinks the avatar while invincible; null when not blinking.
var _blink_tween: Tween = null

@onready var _body: Polygon2D = $Body
@onready var _sword_pivot: Node2D = $SwordPivot
## The Sword Hitbox STAYS on the player (the Equipment holds a ref to this SAME node and
## writes tool stats onto it) so tests read `player._sword.atk` etc. unchanged.
@onready var _sword: Hitbox = $SwordPivot/Sword
@onready var _sword_shape: CollisionShape2D = $SwordPivot/Sword/CollisionShape2D
## Solid silver blade. It IS the hitbox extent (visual == collision), shown only
## during a swing.
@onready var _blade: Polygon2D = $SwordPivot/Sword/Blade
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: Hurtbox = $Hurtbox
## One-shot grace timer: while it runs, the next attack continues the combo; on
## timeout the combo resets to hit 1.
@onready var _combo_reset_timer: Timer = $ComboResetTimer


# --- Equipment facade (E1a) -----------------------------------------------------------
# Thin forwarders so the tests and the HUD keep reading `player.X` after the equipment
# subsystem moved to components/equipment.gd. Behaviour is identical -- these just relay
# to _equipment. The tool-data consts (SWORD_DATA/... , UNARMED_ATK) stay on Player above.

## Inventory model, owned by the Equipment. Forwarded so `player.inventory` reads/methods
## (tests + HUD) work unchanged.
var inventory: Inventory:
	get:
		return _equipment.inventory
## Active tool's runtime wear component, owned by the Equipment. Read by the HUD and a
## test via `player._active_durability`.
var _active_durability: DurabilityComponent:
	get:
		return _equipment._active_durability
## Broken-gate, owned by the Equipment. Read here in attack() and by a test via
## `player._sword_broken`.
var _sword_broken: bool:
	get:
		return _equipment._sword_broken
## Whether the equipped tool chains the full 3-hit combo (the sword). Axe/pickaxe/unarmed
## return false -> a single regular swing per press. Read in attack() to gate progression.
var _combo_enabled: bool:
	get:
		return _equipment.active_combos()


# --- Combat facade -------------------------------------------------------------------
# Thin forwarders so tests and _simulate keep reading/writing `player.X` after the combo subsystem
# moved to components/combat.gd. Both are accessed only AFTER _ready (unlike the pickup tunables,
# which had to stay real node fields to accept a pre-_ready write), so routing through _combat is safe.

## Which hit the NEXT attack() plays (0 arc A / 1 arc B / 2 lunge), owned by the Combat. Forwarded
## get+set: a test READS it (assert the combo advanced) and SETS it (`= 2` to force the lunge).
var _combo_index: int:
	get:
		return _combat._combo_index
	set(value):
		_combat._combo_index = value
## True while a swing is in flight, owned by the Combat. Forwarded get+set: a test's drain loop reads it (`if not player._attacking`); _respawn_in_place clears it.
var _attacking: bool:
	get:
		return _combat._attacking
	set(value):
		_combat._attacking = value


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
	# Equipment subsystem (E1a). A RefCounted (NOT a child node -- see equipment.gd for
	# why: a node would perturb the streaming node-count anchor). "Call down" the host
	# (self, for on-demand durability parenting) + the shared Sword Hitbox / Blade + the
	# three scene-authored DurabilityComponents. setup() seeds the durability map,
	# auto-populates the inventory, and equips the sword by default -- reproducing the
	# prior in-line _ready seeding exactly.
	_equipment = Equipment.new()
	_equipment.setup(self, _sword, _blade, $SwordDurability, $AxeDurability, $PickaxeDurability)
	_interaction = Interaction.new()  # E4: RefCounted like _equipment; scans "interactables" per frame.
	# Magnetic auto-pickup subsystem (E3a). A RefCounted (NOT a child node -- see pickup.gd; a node
	# perturbs the streaming node-count anchor). Player "calls down" into _pickup.process() each frame.
	_pickup = Pickup.new()
	# Sword-combo subsystem. A RefCounted (NOT a child node -- see combat.gd for why: a node would
	# perturb the streaming node-count anchor). "Call down" the host (self -- the swing creates its
	# tween/timer via the player, reads facing + tunables off it) + the SwordPivot / Blade / Sword
	# CollisionShape2D + the ComboResetTimer; setup() also adopts the combo-reset timeout connection.
	_combat = Combat.new()
	_combat.setup(self, _sword_pivot, _blade, _sword_shape, _combo_reset_timer)


## Equip a tool (facade -> Equipment.equip_tool). Directly callable -- a headless test
## calls player.equip_tool(...) to switch tools mid-run.
func equip_tool(tool: ToolData) -> void:
	_equipment.equip_tool(tool)


## Apply whatever the inventory has equipped (facade -> Equipment.apply_equipped).
## Directly callable by a test after driving inventory.equip_index(...).
func _apply_equipped() -> void:
	_equipment.apply_equipped()


## E4 facade -> Interaction: HUD reads interaction_prompt(); interact() harvests the nearby one (test-callable + action-button path).
func interaction_prompt() -> String:
	return _interaction.current_prompt()
func interact() -> void:
	_interaction.try_interact(self)


func _physics_process(delta: float) -> void:
	# The controller advances from an input STRUCT, never from Input directly, so a
	# networked peer / AI / test can drive the same _simulate() later.
	# _gather_input() is the ONLY place that touches the local InputMap.
	_simulate(delta, _gather_input())
	# Inventory hotkeys are their own concern (not part of the networked FrameInput
	# contract -- equip selection is a local UI action, not gameplay-simulation
	# state a peer/AI would drive), so they are read directly from the InputMap by the
	# Equipment here rather than routed through FrameInput. Same physics-frame cadence as
	# before the split.
	_equipment.process_inventory_input()
	# Magnetic auto-pickup (E3a). Like inventory input, this runs OUTSIDE the FrameInput /
	# _simulate seam: grabbing ground loot is a LOCAL world interaction, not networked simulation
	# state a peer/AI would replay -- see components/pickup.gd. The player calls down each frame.
	_pickup.process(self, delta)
	_interaction.process(self)  # E4: nearby scan + 'f'-harvest, node-free like the pickup pass (InputMap, not FrameInput).


## Mouse-wheel hotbar selection is an equipment concern; forward the event verbatim to
## the Equipment (a RefCounted, which cannot receive engine input callbacks itself).
## Same one-shot InputEventMouseButton handling as before the split.
func _unhandled_input(event: InputEvent) -> void:
	_equipment.handle_wheel_input(event)


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


## Play a swing in the current facing direction (facade -> Combat.attack). Callable directly
## -- the headless smoke test and _simulate above call it -- and it AWAITs (the swing spans
## swing_duration), so this facade must `await` the component or a caller that awaits
## player.attack() would resume a frame early. The combo STYLE (sword chains arc->arc->lunge,
## other tools single-swing) and the swing SHAPE (by _combo_index) all live in Combat now.
func attack() -> void:
	await _combat.attack()


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
	# Kill an in-flight blade sweep AND hide the blade + disable its hitbox so a mid-swing death
	# leaves no blade behind -- routed through the Combat, which owns the swing tween (there is a
	# test for mid-swing death). The body-hide below is a player concern and stays here.
	_combat.cancel_swing()
	# The avatar "pops": hide the body, replace with the burst.
	_body.visible = false
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


# --- Pickup facade (E3a) --------------------------------------------------------------
## Collect `count` of `item` into the inventory (facade -> Pickup.collect). The magnet's grab, and
## directly test/world-callable -- world/bush.gd harvests through player.collect(...). Passes self
## down so the RefCounted reaches the inventory; returns the overflow add_item could not fit
## (0 = all taken), so a full inventory leaves the loot for the caller, unchanged from the split.
func collect(item: ItemData, count: int) -> int:
	return _pickup.collect(self, item, count)

# Verified against: Godot 4.7.1 (2026-07-18)
