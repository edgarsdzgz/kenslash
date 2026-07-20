class_name CraftMenu
extends Control
## The MINIMAL craft menu (plan-epic1-parts.md Part 4.2; plan-core-loop.md Phase 4; design-crafting.md
## "Track B"). The "prove the loop is operable" UI slice: a Control panel that LISTS the player's KNOWN
## recipes, marks each craftable-or-not, tracks a selection, and RUNS a craft through components/crafting.gd --
## chrome-minimal by design (a VBox of text rows, no art). Part 5+ can dress it; this part only proves a player
## can stand at a station, see what they can make, and make it.
##
## PRESENTATION + THIN DRIVER, owns NO game state. It reads a CharacterSheet (its KnownRecipes) + an Inventory
## and the in-range station tags handed to open(); it never caches recipe knowledge or materials. The craftable
## FLAG and the craft EXECUTION both defer to Crafting (has_materials_for / needs_station / craft), the SAME
## chokepoint the headless craft tests exercise -- so the menu adds no new craft rules, it only surfaces + calls
## the existing ones. The HUD hosts + opens this (streaming_world.tscn -> HUD); the player never reaches into it
## beyond the interaction seam that requests the open (ui/hud.gd polls player._interaction, mirroring how the
## HUD polls every other player-owned state -- "HUD reads player, player never reaches into HUD").
##
## DETERMINISM: open()/craft() are pure membership + integer work over the passed sheet/inventory/tags (Crafting
## does the atomic consume/produce); no Time/OS/RNG in the craft path (NOTES.md rule), so every listing + craft
## is exactly headless-assertable. Visibility toggling is presentation-only. A RefCounted Crafting instance is
## reused across crafts (it is stateless), so this adds no per-craft allocation churn and no node to the streaming
## baselines beyond this one UI subtree on the HUD/CanvasLayer (never the streamed chunk path).

## The craft executor (components/crafting.gd) -- stateless, so ONE instance serves every craft this menu runs.
var _crafting: Crafting = Crafting.new()

## The character whose KNOWN recipes are listed (its KnownRecipes), set by open(). Read-only use -- the menu
## never mutates the sheet; a craft only touches the inventory (through Crafting).
var _sheet: CharacterSheet = null
## The inventory a craft pulls inputs from + drops output into (Epic 1: inventory-only; the storage seam lives in
## crafting.gd, inert here). Set by open().
var _inventory: Inventory = null
## The station tags currently in range of the player (Station.tags_in_range), routed in by open() so a station-
## gated recipe is craftable ONLY when its tag is present. A COPY is held so a later world change cannot mutate
## the menu's view mid-session.
var _tags: Array[StringName] = []
## The listed recipe ids, in KnownRecipes' insertion order (deterministic) -- the logical list the query methods
## read, independent of the presentation row lifecycle.
var _ids: Array[StringName] = []
## The selected row index into _ids, or -1 when the list is empty. craft_selected() runs this row.
var _selected: int = -1
## Whether the menu is currently OPEN (shown + populated). Toggled by open()/close(); the HUD reads it to decide
## open-vs-close on an 'f' request, and the headless test asserts it directly.
var is_open: bool = false

## The row container -- one Label per listed recipe is (re)built here on open()/refresh. Presentation only; the
## query methods never read these labels (they recompute off _ids + Crafting), so the row lifecycle can never
## desync the asserted state.
@onready var _list: VBoxContainer = $Panel/Column/List


## OPEN the menu against a live sheet/inventory + the station tags in range (the interaction seam hands these in).
## Stores the refs, marks open + visible, and (re)builds the listing of the player's KNOWN recipes with each
## recipe's live craftable flag. Idempotent -- re-opening just refreshes against the current state.
func open(sheet: CharacterSheet, inventory: Inventory, in_range_tags: Array[StringName]) -> void:
	_sheet = sheet
	_inventory = inventory
	_tags = in_range_tags.duplicate()
	is_open = true
	visible = true
	_rebuild()


## CLOSE the menu -- hide it and drop the open flag. The refs are LEFT in place (harmless; a re-open overwrites
## them) so a test can still read the last listing if it wants; a fresh open() re-binds everything.
func close() -> void:
	is_open = false
	visible = false


## Manual dismiss: Escape (the "ui_cancel" action) closes the menu -- but ONLY while it is open. Guarded so a
## closed menu swallows NOTHING (the early return leaves the event for the rest of the game), and the handled
## flag is set only when we actually consume the Escape to close. Minimal: no per-frame input polling, just this
## single-event hook. The HUD still owns the 'f' open/toggle; this is only the standalone Escape-to-close.
func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Craft the SELECTED recipe (craft_selected) -- the row a player would confirm. No selection (empty list) -> a
## refused no-op returning false. Delegates to craft(id).
func craft_selected() -> bool:
	if _selected < 0 or _selected >= _ids.size():
		return false
	return craft(_ids[_selected])


