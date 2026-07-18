class_name Equipment
extends RefCounted
## Equipment subsystem, extracted from player.gd (E1a, design-items.md). Owns the
## tool/inventory/durability half of the player: the Inventory model, the per-tool
## runtime DurabilityComponent map, the active-tool/broken-gate state, and the
## number-key/scroll/Q-E/G inventory selection logic. PURE extraction -- behavior is
## identical to the pre-split player.gd; the player keeps a thin facade (equip_tool /
## _apply_equipped / _active_durability / _sword_broken / inventory) that forwards
## here so tests and the HUD read player.X unchanged.
##
## RefCounted, NOT a Node: adding an Equipment Node to the player's subtree would bump
## the global Performance.OBJECT_NODE_COUNT (or ORPHAN count), which the streaming
## zero-orphan-leak assertion prints as a literal baseline -- changing that message and
## breaking the E1a "same 142 assertions, byte-identical" anchor. As a RefCounted it is
## invisible to both node monitors, so the refactor is truly behavior-neutral. The
## player owns the frame/input seam (its _physics_process calls process_inventory_input,
## its _unhandled_input forwards the mouse wheel here); on-demand durability components
## are parented to the player via the `_host` passed into setup() -- exactly where the
## pre-split code add_child'd them.
##
## "Call down" wiring (patterns/scene-composition.md): the player passes the shared
## Sword Hitbox, the Blade Polygon2D, and the three scene-authored DurabilityComponent
## nodes into setup(); this object writes tool stats/colour onto them but never reaches
## up into the player. The tool-data consts (SWORD_DATA/AXE_DATA/PICKAXE_DATA,
## UNARMED_ATK/UNARMED_COLOR) stay on Player and are read here as Player.X, so the
## const references in the tests do not churn.

## Fallback blade silhouette (the pre-shapes rectangle: x[-15,15] y[-3,3]) used when a tool
## defines no blade_shape, and for the unarmed fist. Equip always sets the Blade polygon to
## either the tool's shape or this, so switching from a shaped tool back to a shapeless one (or
## to unarmed) restores the plain blade instead of leaving the previous tool's outline behind.
static var DEFAULT_BLADE_SHAPE: PackedVector2Array = PackedVector2Array([
	Vector2(-15, -3), Vector2(15, -3), Vector2(15, 3), Vector2(-15, 3),
])

## Inventory & hotbar (design-inventory.md). Pure logic object, standalone testable
## (`Inventory.new()` with no player/scene needed). Reached from the player via a
## forwarding getter (`player.inventory`) so a test can drive equip-by-slot-index
## end-to-end, and so number keys / scroll / Q/E / G all funnel through this node's
## apply_equipped() chokepoint.
var inventory: Inventory = Inventory.new()

## Latched true when the ACTIVE tool's durability hits 0. While broken, the player's
## attack() (which reads this via the facade) is a no-op until repair -- later.
## Re-derived from the active DurabilityComponent's is_broken() on every equip_tool()
## call, so switching to a fresh (unbroken) tool un-gates attacks immediately.
var _sword_broken: bool = false
## The tool currently equipped (System 3, design-durability.md). Set by equip_tool();
## defaulted to the sword at the end of setup() so combat/attack behaviour is unchanged.
var _active_tool: ToolData = null
## The active tool's RUNTIME wear component -- whichever DurabilityComponent is
## currently wired into the Sword Hitbox's `durability`. Read by the HUD via the
## player facade (`player._active_durability`).
var _active_durability: DurabilityComponent = null
## Per-tool runtime DurabilityComponent, keyed by ToolData.resource_path. Seeded in
## setup() with the three built-in tools' scene-authored nodes (durability is per-tool,
## never shared -- the resource-sharing trap, patterns/resource-driven-design.md). A
## ToolData equipped later with no entry here gets a fresh DurabilityComponent
## instantiated on demand (see _durability_for).
var _durability_by_tool: Dictionary = {}

## The shared Sword Hitbox (equip writes atk/power/break_threshold/wear_max/harvest_type
## and the active `durability` onto it). Same node the player exposes as `_sword`, so
## tests read `player._sword.atk` etc. after an equip here.
var _sword: Hitbox = null
## The blade Polygon2D that equip retints to the tool colour (or the unarmed fist tint).
var _blade: Polygon2D = null
## The three scene-authored per-tool wear components, passed down by the player.
var _sword_durability: DurabilityComponent = null
var _axe_durability: DurabilityComponent = null
var _pickaxe_durability: DurabilityComponent = null
## The Node an on-demand DurabilityComponent is parented to (the player) -- exactly the
## node the pre-split code called add_child() on.
var _host: Node = null


