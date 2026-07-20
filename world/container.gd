class_name StorageContainer
extends Placeable
## A placeable STORAGE CONTAINER (plan-epic2-parts.md Phase 2 Part 2.1; design-crafting.md "Track B -- Building").
## The SECOND placeable (after the crafting Station) and the first that resolves the reviewer-flagged place_station
## hardcoding: it rides the SAME kind-agnostic build/persistence path as a Station, differing only in its
## placement_kind() (CONTAINER) and its own build cost. A chest you place in the world and later stash items in.
##
## `class_name StorageContainer`, NOT `Container`: `Container` is a BUILT-IN Godot class (the Control layout base
## for HBoxContainer/VBoxContainer/...), so `class_name Container` collides with the native namespace and fails to
## parse -- the same native-class clash world/tree.gd documents (it drops its class_name entirely). The FILE stays
## container.gd / container.tscn (the plan's name); the SCRIPT class is StorageContainer so tests can `is`-check it.
##
## Holds its OWN components/inventory.gd store (DRY -- a container reuses the player's slot+weight inventory model,
## plan-epic2-parts.md open-confirmation #4). The store is a RefCounted field, NOT a Node child, so it never
## perturbs the streaming node-count / orphan baselines (freed with the container when its refcount drops). Part
## 2.1 scope is the ENTITY + its EMPTY-container round-trip ONLY: the store exists and is exposed, but item
## TRANSFER (store/retrieve) and CONTENTS persistence are Part 2.2 -- for now an empty container round-trips as
## pure identity (kind + position), capture_state()/apply_state() carrying no contents yet.
##
## A plain Node2D in the "container" group (no collision) -- like Station/Forageable, a thing you stand NEXT TO
## and interact with, not a wall. The group is what Part 2.2's transfer interaction (and tests) scan to find a
## container in range, exactly as Station.tags_in_range scans the "station" group.
##
## DETERMINISM: build cost + persistence are pure data (authored exports + plain-Dictionary state), no Time/OS/RNG.

## The group every StorageContainer joins -- the one Part 2.2's transfer scan (and the tests) look it up by. A
## StringName const so the join and the scan reference the SAME key (never a typo'd literal in two places).
const GROUP: StringName = &"container"

## This container's internal store (design-inventory.md), a fresh per-instance Inventory (RefCounted -- the `.new()`
## initializer runs per _init, so no two containers ever alias one store, avoiding the shared-default trap). Item
## TRANSFER into/out of it is Part 2.2; for Part 2.1 it starts EMPTY and is only EXPOSED (the goal-post assertion
## that a placed container carries an internal Inventory). A public field so Part 2.2's transfer op + the tests
## read it directly, mirroring how the player exposes its own `inventory`.
var store: Inventory = Inventory.new()


## Move exactly `n` of `item` FROM the player inventory (`from_inv`) INTO this container's store,
## ATOMICALLY (plan-epic2-parts.md Part 2.2 "store"). Returns `n` on success, 0 on ANY shortfall --
## moving NOTHING in the refuse case (the classic no-dupe/no-loss transfer guarantee). Thin, named
## wrapper over the shared `_transfer` so callers read intent (deposit vs withdraw) at the call site.
func deposit(item: ItemData, n: int, from_inv: Inventory) -> int:
	return _transfer(item, n, from_inv, store)


## Move exactly `n` of `item` FROM this container's store INTO the player inventory (`to_inv`),
## ATOMICALLY (plan-epic2-parts.md Part 2.2 "retrieve"). Returns `n` on success, 0 on ANY shortfall.
## The mirror of deposit(): same atomic guarantee, opposite direction.
func withdraw(item: ItemData, n: int, to_inv: Inventory) -> int:
	return _transfer(item, n, store, to_inv)


