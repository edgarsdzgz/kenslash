class_name ContainerPanel
extends Control
## The MINIMAL storage-container TRANSFER UI (plan-epic2-parts.md Phase 2 Part 2.3; design-crafting.md "Track B --
## Building"). The direct sibling of ui/craft_menu.gd: a Control panel that, when the player presses 'f' beside a
## placed StorageContainer, LISTS the container's stored contents alongside the player's own inventory and lets
## them deposit/withdraw items THROUGH it. Chrome-minimal by design (two VBoxes of text rows, no art) -- this part
## only proves a player can stand at a chest, see both stores, and move items either way.
##
## PRESENTATION + THIN DRIVER, owns NO game state. It reads a bound StorageContainer's `store` + the player's
## Inventory (both handed in by open()); it never caches item knowledge. The deposit/withdraw EXECUTION defers
## WHOLESALE to StorageContainer.deposit/withdraw (the SAME atomic no-dupe/no-loss transfer the headless container
## tests exercise) -- so the panel adds no new transfer rules, it only surfaces + calls the existing ones and then
## REFRESHES its rows. The HUD hosts + manages it (streaming_world.tscn -> HUD, alongside CraftMenu); the player
## never reaches into it beyond the interaction seam that requests the open (ui/hud.gd polls the player's
## interaction, mirroring "HUD reads player, player never reaches into HUD").
##
## DETERMINISM: open()/deposit()/withdraw() are pure integer/membership work over the bound store + inventory
## (StorageContainer._transfer does the atomic commit); no Time/OS/RNG (NOTES.md rule), so every listing + move is
## exactly headless-assertable. Visibility toggling is presentation-only. It adds no node to the streaming
## baselines beyond this one UI subtree on the HUD/CanvasLayer (never the streamed chunk path).

## The container whose `store` this panel is bound to (its contents are listed + the deposit/withdraw target),
## set by open(). Read-only use -- the panel never mutates the container beyond the deposit/withdraw calls; the
## HUD reads it back via bound_container() to judge live proximity for the auto-close.
var _container: StorageContainer = null
## The player inventory a withdraw drops into + a deposit pulls from, set by open(). The OTHER side of every
## transfer -- StorageContainer.deposit/withdraw take it as the from/to inventory.
var _inventory: Inventory = null
## Whether the panel is currently OPEN (shown + populated). Toggled by open()/close(); the HUD reads it to decide
## open-vs-close on an 'f' request + to drive the walk-away auto-close, and the headless test asserts it directly.
var is_open: bool = false

## The row containers -- one Label per DISTINCT item is (re)built here on open()/refresh. Presentation only; the
## query methods never read these labels (they recompute off the live store/inventory), so the row lifecycle can
## never desync the asserted state. Two lists: the container's contents and the player's inventory, side by side.
@onready var _container_list: VBoxContainer = $Panel/Column/ContainerList
@onready var _inventory_list: VBoxContainer = $Panel/Column/InventoryList


## OPEN the panel against a live container + the player's inventory (the interaction seam hands these in). Stores
## the refs, marks open + visible, and (re)builds both listings (the container's stored stacks + the player's
## inventory). Idempotent -- re-opening against a container just rebinds + refreshes.
func open(container: StorageContainer, player_inventory: Inventory) -> void:
	_container = container
	_inventory = player_inventory
	is_open = true
	visible = true
	_rebuild()


## CLOSE the panel -- hide it and drop the open flag. The refs are LEFT in place (harmless; a re-open overwrites
## them) so a test can still read the last binding if it wants; a fresh open() re-binds everything.
func close() -> void:
	is_open = false
	visible = false


## Manual dismiss: Escape (the "ui_cancel" action) closes the panel -- but ONLY while it is open. Guarded so a
## closed panel swallows NOTHING (the early return leaves the event for the rest of the game), and the handled
## flag is set only when we actually consume the Escape to close. Minimal: no per-frame input polling, just this
## single-event hook -- the exact same shape ui/craft_menu.gd uses. The HUD still owns the 'f' open/toggle; this
## is only the standalone Escape-to-close.
func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## DEPOSIT exactly `n` of `item` from the player inventory INTO the bound container, THROUGH the panel: route to
## StorageContainer.deposit (the atomic all-or-nothing move) and, if anything moved, REFRESH both listings so the
## rows reflect the post-transfer stores. Returns what deposit() returned (`n` on success, 0 on any shortfall/full
## destination). A no-op returning 0 if the panel is not bound (open() never ran).
func deposit(item: ItemData, n: int) -> int:
	if _container == null or _inventory == null:
		return 0
	var moved: int = _container.deposit(item, n, _inventory)
	if moved > 0:
		_rebuild()
	return moved


## WITHDRAW exactly `n` of `item` from the bound container INTO the player inventory, THROUGH the panel: the mirror
## of deposit(). Route to StorageContainer.withdraw (same atomic guarantee, opposite direction) and REFRESH on any
## move. Returns withdraw()'s result (`n` on success, 0 on any shortfall/full destination).
func withdraw(item: ItemData, n: int) -> int:
	if _container == null or _inventory == null:
		return 0
	var moved: int = _container.withdraw(item, n, _inventory)
	if moved > 0:
		_rebuild()
	return moved


## The container this panel is currently bound to (or null before the first open()). The HUD reads it each frame to
## judge whether the bound container is still within reach -- walking it out of range AUTO-CLOSES the panel so a
## transfer never runs against a container the player left. Read-only handle.
func bound_container() -> StorageContainer:
	return _container


## The DISTINCT items currently held in the bound container's store, in slot order (a COPY, safe to iterate) -- the
## logical listing the container side shows. Empty when nothing is bound/stored. For the headless test to assert
## the panel surfaced the container's contents without parsing a label.
func container_ids() -> Array[ItemData]:
	return _distinct_items(_container.store) if _container != null else ([] as Array[ItemData])


## The DISTINCT items currently in the bound player inventory, in slot order (a COPY) -- the inventory side's
## logical listing. Empty when nothing is bound. The mirror of container_ids() for the player's own store.
func inventory_ids() -> Array[ItemData]:
	return _distinct_items(_inventory) if _inventory != null else ([] as Array[ItemData])


## The distinct ItemData held across an inventory's slots, in first-seen slot order (never a duplicate). The shared
## helper both listing sides + the row repaint read, so the query methods and the rows can never disagree. A null
## inventory yields an empty list.
func _distinct_items(inv: Inventory) -> Array[ItemData]:
	var out: Array[ItemData] = []
	if inv == null:
		return out
	for i in range(inv.slots.size()):
		var it: ItemData = inv.item_at(i)
		if it != null and not out.has(it):
			out.append(it)
	return out


## Repaint BOTH listings (the container's store + the player's inventory). The one place the rows are (re)built --
## open() and a successful deposit()/withdraw() both call it.
func _rebuild() -> void:
	_repaint_rows(_container_list, _container.store if _container != null else null)
	_repaint_rows(_inventory_list, _inventory)


## Rebuild ONE list's presentation rows (one Label per distinct item: its display name + total count). Purely
## cosmetic -- clears the old rows and makes fresh ones. Guarded so it is a no-op before _ready wires the
## containers (a test that only reads the query methods never needs the rows) or when `inv` is null (nothing bound).
func _repaint_rows(list: VBoxContainer, inv: Inventory) -> void:
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()
	if inv == null:
		return
	for it: ItemData in _distinct_items(inv):
		var row: Label = Label.new()
		row.text = "%s x%d" % [it.display_name, inv.count_of(it)]
		list.add_child(row)

# Verified against: Godot 4.7.1 (2026-07-20)
