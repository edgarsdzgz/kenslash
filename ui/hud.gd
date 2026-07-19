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
## Fraction of the (square) slot the fitted icon spans (its longer bbox side), then centered.
const ICON_FIT: float = 0.75
## Item-name selection popup (Minecraft-style): how long the newly-selected item's name is
## held at full opacity, then how long it takes to fade to transparent. Time-based via a Tween
## (never Time/OS wall-clock) so it advances identically headless.
const SELECTION_HOLD: float = 2.0
const SELECTION_FADE: float = 0.4
## Weight readout tints (design-weight.md "HUD"): one per encumbrance TIER, parallel to
## Inventory.Encumbrance -- white under capacity, then yellow -> orange -> red as it worsens.
const WEIGHT_TIER_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0, 1.0),    ## NORMAL -- white (under capacity).
	Color(1.0, 0.85, 0.3, 1.0),   ## OVER   -- yellow.
	Color(1.0, 0.6, 0.2, 1.0),    ## SUPER  -- orange.
	Color(1.0, 0.35, 0.3, 1.0),   ## ULTRA  -- red.
]
## Tier NAME appended to the weight readout when encumbered (parallel to the tier enum); NORMAL is "".
const WEIGHT_TIER_NAMES: Array[String] = ["", "Overencumbered", "Superencumbered", "Ultraencumbered"]
## Icon rotation for WEAPON (tool blade) hotbar icons only -- 45 degrees, so the blade reads as a
## canted weapon rather than lying flat. Applied to the POINTS before the bbox-fit so it still fits.
const TOOL_ICON_ROTATION: float = PI / 4.0

var _player: Player = null
var _health: HealthComponent = null
## Selection-popup change detection: the equipped index + the item identity in that slot as of
## the last refresh. Initialized in bind() to the CURRENT values so the popup does NOT fire on
## the initial bind -- only on a real selection change (index moves, or the equipped slot's item
## changes identity) afterward. _selection_tween holds the active hold->fade->hide animation.
var _last_equipped_index: int = -1
var _last_equipped_item: ItemData = null
var _selection_tween: Tween = null
## Built once by bind() from the inventory's hotbar window; parallel arrays so a test (or
## the per-frame refresh) can read a slot's glyph/highlight by index.
var _slot_panels: Array[ColorRect] = []
var _slot_labels: Array[Label] = []
## Parallel to _slot_labels: a small bottom-right count label per slot, showing a stack's
## count when > 1 (blank for a single item or an empty slot). Kept separate from the glyph
## label so slot_glyph_at() stays the pure glyph (S/A/P/W) the existing tests assert.
var _slot_counts: Array[Label] = []
## Parallel to _slot_labels: a filled Polygon2D per slot drawing the item's ICON silhouette
## (icon_shape, else a tool's blade_shape), fitted + centered. When it shows, the glyph Label is
## blanked; an empty/shapeless slot hides it and falls back to the letter glyph.
var _slot_icons: Array[Polygon2D] = []

@onready var _health_label: Label = $Backdrop/Column/HealthLabel
@onready var _health_bar: ProgressBar = $Backdrop/Column/HealthBar
@onready var _tool_label: Label = $Backdrop/Column/ToolLabel
## Carried-weight readout below the tool label (design-weight.md "HUD"); refreshed each frame.
@onready var _weight_label: Label = $Backdrop/Column/WeightLabel
## The hotbar row lives in its OWN bottom-center anchor (Minecraft-style), separate from the
## top-left health/tool Backdrop. A CenterContainer anchored to the bottom edge keeps it
## horizontally centered and re-centers automatically on window resize -- no manual math.
@onready var _hotbar: HBoxContainer = $HotbarAnchor/HotbarPanel/Hotbar
## Interaction prompt (E4, design-items.md "Interaction 'f'"): shown just above the hotbar when
## the player stands on an interactable (a bush), reading player.interaction_prompt() each frame;
## hidden when nothing is in reach. Presentation only -- the interaction lives in player.gd.
@onready var _prompt_label: Label = $PromptLabel
## Item-name selection popup (Change 2): shown just ABOVE the interaction prompt (a bit higher y
## so the two never overlap), it names the item in the newly-selected hotbar slot, held then
## faded out. Presentation only -- driven entirely by reading inventory.equipped_index/item.
@onready var _selection_label: Label = $SelectionLabel


