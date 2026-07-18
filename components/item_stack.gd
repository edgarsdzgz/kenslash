class_name ItemStack
extends RefCounted
## What a NON-EMPTY inventory slot holds (design-items.md "Item model"): a shared ItemData
## DEFINITION plus this slot's RUNTIME count. The count is per-slot mutable state, so it
## lives here on the RefCounted stack -- NEVER on the shared ItemData resource (the sharing
## trap, patterns/resource-driven-design.md). A null slot in Inventory.slots means empty;
## a non-null ItemStack means `count` copies of `item` sit in that slot.
##
## RefCounted (not a Resource/Node): it is pure runtime bookkeeping, never saved as an
## asset and never in the scene tree, so it perturbs no node/orphan monitor.

## The item definition this stack holds (shared, immutable data). Null only for a
## default-constructed placeholder; a real slot always has a non-null item.
var item: ItemData = null
## How many of `item` are in this slot. Kept in [1, item.max_stack] by Inventory.add_item;
## a stack is never stored with count <= 0 (that slot is left null/empty instead).
var count: int = 0


func _init(p_item: ItemData = null, p_count: int = 1) -> void:
	item = p_item
	count = p_count

# Verified against: Godot 4.7.1 (2026-07-18)
