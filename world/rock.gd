class_name Rock
extends StaticBody2D
## A destructible mining target (design-durability.md). No HealthComponent -- you MINE
## it, not ATK it: its Hurtbox routes each strike into a `material` DurabilityComponent
## (integrity). A tool wears against this rock's `hardness` every hit, but the integrity
## only drops when the hit AFFECTS the target (Band A/B). A too-hard rock (Band C) wears
## the tool yet never chips -- you need a stronger tool. Destroyed (queue_free) at 0
## integrity; drops come later. The solid body sits on the `world` layer so the player
## bumps into it while mining.
##
## hardness/integrity/color are exported on THIS root so main.tscn can author a soft
## rock vs an obsidian rock by overriding the instance directly -- no fiddly nested
## node-path overrides. _ready pushes them down onto the child Hurtbox/Material.

## System 2 -- how hard this rock is to carve (base material, no armor).
@export var hardness: int = 6
## Mining integrity: how much material there is to remove before it is gone.
@export var integrity: int = 4
## Body tint -- gray for soft stone, dark violet for obsidian, so they read apart.
@export var color: Color = Color(0.5, 0.5, 0.55, 1)

@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _material: DurabilityComponent = $Material
@onready var _body: Polygon2D = $Body


func _ready() -> void:
	# Children run _ready first, so Material already latched its scene-default
	# current_durability; overwrite both max and current from this rock's integrity.
	_material.max_durability = integrity
	_material.current_durability = integrity
	_hurtbox.hardness = hardness
	_body.color = color
	# Owner wires its own components ("call down"): the Hurtbox mines this integrity.
	_hurtbox.material_durability = _material
	_material.durability_changed.connect(_on_integrity_changed)
	_material.broke.connect(_on_broke)
	# Flash on a mining hit so a struck rock reads even before it is mined out.
	_hurtbox.hit_taken.connect(_on_hit_taken)


func _on_hit_taken(_hitbox: Hitbox) -> void:
	_body.modulate = Color(2.0, 2.0, 2.0)
	var tween: Tween = create_tween()
	tween.tween_property(_body, "modulate", Color.WHITE, 0.2)


func _on_integrity_changed(current: int, max_val: int) -> void:
	print("[rock] integrity ", current, "/", max_val)


## Integrity hit 0: the rock is mined out. Drops come later; for now it is removed.
func _on_broke() -> void:
	print("[rock] mined out -- destroyed")
	queue_free()

# Verified against: Godot 4.7.1 (2026-07-17)