## Run ONE craft of `id` through Crafting (learn gate + station gate + atomic consume/produce), then REFRESH the
## listing so the craftable flags reflect the post-craft inventory (a now-unaffordable recipe greys out, a newly
## affordable one lights up). Returns Crafting's success -- true IFF inputs were consumed + output produced.
## Refreshing only on success is enough (a failed craft changed nothing), but refresh is cheap + idempotent so it
## runs whenever the craft returns true.
func craft(id: StringName) -> bool:
	if _sheet == null or _inventory == null:
		return false
	var ok: bool = _crafting.craft(id, _sheet, _inventory, _tags)
	if ok:
		_rebuild()
	return ok


## Move the selection to the row for `id` (a click/keyboard pick). A no-op if `id` is not listed.
func select(id: StringName) -> void:
	var i: int = _ids.find(id)
	if i != -1:
		_selected = i


## The currently-selected recipe id, or &"" when nothing is selected (empty list).
func selected_id() -> StringName:
	return _ids[_selected] if _selected >= 0 and _selected < _ids.size() else &""


## The listed recipe ids (the player's KNOWN set, insertion order) -- a COPY, safe for a caller/test to iterate.
func listed_ids() -> Array[StringName]:
	return _ids.duplicate()


## Whether `id` can be crafted RIGHT NOW from the open state -- delegated WHOLESALE to Crafting.would_craft, the
## transactional dry-run of craft() (known + materials + station + the output FITS), so the "craftable" flag
## EXACTLY matches craft() acceptance. It is a NET NO-OP on the inventory (would_craft snapshots -> tests ->
## restores), never commits, and judges against the CURRENT _tags (kept live by set_tags). This replaces the old
## ad-hoc full-CATALOG lookup that could show craftable for an UNLEARNED id or when a full inventory would make
## craft() refuse the output; the flag can no longer lie. Exposed so a test asserts it without parsing a label.
func is_craftable(id: StringName) -> bool:
	return _crafting.would_craft(id, _sheet, _inventory, _tags)


## Update the in-range station tags to `in_range_tags` (a COPY) and repaint, so is_craftable + craft judge against
## the station presence RIGHT NOW, not the snapshot open() captured. The HUD calls this each frame while the menu
## is open (Station.tags_in_range re-scanned live) so walking up to / away from a station re-evaluates the gate --
## the stale-snapshot bypass (craft a forge recipe with no forge present) can never happen. Presentation-safe: the
## rows recompute their craftable/blocked flags off the fresh tags.
func set_tags(in_range_tags: Array[StringName]) -> void:
	_tags = in_range_tags.duplicate()
	_repaint_rows()


## How many recipes are listed (== the known count). Reads _ids, not the row children, so it is exact regardless
## of the (deferred) row free timing.
func row_count() -> int:
	return _ids.size()


## Re-derive the listed ids from the sheet's KnownRecipes, clamp the selection into range, and repaint the rows.
## The one place the listing is (re)built -- open() and a successful craft() both call it.
func _rebuild() -> void:
	_ids.clear()
	if _sheet != null and _sheet.known_recipes != null:
		for id: StringName in _sheet.known_recipes.known_ids():
			_ids.append(id)
	# Keep the selection valid: clamp a past-the-end index, and default to the first row when nothing is picked.
	if _selected >= _ids.size():
		_selected = _ids.size() - 1
	if _selected < 0 and not _ids.is_empty():
		_selected = 0
	_repaint_rows()


## Rebuild the presentation rows (one Label per listed recipe: a selection marker, the display name, and a
## craftable/blocked tag). Purely cosmetic -- clears the old rows and makes fresh ones. Guarded so it is a no-op
## before _ready wires the container (a test that only reads the query methods never needs the rows).
func _repaint_rows() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	for i in range(_ids.size()):
		var id: StringName = _ids[i]
		var r: RecipeData = _sheet.known_recipes.recipe(id)
		var name: String = r.display_name if r != null else String(id)
		var mark: String = "> " if i == _selected else "  "
		var state: String = "craftable" if is_craftable(id) else "blocked"
		var row: Label = Label.new()
		row.text = "%s%s  [%s]" % [mark, name, state]
		_list.add_child(row)

# Verified against: Godot 4.7.1 (2026-07-19)
