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

## The Drop scene a mined rock spits out per pick (Milestone E2, design-items.md). Preloaded.
const DROP_SCENE: PackedScene = preload("res://world/drop.tscn")
## Deterministic tiny offset (px) a mined stone drops at, just above the rock so it reads as
## chipping off. Fixed (no RNG) for a reproducible headless assertion.
const _YIELD_OFFSET: Vector2 = Vector2(0, -10)

## System 2 -- how hard this rock is to carve (base material, no armor).
@export var hardness: int = 6
## Mining integrity: how much material there is to remove before it is gone.
@export var integrity: int = 4
## Body tint -- gray for soft stone, dark violet for obsidian, so they read apart.
@export var color: Color = Color(0.5, 0.5, 0.55, 1)
## E2 harvest yield (design-items.md "Harvest yield"): the resource this rock drops PER
## affecting mine. Data-driven export so main.tscn AND streamed instances yield with no code
## edits. A mineral gives ONE stone per successful pick (a tree, by contrast, yields on fell).
@export var yield_item: ItemData = preload("res://data/stone.tres")

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
	_spawn_yield()


## Integrity hit 0: the rock is mined out. The stone for THIS final pick was already spawned
## by _on_integrity_changed (durability_changed fires on every affecting hit, the mine-to-0
## one INCLUDED), so we do NOT spawn here -- that would double the last stone. Just remove it.
func _on_broke() -> void:
	print("[rock] mined out -- destroyed")
	queue_free()


## Spawn ONE count-1 Stone Drop of yield_item per AFFECTING mine (E2, design-items.md).
## Driven from durability_changed, which the DurabilityComponent emits once per hit that
## reduces integrity -- so each pick yields its stone (and the mine-to-0 pick yields the last
## one here, NOT in _on_broke). A Band-C "too hard" whiff never reduces integrity, so
## durability_changed never fires and no stone drops -- the mineral gate falls out for free.
## Sibling under get_parent() (same chunk container / arena); add_child DEFERRED (mid-signal),
## global_position set deferred after the add. Pickup / lifetime / persistence are all E3.
func _spawn_yield() -> void:
	if yield_item == null:
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var drop: Drop = DROP_SCENE.instantiate()
	drop.setup(yield_item, 1)
	parent.add_child.call_deferred(drop)
	drop.set_deferred("global_position", global_position + _YIELD_OFFSET)

# Verified against: Godot 4.7.1 (2026-07-18)
