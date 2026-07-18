class_name ToolData
extends Resource
## Definition (stats) for one tool the player can equip -- sword / axe / pickaxe (System 3,
## design-durability.md). Pure DEFINITION data: an ItemData-shaped Resource so it grows into
## a real item system later. The tool's CURRENT durability is RUNTIME on a per-tool
## DurabilityComponent node, NEVER stored here -- storing runtime wear on a shared resource
## is the sharing trap (patterns/resource-driven-design.md).
##
## Split of the two decoupled systems: atk feeds System 1 (HP), power/break_threshold/
## wear_max feed System 2 (wear), harvest_type feeds System 3 (the gather gate). blade_color
## is purely for readability so the player can see which tool is equipped.

## Human-readable label (debug/logs; a UI later).
@export var display_name: String = "Tool"
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
## Blade tint when this tool is equipped, so the active tool reads at a glance.
@export var blade_color: Color = Color(0.85, 0.9, 1.0, 1.0)

# Verified against: Godot 4.7.1 (2026-07-17)