## Point the HUD at the live player: store the ref, subscribe to the health damage EVENT,
## build the hotbar slot widgets, and do an initial full refresh. Called by
## streaming_world.gd _ready once the player exists. Safe to call once per HUD.
func bind(player: Player) -> void:
	_player = player
	_health = player.get_node("HealthComponent") as HealthComponent
	if _health != null and not _health.damaged.is_connected(_on_player_damaged):
		_health.damaged.connect(_on_player_damaged)
	# Seed the selection-popup trackers to the CURRENT equipped slot/item so the very first
	# refresh sees "no change" -- the popup only fires on genuine selection changes afterward.
	_last_equipped_index = _player.inventory.equipped_index
	_last_equipped_item = _player.inventory.equipped_item()
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
	_refresh_weight()
	_refresh_hotbar()
	_refresh_prompt()
	_refresh_selection()


## Carried-weight readout (design-weight.md "HUD"): "Wt <carried> / <capacity>", and -- when
## encumbered -- the TIER NAME appended (e.g. "Wt 90 / 50  Overencumbered") with a per-tier warning
## tint (white -> yellow -> orange -> red). The tier is owned by the Inventory (encumbrance_tier());
## the HUD only maps int -> name/tint. Presentation only -- state reads, no game logic added.
func _refresh_weight() -> void:
	var inv: Inventory = _player.inventory
	var tier: int = inv.encumbrance_tier()
	var text: String = "Wt %s / %s" % [_fmt_weight(inv.total_weight()), _fmt_weight(inv.carry_capacity)]
	if tier != Inventory.Encumbrance.NORMAL:
		text += "  " + WEIGHT_TIER_NAMES[tier]
	_weight_label.text = text
	_weight_label.modulate = WEIGHT_TIER_COLORS[tier]


## Trim a weight for display: a whole value reads "10" (not str()'s "10.0"), a fractional one keeps
## its decimals ("12.5") -- the design "Wt 12.5 / 50" format. Godot's % has no %g to do this.
func _fmt_weight(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)


## Item-name selection popup (Change 2): when the equipped slot changes -- a new index, OR the
## same index now holding a different item -- pop the newly-selected item's display_name in the
## SelectionLabel (above the prompt), reset it to full opacity, and (re)start a Tween that holds
## for SELECTION_HOLD then fades over SELECTION_FADE and hides. An empty new selection hides the
## label (and kills any running fade). Any prior tween is killed first so rapid selection changes
## restart the hold cleanly. No change since the last refresh -> nothing happens (the fade runs).
func _refresh_selection() -> void:
	var inv: Inventory = _player.inventory
	var idx: int = inv.equipped_index
	var item: ItemData = inv.equipped_item()
	if idx == _last_equipped_index and item == _last_equipped_item:
		return
	_last_equipped_index = idx
	_last_equipped_item = item
	if _selection_tween != null and _selection_tween.is_valid():
		_selection_tween.kill()
		_selection_tween = null
	if item == null:
		_selection_label.visible = false
		return
	_selection_label.text = item.display_name
	_selection_label.modulate.a = 1.0
	_selection_label.visible = true
	_selection_tween = create_tween()
	_selection_tween.tween_interval(SELECTION_HOLD)
	_selection_tween.tween_property(_selection_label, "modulate:a", 0.0, SELECTION_FADE)
	_selection_tween.tween_callback(_hide_selection_label)


## Tween tail: hide the popup once it has fully faded (called by the selection Tween's callback).
func _hide_selection_label() -> void:
	_selection_label.visible = false


## Interaction prompt (E4): if the player has a nearby interactable, show "[<key>] <verb>" just
## above the hotbar, where <key> is whatever key is currently bound to the_action_button (derived
## from the InputMap, so a rebind updates the prompt for free); otherwise hide the label.
func _refresh_prompt() -> void:
	var prompt: String = _player.interaction_prompt()
	if prompt == "":
		_prompt_label.text = ""
		_prompt_label.visible = false
		return
	_prompt_label.text = "[%s] %s" % [_action_key_text(), prompt]
	_prompt_label.visible = true


