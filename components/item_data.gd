class_name ItemData
extends Resource
## Base DEFINITION for anything the inventory can hold -- a tool, a resource, a future
## consumable (design-items.md "Item model"). Pure DEFINITION data on a shared Resource:
## the sharing trap (patterns/resource-driven-design.md) means NO runtime/per-instance
## state ever lives here (a tool's current wear, a stack's count) -- those live on the
## Inventory's ItemStack or a runtime component, never on the shared ItemData.
##
## ToolData EXTENDS this (adding atk/power/break_threshold/wear_max/harvest_type/
## blade_color), so a tool IS an ItemData -- the Inventory, HUD, and pickup path all speak
## ItemData and only DOWN-CAST to ToolData at the equip seam (a resource stack casts to
## null -> the unarmed fallback, exactly as an empty slot does).

## Human-readable label (debug/logs; the HUD's fallback glyph is its first character).
@export var display_name: String = "Item"
## How many of this item fit in ONE inventory slot. 1 = non-stackable (all tools); a
## resource (Wood/Stone/Stick/Fiber) uses 255. add_item() tops existing stacks to this
## cap before spilling into new slots.
@export var max_stack: int = 1
## Short hotbar glyph (1-2 chars) shown in the slot widget. "" means "fall back to the
## display_name's first character" -- so tools (glyph "") still read S/A/P unchanged while
## resources can pin an explicit letter (W/S) independent of their display_name.
@export var glyph: String = ""
## Tint a world Drop of this item paints its little ground primitive (E2, design-items.md
## "Drops"). Purely visual -- a mini brown square for Wood, a small gray bit for Stone --
## so a drop reads as a shrunk version of its resource. The default gray covers items that
## do not (yet) drop as world entities (tools).
@export var color: Color = Color(0.6, 0.6, 0.6, 1)
## Hotbar-ICON silhouette: this item's outline in its OWN local space (any scale -- the HUD
## measures its bounding box and normalizes it to fit the slot), rendered FILLED in `color`
## (a tool uses its blade_color). A small readable shape (a plank for Wood, a hexagon for
## Stone, a thin stick, a fiber tuft) that replaces the single-letter glyph in the slot.
## EMPTY -> the HUD falls back: a ToolData reuses its own `blade_shape` as the icon, and any
## still-shapeless item shows the letter glyph as before. Keep it a simple, non-self-
## intersecting polygon. Presentation only -- never read by gameplay.
@export var icon_shape: PackedVector2Array = PackedVector2Array()
## Per-UNIT weight (design-weight.md "Model"): the weight of ONE of this item. A stack
## weighs `weight * count`, and the Inventory sums it across ALL slots into total_weight()
## for the carry-capacity encumbrance. Tools inherit this (ToolData IS an ItemData) and
## carry weight too. 0.0 = weightless (the safe default for any item that has not set one).
@export var weight: float = 0.0

# Verified against: Godot 4.7.1 (2026-07-19)
