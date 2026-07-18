extends StaticBody2D
## A destructible CHOP-only resource node (System 3, design-durability.md). NOTE: no
## `class_name` here -- `Tree` collides with Godot's own native `Tree` control class
## ("Class 'Tree' hides a native class" parse error), so this is a plain script
## (referenced by path/node lookup, never by type name), per the design task's
## explicit fallback.
##
## Mirrors world/rock.gd's shape (root-exported hardness/integrity/color, a Hurtbox
## routing into a `material_durability` DurabilityComponent). The gate that makes this
## a CHOP-only target lives on the Hurtbox's `required_harvest` (checked at the
## Hurtbox chokepoint, Gate 1) -- this script does not re-check tool type itself. No
## HealthComponent: you FELL it, not ATK it. Solid body sits on `world` (bit 1), the
## same layer rocks use, so the player bumps into it while it stands.
##
## hardness/integrity/color are exported on THIS root, same pattern as Rock, so
## main.tscn can author variants by overriding the instance directly.

## System 2 -- how hard this tree is to fell (base material). Deliberately soft --
## the axe (power 5) fells it with zero wear (Band A).
@export var hardness: int = 3
## Felling integrity: how much wood there is before the tree comes down.
@export var integrity: int = 6
## Body tint -- green so a tree reads apart from the gray/violet mineral rocks.
@export var color: Color = Color(0.25, 0.55, 0.25, 1)

@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _material: DurabilityComponent = $Material
@onready var _body: Polygon2D = $Body


func _ready() -> void:
	# Children run _ready first, so Material already latched its scene-default
	# current_durability; overwrite both max and current from this tree's integrity.
	_material.max_durability = integrity
	_material.current_durability = integrity
	_hurtbox.hardness = hardness
	_body.color = color
	# Owner wires its own components ("call down"): the Hurtbox fells this integrity.
	_hurtbox.material_durability = _material
	_material.durability_changed.connect(_on_integrity_changed)
	_material.broke.connect(_on_broke)
	# Flash on a chopping hit so a struck tree reads even before it comes down.
	_hurtbox.hit_taken.connect(_on_hit_taken)


func _on_hit_taken(_hitbox: Hitbox) -> void:
	_body.modulate = Color(2.0, 2.0, 2.0)
	var tween: Tween = create_tween()
	tween.tween_property(_body, "modulate", Color.WHITE, 0.2)


func _on_integrity_changed(current: int, max_val: int) -> void:
	print("[tree] integrity ", current, "/", max_val)


## Integrity hit 0: the tree is felled. Drops come later; for now it is removed.
func _on_broke() -> void:
	print("[tree] felled -- destroyed")
	queue_free()

# Verified against: Godot 4.7.1 (2026-07-17)
