class_name Hud
extends CanvasLayer
## Minimal in-game HUD for the playable loop (design-playable-loop.md D2). PRESENTATION
## ONLY: it READS live player/inventory/health/durability state and renders it. It owns
## NO game state, mutates NOTHING, and adds NO signals to player.gd (per
## patterns/game-code-organization.md -- "the HUD subscribes, never polls game logic into
## itself"). Placeholder styling (solid ColorRect slots + Labels), no art.
##
## Update strategy (why per-frame reads are correct here, not "polling logic"):
##  * Health -- connects to HealthComponent.damaged for the damage EVENT, AND does a light
##    per-frame refresh. revive()/heal() emit NOTHING (design-playable-loop.md D1), so the
##    per-frame read is the ONLY clean way to catch a respawn without growing player.gd.
##  * Tool + durability + hotbar highlight -- the equipped tool, its DurabilityComponent,
##    and inventory.equipped_index have no HUD-facing signal (and player.gd is at its line
##    cap and must NOT grow a new one), so the HUD reads these presentation values each
##    frame. Reading a handful of STATE values per frame is standard for a HUD; it adds no
##    game LOGIC to the UI.

## Highlight tint for the equipped hotbar slot; every other slot uses SLOT_COLOR.
const HIGHLIGHT_COLOR: Color = Color(0.95, 0.85, 0.35, 0.95)
const SLOT_COLOR: Color = Color(0.18, 0.18, 0.22, 0.9)
const SLOT_SIZE: Vector2 = Vector2(34, 34)

var _player: Player = null
var _health: HealthComponent = null
## Built once by bind() from the inventory's hotbar window; parallel arrays so a test (or
## the per-frame refresh) can read a slot's glyph/highlight by index.
var _slot_panels: Array[ColorRect] = []
var _slot_labels: Array[Label] = []

@onready var _health_label: Label = $Backdrop/Column/HealthLabel
@onready var _health_bar: ProgressBar = $Backdrop/Column/HealthBar
@onready var _tool_label: Label = $Backdrop/Column/ToolLabel
@onready var _hotbar: HBoxContainer = $Backdrop/Column/Hotbar


## Point the HUD at the live player: store the ref, subscribe to the health damage EVENT,
## build the hotbar slot widgets, and do an initial full refresh. Called by
## streaming_world.gd _ready once the player exists. Safe to call once per HUD.
func bind(player: Player) -> void:
	_player = player
	_health = player.get_node("HealthComponent") as HealthComponent
	if _health != null and not _health.damaged.is_connected(_on_player_damaged):
		_health.damaged.connect(_on_player_damaged)
	_build_hotbar()
	_refresh()


## Light per-frame refresh so signal-less changes (revive/heal, equip/cycle, wear) show up
## without any new player signal. Guarded: no-ops until bound / if the player was freed.
func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_refresh()


## Damage EVENT hook (HealthComponent.damaged). The per-frame pass also refreshes health,
## but the signal keeps the readout responsive on the exact frame damage lands.
func _on_player_damaged(_amount: int, _current: int) -> void:
	_refresh_health()


func _refresh() -> void:
	_refresh_health()
	_refresh_tool()
	_refresh_hotbar()


func _refresh_health() -> void:
	if _health == null:
		return
	var cur: int = _health.current_health
	var mx: int = _health.max_health
	_health_label.text = "HP %d / %d" % [cur, mx]
	_health_bar.max_value = mx
	_health_bar.value = cur


## Equipped-tool readout: the tool's display_name + its active DurabilityComponent's
## current/max, or "Unarmed" when the equipped slot is empty. Reads inventory.equipped_tool()
## for the name/empty state and the player's private _active_durability for the wear numbers
## (both kept in sync by the player's _apply_equipped() chokepoint; the HUD only reads them).
func _refresh_tool() -> void:
	var tool: ToolData = _player.inventory.equipped_tool()
	if tool == null:
		_tool_label.text = "Unarmed"
		return
	var dura: DurabilityComponent = _player._active_durability
	if dura != null:
		_tool_label.text = "%s  %d / %d" % [tool.display_name, dura.current_durability, dura.max_durability]
	else:
		_tool_label.text = tool.display_name


func _refresh_hotbar() -> void:
	var inv: Inventory = _player.inventory
	var equipped: int = inv.equipped_index
	for i in range(_slot_panels.size()):
		var tool: ToolData = inv.slots[i] if i < inv.slots.size() else null
		_slot_labels[i].text = _slot_glyph(tool)
		_slot_panels[i].color = HIGHLIGHT_COLOR if i == equipped else SLOT_COLOR


## Build one ColorRect + centered Label per hotbar-window slot (hotbar_size()). Placeholder
## styling only. Rebuilds cleanly if called again.
func _build_hotbar() -> void:
	for child in _hotbar.get_children():
		child.queue_free()
	_slot_panels.clear()
	_slot_labels.clear()
	var count: int = _player.inventory.hotbar_size()
	for _i in range(count):
		var panel: ColorRect = ColorRect.new()
		panel.custom_minimum_size = SLOT_SIZE
		panel.color = SLOT_COLOR
		var label: Label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_child(label)
		_hotbar.add_child(panel)
		_slot_panels.append(panel)
		_slot_labels.append(label)


## Short glyph for a slot: the tool's first letter, or "" for an empty slot.
func _slot_glyph(tool: ToolData) -> String:
	if tool == null:
		return ""
	return tool.display_name.substr(0, 1)


# --- Read-only presentation queries (for the headless HUD test) -----------------------

func health_text() -> String:
	return _health_label.text


func tool_text() -> String:
	return _tool_label.text


func hotbar_slot_count() -> int:
	return _slot_panels.size()


func slot_glyph_at(i: int) -> String:
	if i < 0 or i >= _slot_labels.size():
		return ""
	return _slot_labels[i].text


## Index of the (first) slot currently painted with HIGHLIGHT_COLOR, or -1 if none.
func highlighted_slot_index() -> int:
	for i in range(_slot_panels.size()):
		if _slot_panels[i].color == HIGHLIGHT_COLOR:
			return i
	return -1


## How many slots are painted highlighted -- must be exactly 1 in normal operation.
func highlighted_count() -> int:
	var n: int = 0
	for panel in _slot_panels:
		if panel.color == HIGHLIGHT_COLOR:
			n += 1
	return n

# Verified against: Godot 4.7.1 (2026-07-18)
