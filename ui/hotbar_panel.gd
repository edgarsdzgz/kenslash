class_name HotbarPanel
extends HBoxContainer
## The hotbar sub-system of the HUD (design-inventory.md), extracted from ui/hud.gd to keep both
## files under the line cap (CONVENTIONS.md Rule 1). PRESENTATION ONLY: it READS the live
## inventory's hotbar window each frame and renders one placeholder slot widget per position --
## a ColorRect background, a centered glyph Label, a fitted item-ICON Polygon2D, and a small
## bottom-right stack-count Label -- plus the Minecraft-style item-name SELECTION popup that fires
## when the equipped slot changes. Owns NO game state, mutates nothing.
##
## This IS the Hotbar HBoxContainer node in hud.tscn (the script is attached to it), so the slot
## widgets are built as its own children. The parent Hud binds the player + the shared SelectionLabel
## into this panel and delegates build/refresh to it, then FORWARDS the headless test queries here so
## the HUD test is unchanged. A scene node with a script (not a RefCounted) because it owns real
## Control children and the selection Tween -- the HUD is not in the streaming node-count baseline, so
## the extra node is free (unlike the RefCounted subsystems on the player).

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
## Icon rotation for WEAPON (tool blade) hotbar icons only -- 45 degrees COUNTERclockwise, so the
## blade cants up toward the top-right (screen +y is down, so a negative angle rotates CCW).
## Applied to the POINTS before the bbox-fit so it still fits.
const TOOL_ICON_ROTATION: float = -PI / 4.0

var _player: Player = null
## The shared SelectionLabel node (a sibling in the HUD tree, passed in by bind()) that this
## panel drives for the item-name popup; the popup logic lives here since it fires on hotbar
## selection changes, but the label itself must stay above the interaction prompt in the HUD.
var _selection_label: Label = null
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


## Point the panel at the live player + the shared SelectionLabel, seed the selection-popup
## trackers to the CURRENT equipped slot/item (so the popup only fires on genuine changes
## afterward), and build the slot widgets. Called by Hud.bind().
func bind(player: Player, selection_label: Label) -> void:
	_player = player
	_selection_label = selection_label
	_last_equipped_index = _player.inventory.equipped_index
	_last_equipped_item = _player.inventory.equipped_item()
	_build_hotbar()


## Per-frame refresh delegated from the HUD: repaint the slots from the inventory, then run the
## selection-popup change detection. Guarded by the HUD's own bound/valid check upstream.
func refresh() -> void:
	_refresh_hotbar()
	_refresh_selection()


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
	for child in get_children():
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
		add_child(panel)
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


# --- Read-only presentation queries (forwarded from the Hud for the headless HUD test) --------

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
