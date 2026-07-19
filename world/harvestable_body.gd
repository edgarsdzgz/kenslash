class_name HarvestableBody
extends StaticBody2D
## Shared BASE for the attack-driven MINE/CHOP resource nodes (System 3, design-durability.md): the Rock
## and the Tree. Unlike a forageable (walked-over, pressed), a harvestable body is a SOLID node you
## STRIKE: each hit routes through a Hurtbox into a `material` DurabilityComponent (integrity), a tool
## wears against its `hardness`, and the integrity drops only when the hit AFFECTS it (Band A/B). No
## HealthComponent -- you MINE/FELL it, not ATK it. The solid body sits on the `world` layer so the
## player bumps into it while it stands.
##
## The base owns everything Rock and Tree share: the exported hardness/integrity/color (pushed down onto
## the child Material/Hurtbox/Body in _ready), the full component wiring + signal connects, the damage-
## blink _on_hit_taken flash, and the reusable _spawn_drop() deferred sibling-add. Each subclass stays
## THIN, authoring only its differences: the Rock drops a chip PER affecting mine; the Tree yields ON fell
## and plays a fall/break animation. hardness/integrity/color are set per-type in each subclass's _init()
## and stay @export, so main.tscn / streamed instances can author variants by overriding the instance.

## Damage-blink tint: a struck (not-yet-destroyed) body flashes its Body's fill to this warm color once,
## then fades back to its natural color -- a readable "took a hit" COLOR change, not the old overbright
## white-out that washed the body toward invisible. Shared by every harvestable body.
const HIT_FLASH_COLOR: Color = Color(1.0, 0.5, 0.4, 1.0)
## The Drop scene a harvested body bursts (Milestone E2, design-items.md). Preloaded once.
const DROP_SCENE: PackedScene = preload("res://world/drop.tscn")

## System 2 -- how hard this body is to carve/fell (base material). Set per-type in _init(); exported so
## main.tscn can author a soft vs obsidian-hard variant by overriding the instance directly.
@export var hardness: int = 1
## Integrity: how much material there is to remove before the body is gone / comes down.
@export var integrity: int = 1
## Body tint -- set per-type in _init() (green tree vs gray/violet mineral), exported for variants.
@export var color: Color = Color.WHITE

@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _material: DurabilityComponent = $Material
@onready var _body: Polygon2D = $Body


func _ready() -> void:
	# Children run _ready first, so Material already latched its scene-default current_durability;
	# overwrite both max and current from this body's integrity, push hardness + color down, and wire the
	# components ("call down"): the Hurtbox mines/fells this integrity. The durability_changed / broke /
	# hit_taken handlers below are overridable hooks -- a subclass supplies its own per-hit + on-broke
	# behaviour, the flash is shared.
	_material.max_durability = integrity
	_material.current_durability = integrity
	_hurtbox.hardness = hardness
	_body.color = color
	_hurtbox.material_durability = _material
	_material.durability_changed.connect(_on_integrity_changed)
	_material.broke.connect(_on_broke)
	# Flash on a hit so a struck body reads even before it is mined out / felled.
	_hurtbox.hit_taken.connect(_on_hit_taken)


## Damage blink (shared): a single quick COLOR flash (not an overbright white-out) so a struck-but-
## standing body clearly reads as taking a hit. Flash the fill to the warm hit tint, then fade back to
## the body's natural color.
func _on_hit_taken(_hitbox: Hitbox) -> void:
	_body.color = HIT_FLASH_COLOR
	var tween: Tween = create_tween()
	tween.tween_property(_body, "color", color, 0.18)


## Integrity dropped on an affecting hit -- overridable hook the base wires to Material.durability_changed.
## Default: no-op. The Rock overrides it to drop a chip per hit; the Tree only yields on fell.
func _on_integrity_changed(_current: int, _max_val: int) -> void:
	pass


## Integrity hit 0 -- overridable hook the base wires to Material.broke. Default: destroy the body. The
## Rock keeps that (mined out -> destroyed); the Tree overrides it to run its fall/break animation.
func _on_broke() -> void:
	queue_free()


## Spawn ONE count-1 Drop of `item` at world `at`, a SIBLING under get_parent() (the same chunk container
## / arena this body lived in). add_child is DEFERRED -- callers fire this mid-signal (Material.broke /
## durability_changed, mid-physics) and may be about to queue_free the body, so deferring keeps the
## scene-tree edit safe; global_position is set deferred too, ordered AFTER the add so the drop is in-tree
## when positioned. A subclass bursts a ring (tree) or a single chip (rock) by calling this once per drop.
## A null item / null parent is guarded (a Band-C whiff that never reduces integrity simply spawns none).
func _spawn_drop(item: ItemData, at: Vector2) -> void:
	if item == null:
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var drop: Drop = DROP_SCENE.instantiate()
	drop.setup(item, 1)
	parent.add_child.call_deferred(drop)
	drop.set_deferred("global_position", at)

# Verified against: Godot 4.7.1 (2026-07-19)