## The ATOMIC move primitive both deposit()/withdraw() compose (kept static + Inventory-typed so the
## direction is chosen ONLY by which store is src vs dst -- one code path, no duplication). Move exactly
## `n` of `item` from `src` to `dst`, or move NOTHING and return 0. The two-part precheck makes it atomic:
##   1. REFUSE if `src` does not hold the full `n` (Inventory.has_item) -- an over-count REFUSES (moves
##      nothing), it does NOT clamp to a partial move. DECIDED: refuse, so a transfer is all-or-nothing.
##   2. Commit into `dst` FIRST behind a snapshot/restore rollback: if add_item reports ANY overflow the
##      destination is FULL, so restore it byte-identical and refuse (no partial deposit, no item loss).
## Only AFTER `dst` has accepted all `n` (overflow 0) do we remove `n` from `src` -- guaranteed to remove
## exactly `n` by the step-1 precheck, so there is no failure path past the commit and nothing can be lost
## or duplicated. Weight/encumbrance re-flow the NORMAL way on both inventories (the stack sums shift).
## A null item or n <= 0 is a no-op (returns 0). Deterministic -- no Time/OS/RNG, purely the item counts.
static func _transfer(item: ItemData, n: int, src: Inventory, dst: Inventory) -> int:
	if item == null or n <= 0:
		return 0
	if not src.has_item(item, n):
		return 0  # source short -- refuse whole (no partial), move nothing
	# Test-fit into dst without committing: snapshot, try to add all n, roll back if it cannot hold them.
	var dst_snapshot: Array = dst.snapshot()
	var overflow: int = dst.add_item(item, n)
	if overflow != 0:
		dst.restore(dst_snapshot)  # dst full -- refuse, leave dst byte-identical (no partial, no loss)
		return 0
	# dst accepted all n; the step-1 precheck guarantees src holds n, so this removes exactly n.
	src.remove_item(item, n)
	return n


func _ready() -> void:
	# Join the "container" group Part 2.2's transfer scan uses -- the same pure group-membership contract Station
	# and Forageable use. Membership on a plain Node2D (no Area2D), so this adds no collision node to the streaming
	# node-count baseline.
	add_to_group(GROUP)


## The persistence contract (world/placeable.gd): a container persists as a Kind.CONTAINER ADDITION delta, the
## mirror of a Station's STATION delta. Part 2.2 rides its STORE CONTENTS in that SAME delta Dictionary (no new
## channel): capture_state() serializes the store's stacks and apply_state() rebuilds them, so a container holding
## items survives unload/reload with its exact contents. An EMPTY container still round-trips as identity (an empty
## `contents` list). The kind-agnostic path is UNCHANGED -- this file is the single place the contents knowledge lives.
func placement_kind() -> int:
	return ChunkData.Kind.CONTAINER


## The key the store contents ride under inside the delta `state` Dictionary. A named const so capture_state()
## writes and apply_state() reads the SAME key (never a typo'd literal in two places), mirroring GROUP above.
const CONTENTS_KEY: StringName = &"contents"


## Serialize this container's `store` into a store_var-/JSON-safe delta Dictionary (the ADDITION delta `state`).
## Contents are a flat list of [item RESOURCE PATH, count] pairs -- the SAME item-by-path idiom the DROP write-back
## uses (ChunkContent.drop_entry: item.resource_path), NEVER an object ref -- one pair per NON-EMPTY slot (slot
## order preserved; empty slots omitted). Paths + ints only, so the whole chunk stays flat serializable data and
## the disk save (ChunkData.to_dict) remains a CALL, not a redesign. An empty store yields an empty `contents` list
## (the identity round-trip). Also called on placement (register_placement) -- one serializer for placement AND the
## unload write-back, so the two can never disagree.
func capture_state() -> Dictionary:
	var contents: Array = []
	for i in range(store.slots.size()):
		var stack: ItemStack = store.slots[i]
		if stack != null and stack.item != null:
			contents.append([stack.item.resource_path, stack.count])
	return {CONTENTS_KEY: contents}


## Rebuild `store` from a capture_state() Dictionary -- the inverse of capture_state(). load() each item by its
## stable resource_path (the item id, exactly as the DROP spawn path re-loads its item) and add_item() the count
## back, so the reloaded container holds the SAME items in the SAME totals. Called by ChunkContent.spawn() on a
## FRESH instance whose store starts empty, BEFORE add_child (so it is populated the moment it enters the tree).
## A missing/empty `contents` (a Part-2.1 identity entry, or a plain {} placement) restores an empty store -- the
## empty round-trip still works. A null item path is skipped defensively (a renamed/removed resource never crashes).
## NOTE: item COUNTS are preserved EXACTLY, but slot ORDER is not guaranteed -- add_item compacts each stack from
## slot 0, so a store that had gaps re-lands its stacks packed. Cosmetic only (deposits fill compactly anyway); the
## totals a caller reads via count_of() are identical.
func apply_state(state: Dictionary) -> void:
	var contents: Array = state.get(CONTENTS_KEY, [])
	for pair in contents:
		var item: ItemData = load(pair[0]) as ItemData
		if item != null:
			store.add_item(item, int(pair[1]))

# Verified against: Godot 4.7.1 (2026-07-20)
