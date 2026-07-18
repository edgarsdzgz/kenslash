class_name Hurtbox
extends Area2D
## Receives a strike from an overlapping Hitbox and resolves BOTH systems at the ONE
## chokepoint (design-durability.md): System 1 combat HP via CombatResolver, System 2
## durability wear via DurabilityResolver. Still the monitoring side of the one-way
## Hitbox->Hurtbox scheme; still owns i-frames and the hit_taken signal (knockback).
##
## Split rule: HealthComponent = combat HP (ATK/DEF). DurabilityComponent = wear
## (hardness). A creature has a `health`; a rock does not (you mine it, not ATK it).

signal hit_taken(hitbox: Hitbox)
## Emitted when invincibility begins / ends, so owners can drive a blink or other
## feedback without polling is_invincible every frame.
signal invincibility_started
signal invincibility_ended

## The HealthComponent that takes combat HP damage. Null for a non-creature target
## (a rock is mined, not damaged). Injected by the owning entity ("call down").
@export var health: HealthComponent
## System 3 -- the gather category required to affect this target (Harvest.Type),
## design-durability.md. NONE = a creature/non-resource target, never gated by tool
## type. A resource node (tree/mineral) sets this to CHOP/MINE; a strike from a tool
## whose harvest_type does not match is a total whiff -- Gate 1, checked first.
@export var required_harvest: int = Harvest.Type.NONE
## System 1 -- HP mitigation. This is the EFFECTIVE value; an owner drops it toward a
## flesh base when its armor breaks.
@export var def: int = 0
## System 2 -- base material + armor hardness. EFFECTIVE value; drops on armor break.
@export var hardness: int = 2
## System 2 -- durability the struck armor/material loses per AFFECTING hit ("wear_taken").
@export var wear_taken: int = 1
## Optional worn armor. Degrades each affecting hit; the OWNER reacts to its `broke`
## (dropping def/hardness to flesh). Assigned in code by the owner, null otherwise.
@export var armor: DurabilityComponent = null
## Optional mineable integrity (a rock). Reduced ONLY when a hit affects the target
## (Band A/B). Band C (too hard) never chips it. The owner destroys the target on
## `broke`. Named *_durability (not `material`) -- CanvasItem already owns `material`.
@export var material_durability: DurabilityComponent = null
## Seconds of invincibility after a hit. Short for enemies so multi-hit attacks can
## still connect; longer for a player.
@export var invincibility_time: float = 0.1

var is_invincible: bool = false

@onready var _timer: Timer = $InvincibilityTimer


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	_timer.timeout.connect(_on_invincibility_ended)


func _on_area_entered(area: Area2D) -> void:
	var hitbox: Hitbox = area as Hitbox
	if hitbox == null or is_invincible:
		return

	# Gate 1 -- tool-type gate (System 3, design-durability.md), checked BEFORE
	# System 1/2 and before i-frames start. A resource node (required_harvest !=
	# NONE) only reacts to a tool whose harvest_type matches; any other tool is a
	# clean whiff -- no HP, no DurabilityResolver, no wear on either side, not even
	# invincibility. Creatures keep required_harvest at NONE and are NEVER gated by
	# tool type -- any tool still deals its ATK-based HP to them.
	if required_harvest != Harvest.Type.NONE and hitbox.harvest_type != required_harvest:
		return

	# System 1 -- combat HP. Creatures only; flesh is never "too hard" to damage, so
	# hardness does not gate this. A rock has no health and takes none.
	if health != null:
		health.take_damage(CombatResolver.hp_damage(hitbox.atk, def))

	# System 2 -- durability. Only a wearable weapon carries a durability component;
	# an enemy's contact attack has none and skips wear entirely.
	if hitbox.durability != null:
		var result: Dictionary = DurabilityResolver.resolve(
			hitbox.power, hardness, hitbox.break_threshold, hitbox.wear_max)
		var weapon_wear: int = result["weapon_wear"]
		var affects_target: bool = result["affects_target"]
		if weapon_wear > 0:
			hitbox.durability.wear(weapon_wear)
		# BOTH wear: the struck armor/material degrades only when the hit lands
		# (Band A/B). Band C (too hard) wears the weapon but never the target.
		if affects_target:
			if armor != null:
				armor.wear(wear_taken)
			if material_durability != null:
				material_durability.wear(wear_taken)

	hit_taken.emit(hitbox)
	is_invincible = true
	invincibility_started.emit()
	_timer.start(invincibility_time)


func _on_invincibility_ended() -> void:
	is_invincible = false
	invincibility_ended.emit()

# Verified against: Godot 4.7.1 (2026-07-17)
