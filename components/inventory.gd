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

## Slot contents: null = empty, or an ItemStack. Default size 15 (today's starting
## inventory): the leading hotbar_size() == 10 are the number-key hotbar window, and
## indices 10-14 are background storage reached via the unlock/scroll. A test (or future
## growth code) can `slots.resize(n)` directly to build a bigger inventory --
## Array.resize() null-fills new typed-Object slots (a typed Array[ItemStack] still
## permits null elements).
var slots: Array[ItemStack] = [null, null, null, null, null, null, null, null, null, null, null, null, null, null, null]
## The slot index the Sword Hitbox currently reflects. Default 0 (key '1').
var equipped_index: int = 0
## False (default) = locked: scroll/Q/E wrap within the hotbar window only.
## True = unlocked: scroll/Q/E wrap across the WHOLE inventory. Never affects
## number-key direct jumps (equip_index), which are always unrestricted by lock.
var hotbar_unlocked: bool = false
## Carry-capacity stat in GRAMS (design-weight.md REVISION 1, DECIDED default 50000 g = 50 kg):
## the carried weight at/under which the player moves at full speed. Over it, encumbrance_factor()
## slows movement (never blocks pickup). Weights are stored in grams, so this is grams too and
## weight_ratio() stays a pure grams/grams ratio (the tiers are unchanged). Lives on the Inventory
## so the whole weight model travels with the item data (the player reads it via its `inventory`
## facade); tunable per save/difficulty later.
var carry_capacity: float = 50000.0

## Encumbrance TIERS (design-weight.md "Over-capacity behavior", GENTLE scheme). Instead of a
## continuous linear slow-down, the carried/capacity ratio falls into one of four DISCRETE bands,
## each imposing a flat speed multiplier. Discrete tiers read clearly on the HUD (a named state)
## and are trivial to persist as a small int. Values are APPEND-ONLY and persistable-safe: NORMAL
## is 0 and the tiers only ever grow heavier, so a saved tier int never shifts meaning.
##   NORMAL (0) -- at or under capacity, full speed.
##   OVER   (1) -- Overencumbered: 1x-2x capacity.
##   SUPER  (2) -- Superencumbered: 2x-3x capacity.
##   ULTRA  (3) -- Ultraencumbered: beyond 3x capacity (a crawl, but still moving).
enum Encumbrance { NORMAL, OVER, SUPER, ULTRA }

## Tier boundary ratios (carried / carry_capacity). Each threshold is the UPPER edge of a tier and
## is INCLUSIVE of the lighter tier: ratio == 1.0 is still NORMAL, == 2.0 still OVER, == 3.0 still
## SUPER. So a band is (lower, upper]; only strictly exceeding a threshold drops to the next tier.
const OVER_THRESHOLD: float = 1.0   ## ratio <= this -> NORMAL (full speed).
const SUPER_THRESHOLD: float = 2.0  ## OVER spans (1.0, 2.0]; above 2.0 -> SUPER.
const ULTRA_THRESHOLD: float = 3.0  ## SUPER spans (2.0, 3.0]; above 3.0 -> ULTRA.

## Flat walk-speed multiplier per tier (GENTLE cutoffs). NORMAL is full speed; ULTRA is a floored
## crawl -- slowed hard but NEVER 0, so an overloaded player can always still stagger to a drop.
const NORMAL_SPEED: float = 1.0   ## NORMAL: full speed.
const OVER_SPEED: float = 0.75    ## OVER:  three-quarter speed.
const SUPER_SPEED: float = 0.50   ## SUPER: half speed.
const ULTRA_SPEED: float = 0.25   ## ULTRA: quarter speed (a crawl, still moving).


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


## Total carried weight (design-weight.md "Carried weight"): the sum over ALL slots -- the
## hotbar window AND the background slots -- of `item.weight * count`. Weight is about what you
## HAUL, not what is equipped, so every stack counts. Empty slots contribute nothing (guarded).
func total_weight() -> float:
	var sum: float = 0.0
	for i in range(slots.size()):
		var item: ItemData = item_at(i)
		if item != null:
			sum += item.weight * count_at(i)
	return sum


## Carried weight as a FRACTION of carry_capacity (design-weight.md): 1.0 == exactly at capacity,
## > 1.0 == over (encumbered). Guards a non-positive capacity by returning 0.0 (no div-by-zero,
## and "no capacity set" reads as unencumbered rather than infinitely over).
func weight_ratio() -> float:
	if carry_capacity <= 0.0:
		return 0.0
	return total_weight() / carry_capacity


## The current encumbrance TIER (Encumbrance enum, 0..3) from the carried/capacity ratio. Bands
## are (lower, upper] -- a threshold ratio belongs to the LIGHTER tier (ratio 1.0 -> NORMAL, 2.0 ->
## OVER, 3.0 -> SUPER). Pure classification; encumbrance_factor() maps this to a speed multiplier.
func encumbrance_tier() -> int:
	var ratio: float = weight_ratio()
	if ratio <= OVER_THRESHOLD:
		return Encumbrance.NORMAL
	if ratio <= SUPER_THRESHOLD:
		return Encumbrance.OVER
	if ratio <= ULTRA_THRESHOLD:
		return Encumbrance.SUPER
	return Encumbrance.ULTRA


## Movement speed multiplier from encumbrance (design-weight.md "Over-capacity behavior", GENTLE
## scheme). A FLAT multiplier per tier -- NORMAL 1.0, OVER 0.75, SUPER 0.50, ULTRA 0.25 -- so the
## slow-down steps down in three discrete jumps rather than sliding linearly. Never 0: even ULTRA
## keeps the player crawling. player.gd multiplies its walk target by this (walking ONLY --
## knockback/lunge impulses are never scaled). Kept here so player.gd stays minimal and the whole
## weight model lives in one place.
func encumbrance_factor() -> float:
	match encumbrance_tier():
		Encumbrance.OVER:
			return OVER_SPEED
		Encumbrance.SUPER:
			return SUPER_SPEED
		Encumbrance.ULTRA:
			return ULTRA_SPEED
		_:
			return NORMAL_SPEED


## DEFERRED this slice, per the user ("if we hit 'sort' we will develop that
## later"). Future behavior: tools fill the hotbar first, non-tools push to the
## back/background of inventory (beyond the hotbar window). Intentionally a no-op
## for now.
func sort() -> void:
	pass

# Verified against: Godot 4.7.1 (2026-07-19)
