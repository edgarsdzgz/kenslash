class_name Inventory
extends RefCounted
## Slot-based inventory + hotbar selection model (design-inventory.md). ONE array;
## the "hotbar" is a WINDOW onto that same array (the leading hotbar_size() slots),
## not a separate structure. Pure logic, no scene/node dependency -- directly
## testable via `Inventory.new()` with no player/scene required.
##
## Each slot holds an ItemStack (item + count) or null=empty (E1b, design-items.md).
## A stack's item can be ANY ItemData -- a ToolData (non-stackable, max_stack 1) or a
## resource (Wood/Stone, max_stack 64). add_item() merges into matching stacks up to
## max_stack, then spills into empty slots, returning any overflow. Only a ToolData in
## the EQUIPPED slot arms the blade; a resource stack (or empty slot) -> unarmed.
##
## Key ring: keys 1-9,0 map to slots 0-8,9 (a fixed 10-position ring, see
## design-inventory.md). hotbar_size() clamps that ring to however many slots
## actually exist. Locked (default): scroll/Q/E wrap only within
## [0, hotbar_size()). Unlocked: wrap within the full [0, slots.size()). Number
## keys are UNCHANGED in both modes -- always a direct jump to their mapped index.
##
## Runtime state only (equipped_index, hotbar_unlocked, the ItemStacks in each slot)
## lives here, never on the shared ItemData/ToolData resources themselves -- the
## sharing trap, patterns/resource-driven-design.md.

## Slot contents: null = empty, or an ItemStack. Default size 6 (today's starting
## inventory). A test (or future growth code) can `slots.resize(n)` directly to
## build a bigger inventory -- Array.resize() null-fills new typed-Object slots
## (a typed Array[ItemStack] still permits null elements).
var slots: Array[ItemStack] = [null, null, null, null, null, null]
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


## The ItemData in slot `i`, or null if `i` is out of range or the slot is empty.
func item_at(i: int) -> ItemData:
	if i < 0 or i >= slots.size():
		return null
	var stack: ItemStack = slots[i]
	return stack.item if stack != null else null


## How many items sit in slot `i` (0 if out of range or empty).
func count_at(i: int) -> int:
	if i < 0 or i >= slots.size():
		return 0
	var stack: ItemStack = slots[i]
	return stack.count if stack != null else 0


## The ItemData in the currently-equipped slot (any item kind, or null if empty).
func equipped_item() -> ItemData:
	return item_at(equipped_index)


## The currently-equipped ToolData, or null when the equipped slot is empty, out of
## range, OR holds a non-tool resource stack (down-cast yields null -> the Player's
## unarmed fallback). Kept so equipment.gd reads the equipped WEAPON unchanged.
func equipped_tool() -> ToolData:
	return equipped_item() as ToolData


## Add `count` of `item` (design-items.md): first top up EXISTING matching stacks to
## max_stack, then fill EMPTY slots with new stacks (each capped at max_stack). Returns
## the overflow that did not fit (0 = fully placed). Non-stackable items (max_stack 1,
## all tools) never merge -- each takes its own slot. A null item or count<=0 places
## nothing and returns the count unchanged (0 for count<=0).
func add_item(item: ItemData, count: int = 1) -> int:
	if item == null or count <= 0:
		return maxi(count, 0)
	var remaining: int = count
	var cap: int = maxi(item.max_stack, 1)
	# Pass 1 -- merge into existing matching stacks with room.
	for i in range(slots.size()):
		if remaining <= 0:
			break
		var stack: ItemStack = slots[i]
		if stack != null and stack.item == item and stack.count < cap:
			var room: int = cap - stack.count
			var moved: int = mini(room, remaining)
			stack.count += moved
			remaining -= moved
	# Pass 2 -- fill empty slots with new stacks.
	for i in range(slots.size()):
		if remaining <= 0:
			break
		if slots[i] == null:
			var placed: int = mini(cap, remaining)
			slots[i] = ItemStack.new(item, placed)
			remaining -= placed
	return remaining


## Auto-populate a single tool into the first EMPTY slot. Tool-priority ordering
## (sword, axe, pickaxe, ...) is the CALLER's responsibility -- add in that order at
## startup. Thin convenience over add_item (tools are max_stack 1 -> one slot each).
## Returns false if no empty slot remained (inventory full).
func add_tool(tool: ToolData) -> bool:
	return add_item(tool, 1) == 0


## DEFERRED this slice, per the user ("if we hit 'sort' we will develop that
## later"). Future behavior: tools fill the hotbar first, non-tools push to the
## back/background of inventory (beyond the hotbar window). Intentionally a no-op
## for now.
func sort() -> void:
	pass

# Verified against: Godot 4.7.1 (2026-07-18)