## Human-readable key currently bound to the_action_button: the first InputEventKey's keycode
## (physical preferred, since the action is authored physical) as a label. "?" if none is bound.
func _action_key_text() -> String:
	for ev in InputMap.action_get_events("the_action_button"):
		if ev is InputEventKey:
			var k: InputEventKey = ev as InputEventKey
			var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
			return OS.get_keycode_string(code)
	return "?"


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
		var item: ItemData = inv.item_at(i)
		var count: int = inv.count_at(i)
		# Prefer the item's icon SILHOUETTE; blank the glyph label when one shows so the two
		# never render on top of each other. No shape -> hide the icon, keep the letter glyph.
		var icon_src: PackedVector2Array = _icon_shape_for(item)
		if not icon_src.is_empty():
			# Rotate 45 degrees for WEAPONS only (icon came from a ToolData's blade_shape); a
			# resource's own icon_shape stays upright.
			_slot_icons[i].polygon = _fit_polygon(icon_src, _icon_is_tool_blade(item))
			_slot_icons[i].color = _icon_color(item)
			_slot_icons[i].visible = true
			_slot_labels[i].text = ""
		else:
			_slot_icons[i].polygon = PackedVector2Array()
			_slot_icons[i].visible = false
			_slot_labels[i].text = _slot_glyph(item)
		# Show the count only for a real stack (> 1); a single item or empty slot is blank.
		_slot_counts[i].text = str(count) if count > 1 else ""
		_slot_panels[i].color = HIGHLIGHT_COLOR if i == equipped else SLOT_COLOR


## Build one ColorRect + centered Label per hotbar-window slot (hotbar_size()). Placeholder
## styling only. Rebuilds cleanly if called again.
func _build_hotbar() -> void:
	for child in _hotbar.get_children():
		child.queue_free()
	_slot_panels.clear()
	_slot_labels.clear()
	_slot_counts.clear()
	_slot_icons.clear()
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
		# The item ICON (a filled silhouette). A Node2D child of the ColorRect renders at the
		# slot's top-left origin, so it is nudged to the slot CENTER (the polygon is pre-fitted
		# around its own origin). Hidden until _refresh_hotbar sets polygon/color/visibility.
		var icon: Polygon2D = Polygon2D.new()
		icon.position = SLOT_SIZE * 0.5
		icon.visible = false
		panel.add_child(icon)
		# A second small label pinned bottom-right for a stack's count (blank unless > 1); added
		# LAST so the count badge draws over the icon. Separate widget from the glyph label.
		var count_label: Label = Label.new()
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_child(count_label)
		_hotbar.add_child(panel)
		_slot_panels.append(panel)
		_slot_labels.append(label)
		_slot_icons.append(icon)
		_slot_counts.append(count_label)


## Short glyph for a slot: "" for an empty slot; the item's explicit glyph when it has one
## (resources pin W/S); otherwise the display_name's first letter (tools -> S/A/P).
func _slot_glyph(item: ItemData) -> String:
	if item == null:
		return ""
	if item.glyph != "":
		return item.glyph
	return item.display_name.substr(0, 1)


## The icon SILHOUETTE to draw for a slot's item, in the item's own local space. Lookup rule:
## the item's own icon_shape if it set one; else, if it is a ToolData, REUSE its blade_shape
## (so the sword/axe/pickaxe hotbar icons come straight from the swing silhouette -- no
## duplicated shape on the tool .tres); else empty -> the caller falls back to the letter glyph.
func _icon_shape_for(item: ItemData) -> PackedVector2Array:
	if item == null:
		return PackedVector2Array()
	if not item.icon_shape.is_empty():
		return item.icon_shape
	if item is ToolData:
		return (item as ToolData).blade_shape
	return PackedVector2Array()


## Fill colour for a slot icon: a tool paints in its blade_color, any other item in its drop `color`.
func _icon_color(item: ItemData) -> Color:
	if item is ToolData:
		return (item as ToolData).blade_color
	return item.color


## Whether the icon drawn for `item` is a WEAPON (tool) BLADE silhouette -- the exact case
## _icon_shape_for falls back to blade_shape: a ToolData that set NO icon_shape of its own. Only
## this case is rotated 45 degrees. Mirrors _icon_shape_for's lookup so the two can't drift.
func _icon_is_tool_blade(item: ItemData) -> bool:
	return item is ToolData and item.icon_shape.is_empty()


