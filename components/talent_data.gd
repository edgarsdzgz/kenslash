class_name TalentData
extends Resource
## Definition for ONE node in the Track A talent tree (plan-core-loop.md Phase 2; design-crafting.md
## "Track A -- Personal", design-multiplayer.md talent points). Pure DEFINITION data on a shared
## Resource, exactly like ItemData/ToolData: the node's id, its talent-point cost, the prereq ids that
## must be unlocked before it, and an INERT effect descriptor. NO runtime/per-character state ever lives
## here (which nodes a given character has unlocked is CHARACTER state on components/talents.gd, never on
## this shared definition -- the sharing trap, patterns/resource-driven-design.md).
##
## EFFECTS ARE INERT IN PART 2.1. `effect_kind` + `magnitude` DECLARE what a node WILL do (e.g.
## MELEE_DAMAGE +1, HARVEST_YIELD +1) so the tree can be authored now, but NOTHING reads them yet --
## Part 2.2 consumes this payload to apply the perk to a real stat (and adds respec). Until then a talent
## unlock only flips a bit in the unlocked set; it changes no gameplay number. Costs are placeholders for
## later balancing, like the Progression tuning constants.

## The KIND of perk this node grants once Part 2.2 wires effects. NONE = a pure gate node (no stat
## change). MELEE_DAMAGE / HARVEST_YIELD name concrete future perks. Serializes to an int in the .tres.
## Append new kinds (MOVE_SPEED, STAMINA_MAX, ...) as the tree grows -- purely additive.
enum EffectKind { NONE, MELEE_DAMAGE, HARVEST_YIELD }

## Stable identity used everywhere the tree is addressed (unlock/prereq lookups, the unlocked set, a
## future save blob). A StringName so id compares are pointer-cheap and never collide with display text.
@export var id: StringName = &""
## Human-readable label (debug/logs, a future talent-tree UI). Never used as an identity key.
@export var display_name: String = "Talent"
## Talent-point price to unlock this node. The CALLER (Part 2.2) deducts this from Progression.talent_points
## after can_unlock() clears it; Talents itself only reports the cost, staying decoupled from Progression.
@export var cost: int = 1
## Ids of the nodes that must ALREADY be unlocked before this one can be. Empty = a root node (no gate).
## An Array[StringName] so the prereq edges are the same vocabulary as `id`. Definition data -- never
## mutated at runtime, so the exported-array sharing trap is moot here (nothing writes it).
@export var prereqs: Array[StringName] = []
## INERT until Part 2.2 -- see the class docstring. Which stat the perk touches once effects are wired.
@export var effect_kind: EffectKind = EffectKind.NONE
## INERT until Part 2.2 -- see the class docstring. How much `effect_kind` grants (e.g. +1 melee damage).
@export var magnitude: int = 0

# Verified against: Godot 4.7.1 (2026-07-19)
