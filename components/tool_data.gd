class_name ToolData
extends ItemData
## Definition (stats) for one tool the player can equip -- sword / axe / pickaxe (System 3,
## design-durability.md). A ToolData IS an ItemData (E1b, design-items.md): it inherits
## display_name/max_stack/glyph and ADDS the tool-only combat/wear/harvest stats below.
## Tools keep the inherited max_stack default of 1 (non-stackable) -- they are never merged
## into a stack. The tool's CURRENT durability is RUNTIME on a per-tool DurabilityComponent
## node, NEVER stored here -- storing runtime wear on a shared resource is the sharing trap
## (patterns/resource-driven-design.md).
##
## Split of the two decoupled systems: atk feeds System 1 (HP), power/break_threshold/
## wear_max feed System 2 (wear), harvest_type feeds System 3 (the gather gate). blade_color
## is purely for readability so the player can see which tool is equipped.

## System 1 -- HP damage potential. The Hurtbox applies max(0, atk - target.def).
@export var atk: int = 1
## System 2 -- this tool's rating on the shared hardness scale.
@export var power: int = 0
## System 2 -- workable margin above power before the target is "too hard" (Band C).
@export var break_threshold: int = 1
## System 2 -- max durability this tool can lose in a single hit.
@export var wear_max: int = 0
## Starting/maximum durability for this tool's runtime DurabilityComponent.
@export var max_durability: int = 40
## System 3 -- the gather category (Harvest.Type). NONE = a pure weapon (no harvest).
@export var harvest_type: int = Harvest.Type.NONE
## Whether this tool performs the full 3-hit COMBO (arc, arc, lunge) on repeated attacks.
## Only the sword combos; the axe/pickaxe (and the unarmed fist) do a single regular arc
## swing each press -- no chain, no lunge finisher. Read in player.gd attack().
@export var has_combo: bool = false
## Blade tint when this tool is equipped, so the active tool reads at a glance.
@export var blade_color: Color = Color(0.85, 0.9, 1.0, 1.0)
## The swung weapon's SILHOUETTE, as a Polygon2D outline in blade-local space (+x points
## outward along the swing, the current rectangle spans x[-15,15] y[-3,3]). Lets each tool
## read as its own shape -- a pointed sword blade, a broad axe head, a double-pointed pick --
## instead of one recolored rectangle. Presentation only: the invisible Sword Hitbox
## rectangle (gameplay reach) is unchanged. EMPTY -> the equipment falls back to the default
## rectangle (so a shapeless/legacy tool and the unarmed fist still render).
@export var blade_shape: PackedVector2Array = PackedVector2Array()

# Verified against: Godot 4.7.1 (2026-07-18)