## Normalize an icon outline to fit the slot: optionally ROTATE it 45 degrees first (weapons only),
## then measure its bounding box, uniformly scale so the LONGER side spans ICON_FIT * SLOT_SIZE, and
## recenter the box on the origin (the Polygon2D sits at the slot centre). Rotating BEFORE the fit
## keeps a canted blade inside the slot -- a naive Polygon2D.rotation AFTER the fit would swing the
## corners past the slot edges. Pivot is irrelevant (the bbox recenter cancels it), so we spin about
## the origin. Point COUNT is preserved. A degenerate (zero-area) shape is returned unchanged.
func _fit_polygon(shape: PackedVector2Array, rotate: bool = false) -> PackedVector2Array:
	# Rotate the raw points (weapons only) BEFORE measuring, so the fit boxes the ROTATED
	# silhouette. Point count is unchanged; each point is just moved.
	var src: PackedVector2Array = shape
	if rotate:
		src = PackedVector2Array()
		for p in shape:
			src.append(p.rotated(TOOL_ICON_ROTATION))
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for p in src:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	var span: float = maxf(max_x - min_x, max_y - min_y)
	if span <= 0.0:
		return shape
	var scale: float = (SLOT_SIZE.x * ICON_FIT) / span
	var center: Vector2 = Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	var out: PackedVector2Array = PackedVector2Array()
	for p in src:
		out.append((p - center) * scale)
	return out


# --- Read-only presentation queries (for the headless HUD test) -----------------------

func health_text() -> String:
	return _health_label.text


## The interaction prompt currently SHOWN (e.g. "[F] Harvest"), or "" when the label is hidden.
## Reads the rendered text so a test sees exactly what a player would (E4).
func prompt_text() -> String:
	return _prompt_label.text if _prompt_label.visible else ""


func tool_text() -> String:
	return _tool_label.text


## The carried-weight readout currently SHOWN (e.g. "Wt 12.5 / 50"), for the headless HUD test.
func weight_text() -> String:
	return _weight_label.text


## Whether the weight readout is in ANY over-capacity warning state (tier past NORMAL) -- for the
## headless HUD test. True once the player is Over/Super/Ultra-encumbered (not the normal white).
func weight_over() -> bool:
	return _weight_label.modulate != WEIGHT_TIER_COLORS[Inventory.Encumbrance.NORMAL]


## The current encumbrance TIER shown by the readout (Inventory.Encumbrance, 0..3), forwarded from
## the live inventory so the HUD test can assert the tier without parsing the string.
func weight_tier() -> int:
	return _player.inventory.encumbrance_tier()


## The item-name selection popup currently SHOWN, or "" once it has faded/hidden. Reads the
## rendered text only while the label is visible AND still opaque (alpha > 0), so a test sees
## exactly what a player would across the hold->fade->hide lifecycle.
func selection_text() -> String:
	if _selection_label.visible and _selection_label.modulate.a > 0.0:
		return _selection_label.text
	return ""


func hotbar_slot_count() -> int:
	return _slot_panels.size()


func slot_glyph_at(i: int) -> String:
	if i < 0 or i >= _slot_labels.size():
		return ""
	return _slot_labels[i].text


## Vertex count of the icon polygon SHOWN in slot `i` (0 when no icon: empty/shapeless/range). The
## fit transform preserves point count, so a test matches it against icon_shape / blade_shape size.
func slot_icon_point_count(i: int) -> int:
	if i < 0 or i >= _slot_icons.size():
		return 0
	if not _slot_icons[i].visible:
		return 0
	return _slot_icons[i].polygon.size()


## Whether slot `i` is currently drawing an item icon (false for an empty/shapeless slot or out
## of range).
func slot_icon_visible(i: int) -> bool:
	if i < 0 or i >= _slot_icons.size():
		return false
	return _slot_icons[i].visible


## Fill colour of slot `i`'s icon polygon -- a tool's blade_color, a resource's own color. Lets
## the HUD test prove the tool-vs-resource tint branch. Transparent black when out of range.
func slot_icon_color(i: int) -> Color:
	if i < 0 or i >= _slot_icons.size():
		return Color(0, 0, 0, 0)
	return _slot_icons[i].color


## The count currently SHOWN in slot `i`'s count label (0 when blank -- a single item or an
## empty slot -- or out of range). Reads the rendered text so it mirrors exactly what a
## player sees, not the raw inventory count.
func slot_count_at(i: int) -> int:
	if i < 0 or i >= _slot_counts.size():
		return 0
	var text: String = _slot_counts[i].text
	return int(text) if text != "" else 0


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

# Verified against: Godot 4.7.1 (2026-07-19)