## Wire the host + the shared Sword Hitbox / Blade / three built-in DurabilityComponents
## (the player "calls down" in its _ready), seed the per-tool durability map +
## auto-populate the starting inventory in TOOL-PRIORITY order, then equip the sword by
## default via the SAME apply_equipped() chokepoint the inventory input uses --
## reproducing the pre-split player._ready seeding exactly.
func setup(host: Node, sword: Hitbox, blade: Polygon2D, sword_dura: DurabilityComponent,
		axe_dura: DurabilityComponent, pickaxe_dura: DurabilityComponent) -> void:
	_host = host
	_sword = sword
	_blade = blade
	_sword_durability = sword_dura
	_axe_durability = axe_dura
	_pickaxe_durability = pickaxe_dura
	# Seed the per-tool durability map with the three built-in tools' scene-authored
	# components (durability is per-tool, never shared).
	_durability_by_tool[Player.SWORD_DATA.resource_path] = _sword_durability
	_durability_by_tool[Player.AXE_DATA.resource_path] = _axe_durability
	_durability_by_tool[Player.PICKAXE_DATA.resource_path] = _pickaxe_durability
	# Auto-populate the starting loadout in TOOL-PRIORITY order -- add_tool() itself
	# just fills first-empty, so the priority ordering comes from this call order.
	inventory.add_tool(Player.SWORD_DATA)
	inventory.add_tool(Player.AXE_DATA)
	inventory.add_tool(Player.PICKAXE_DATA)
	# equipped_index defaults to 0 (the sword), so this reproduces the prior hardcoded
	# equip_tool(SWORD_DATA) default via the SAME chokepoint the input also calls into.
	apply_equipped()


## Equip a tool: swap its stats onto the Sword Hitbox (atk/power/break_threshold/
## wear_max/harvest_type -- Systems 1/2/3), swap its OWN runtime DurabilityComponent
## into hitbox.durability (each tool's wear is independent, never shared), retint the
## blade, and re-latch the broken-gate to whichever tool is now active. Directly
## callable -- this is the ONE chokepoint the inventory/hotbar input calls into instead
## of reinventing tool-switching. A headless test calls it (via player.equip_tool) to
## switch tools mid-run.
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
	# Swap the Blade's SILHOUETTE to this tool's shape (a pointed sword, a broad axe head,
	# a double-pointed pick) -- presentation only, the invisible Hitbox rectangle is
	# unchanged. An empty blade_shape falls back to the plain rectangle.
	_blade.polygon = tool.blade_shape if not tool.blade_shape.is_empty() else DEFAULT_BLADE_SHAPE


## Inventory & hotbar chokepoint (design-inventory.md): reads whatever the inventory
## currently has equipped and applies it to the Sword Hitbox -- a real ToolData via the
## EXISTING equip_tool(), or the unarmed fallback via _apply_unarmed() when the equipped
## slot is empty. Number keys, scroll, and Q/E all funnel through this ONE method so
## equip behaves identically no matter which input triggered it. Directly callable by a
## test (via player._apply_equipped) with no real input needed.
func apply_equipped() -> void:
	var tool: ToolData = inventory.equipped_tool()
	if tool != null:
		equip_tool(tool)
	else:
		_apply_unarmed()


## Unarmed fallback (design-inventory.md): the equipped slot is empty. Sets the Sword
## Hitbox to a low flat ATK with NO durability/harvest interaction -- power/
## break_threshold/wear_max all 0, harvest_type NONE, and `durability` left null so the
## Hurtbox chokepoint's `if hitbox.durability != null` skip means no wear is ever
## attempted (nothing to wear -- there is no weapon). Converges on the same Sword Hitbox
## fields equip_tool() sets, just with the constant fallback block instead of a ToolData's.
func _apply_unarmed() -> void:
	if _active_durability != null and _active_durability.broke.is_connected(_on_tool_broke):
		_active_durability.broke.disconnect(_on_tool_broke)
	_active_tool = null
	_active_durability = null
	_sword_broken = false
	_sword.durability = null
	_sword.atk = Player.UNARMED_ATK
	_sword.power = 0
	_sword.break_threshold = 0
	_sword.wear_max = 0
	_sword.harvest_type = Harvest.Type.NONE
	_blade.color = Player.UNARMED_COLOR
	# No tool: restore the plain rectangle blade (the fist swing), never a stale tool outline.
	_blade.polygon = DEFAULT_BLADE_SHAPE


