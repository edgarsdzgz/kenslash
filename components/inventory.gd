class_name Inventory
extends RefCounted
## Slot-based inventory + hotbar selection model (design-inventory.md). ONE array;
## the "hotbar" is a WINDOW onto that same array (the leading hotbar_size() slots),
## not a separate structure. Pure logic, no scene/node dependency -- directly
## testable via `Inventory.new()` with no player/scene required.
##
## Key ring: keys 1-9,0 map to slots 0-8,9 (a fixed 10-position ring, see
## design-inventory.md). hotbar_size() clamps that ring to however many slots
## actually exist. Locked (default): scroll/Q/E wrap only within
## [0, hotbar_size()). Unlocked: wrap within the full [0, slots.size()). Number
## keys are UNCHANGED in both modes -- always a direct jump to their mapped index.
##
## Runtime state only (equipped_index, hotbar_unlocked, which ToolData sits in each
## slot) lives here, never on the shared ToolData resources themselves -- the
## sharing trap, patterns/resource-driven-design.md.

## Slot contents: null = empty, or a ToolData. Default size 6 (today's starting
## inventory). A test (or future growth code) can `slots.resize(n)` directly to
## build a bigger inventory -- Array.resize() null-fills new typed-Object slots.
var slots: Array[ToolData] = [null, null, null, null, null, null]
## The slot index the Sword Hitbox currently reflects. Default 0 (key '1').
var equipped_index: int = 0
## False (default) = locked: scroll/Q/E wrap within the hotbar window only.
## True = unlocked: scroll/Q/E wrap across the WHOLE inventory. Never affects
## number-key direct jumps (equip_index), which are always unrestricted by lock.
var hotbar_unlocked: bool = false


## Leading N slots that are live hotbar slots, capped at the 10-key ring.
func hotbar_size() -> int:
	return mini(slots.size(), 10)


## Jump directly to slot `i`, UNCONDITIONALLY -- regardless of lock state, and even
## if that slot is empty (equipping "nothing" is valid; it drives the unarmed
## fallback). Out-of-range `i` is clamped into [0, slots.size()).
func equip_index(i: int) -> void:
	equipped_index = clampi(i, 0, slots.size() - 1)


## Step `equipped_index` by `delta` (+1 or -1), wrapping within the CURRENT ring:
## the hotbar window when locked, the whole inventory when unlocked. Defensive
## modulo -- GDScript's `%` on a negative int does not wrap like Python's, so wrap
## by hand via ((i % n) + n) % n.
func cycle(delta: int) -> void:
	var n: int = slots.size() if hotbar_unlocked else hotbar_size()
	if n <= 0:
		return
	equipped_index = ((equipped_index + delta) % n + n) % n


## The currently-equipped ToolData, or null if the slot is empty/out of range
## (drives the Player's unarmed fallback).
func equipped_tool() -> ToolData:
	if equipped_index < 0 or equipped_index >= slots.size():
		return null
	return slots[equipped_index]


## Auto-populate: place `tool` in the first EMPTY slot. Tool-priority ordering
## (sword, axe, pickaxe, ...) is the CALLER's responsibility -- add in that order
## at startup; this method itself just fills first-empty. Returns false if no
## empty slot remains (inventory full).
func add_tool(tool: ToolData) -> bool:
	for i in range(slots.size()):
		if slots[i] == null:
			slots[i] = tool
			return true
	return false


## DEFERRED this slice, per the user ("if we hit 'sort' we will develop that
## later"). Future behavior: tools fill the hotbar first, non-tools push to the
## back/background of inventory (beyond the hotbar window). Intentionally a no-op
## for now -- no non-tool items exist yet to sort.
func sort() -> void:
	pass

# Verified against: Godot 4.7.1 (2026-07-17)
