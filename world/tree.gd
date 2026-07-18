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

## The Drop scene a felled tree bursts (Milestone E2, design-items.md). Preloaded once.
const DROP_SCENE: PackedScene = preload("res://world/drop.tscn")
## Radius (px) of the deterministic ring the felled wood scatters onto. Small (~0.3 tile,
## components/world_scale.gd TILE 40) so the burst reads as landing at the stump.
const _YIELD_RING_RADIUS: float = 12.0

## System 2 -- how hard this tree is to fell (base material). Deliberately soft --
## the axe (power 5) fells it with zero wear (Band A).
@export var hardness: int = 3
## Felling integrity: how much wood there is before the tree comes down.
@export var integrity: int = 6
## Body tint -- green so a tree reads apart from the gray/violet mineral rocks.
@export var color: Color = Color(0.25, 0.55, 0.25, 1)
## E2 harvest yield (design-items.md "Harvest yield"): the resource a felled tree drops and
## how many. Data-driven exports so main.tscn AND streamed instances yield with no code
## edits. A tree yields NOTHING per chop -- only felling (integrity 0) bursts this wood.
@export var yield_item: ItemData = preload("res://data/wood.tres")
@export var yield_amount: int = 3

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


## Integrity hit 0: the tree is felled -- burst its wood (E2), then remove the trunk.
func _on_broke() -> void:
	print("[tree] felled -- destroyed")
	_spawn_yield()
	queue_free()


## Burst `yield_amount` count-1 Wood Drops around the stump on fell (E2, design-items.md).
## Positions are DETERMINISTIC -- a fixed ring by index (no RNG, no Time/OS) -- so the
## headless test can assert exactly how many land and where. Spawned as SIBLINGS under
## get_parent() so they join the same chunk container / arena the tree lived in. add_child
## is DEFERRED: we are inside the Material's `broke` signal (mid-physics) and about to
## queue_free this tree, so deferring keeps the scene-tree edit safe; global_position is set
## deferred too, ordered after the add so the drop is in-tree when it is positioned. Pickup /
## lifetime / persistence are all E3.
func _spawn_yield() -> void:
	if yield_item == null:
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var origin: Vector2 = global_position
	var n: int = maxi(yield_amount, 1)
	for i in range(yield_amount):
		var drop: Drop = DROP_SCENE.instantiate()
		drop.setup(yield_item, 1)
		var angle: float = TAU * float(i) / float(n)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * _YIELD_RING_RADIUS
		parent.add_child.call_deferred(drop)
		drop.set_deferred("global_position", origin + offset)

# Verified against: Godot 4.7.1 (2026-07-18)