## Look up (or lazily create) the RUNTIME DurabilityComponent for `tool`, keyed by its
## resource path so a future ToolData outside the three built-in nodes (a new inventory
## item) still gets its own independent wear counter instead of reusing someone else's
## -- current durability is never stored on the shared ToolData resource itself (the
## sharing trap, patterns/resource-driven-design.md). An on-demand component is parented
## to this Equipment node so its _ready runs (current_durability = max_durability).
func _durability_for(tool: ToolData) -> DurabilityComponent:
	var key: String = tool.resource_path
	if _durability_by_tool.has(key):
		return _durability_by_tool[key]
	var dura: DurabilityComponent = DurabilityComponent.new()
	dura.max_durability = tool.max_durability
	_host.add_child(dura)
	_durability_by_tool[key] = dura
	return dura


## Active tool's durability hit 0: gate the blade. The player's attack() no-ops (reading
## _sword_broken via the facade) until repair (later), so a broken tool deals no HP
## damage and takes no further wear.
func _on_tool_broke() -> void:
	_sword_broken = true
	print("[player] ", _active_tool.display_name, " broke -- attacks disabled until repaired")


## Inventory & hotbar keys (design-inventory.md): number keys 1-9,0 jump directly to
## their mapped slot (key '1' -> index 0, ... '9' -> index 8, '0' -> index 9, the fixed
## 10-position ring), ALWAYS, regardless of lock state. Q/E cycle the current ring by
## -1/+1 -- same convention as the scroll wheel (Q mirrors scroll up = previous, E
## mirrors scroll down = next). G toggles the hotbar lock. Every branch re-applies via
## the SAME apply_equipped() chokepoint the scroll-wheel handler and setup() also use, so
## equip behaves identically no matter which input triggered it. Called from the player's
## _physics_process (unchanged cadence) -- inventory input is read directly from the
## InputMap, NOT via FrameInput, exactly as before the split.
func process_inventory_input() -> void:
	if Input.is_action_just_pressed("tool_1"):
		inventory.equip_index(0)
		apply_equipped()
	elif Input.is_action_just_pressed("tool_2"):
		inventory.equip_index(1)
		apply_equipped()
	elif Input.is_action_just_pressed("tool_3"):
		inventory.equip_index(2)
		apply_equipped()
	elif Input.is_action_just_pressed("tool_4"):
		inventory.equip_index(3)
		apply_equipped()
	elif Input.is_action_just_pressed("tool_5"):
		inventory.equip_index(4)
		apply_equipped()
	elif Input.is_action_just_pressed("tool_6"):
		inventory.equip_index(5)
		apply_equipped()
	elif Input.is_action_just_pressed("tool_7"):
		inventory.equip_index(6)
		apply_equipped()
	elif Input.is_action_just_pressed("tool_8"):
		inventory.equip_index(7)
		apply_equipped()
	elif Input.is_action_just_pressed("tool_9"):
		inventory.equip_index(8)
		apply_equipped()
	elif Input.is_action_just_pressed("tool_0"):
		inventory.equip_index(9)
		apply_equipped()

	if Input.is_action_just_pressed("inventory_prev"):
		inventory.cycle(-1)
		apply_equipped()
	elif Input.is_action_just_pressed("inventory_next"):
		inventory.cycle(1)
		apply_equipped()

	if Input.is_action_just_pressed("toggle_hotbar_unlock"):
		inventory.hotbar_unlocked = not inventory.hotbar_unlocked
		print("[player] hotbar unlock: ", inventory.hotbar_unlocked)


## Mouse wheel selection (design-inventory.md): scroll up = previous, scroll down = next
## (same ring/lock rules as Q/E). The wheel has no clean "just pressed" via the Input
## singleton -- it arrives as a one-shot InputEventMouseButton with pressed=true,
## followed by a synthetic released on the same input flush. Acting only on the
## pressed=true edge means one notch triggers exactly one cycle, never two. Forwarded
## verbatim from the player's _unhandled_input (this is a RefCounted, so it cannot get
## engine input callbacks itself) -- identical handling to the pre-split player.
func handle_wheel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			inventory.cycle(-1)
			apply_equipped()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inventory.cycle(1)
			apply_equipped()

# Verified against: Godot 4.7.1 (2026-07-18)
