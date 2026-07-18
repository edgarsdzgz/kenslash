class_name Harvest
## Shared harvest-category enum (System 3, design-durability.md). A tool carries ONE
## harvest_type; a resource node carries ONE required_harvest. They must match for the
## tool to affect the resource (Gate 1 -- the tool-type gate). Creatures use NONE and
## are never gated by tool type. Extensible: append DIG, PUMP, ... as new gathers arrive.
##
## A pure enum holder -- never instantiated (no extends; defaults to RefCounted). Referenced
## as `Harvest.Type.MINE`. Kept as its own class_name so the Hitbox, Hurtbox, tools, and
## resource nodes all speak the same category vocabulary.

enum Type { NONE, CHOP, MINE }

# Verified against: Godot 4.7.1 (2026-07-17)
