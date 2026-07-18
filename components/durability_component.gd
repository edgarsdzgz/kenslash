class_name DurabilityComponent
extends Node
## Runtime wear for whatever it is attached to -- a weapon's edge, a suit of armor,
## or a rock's mining integrity. One node, three roles (design-durability.md). Holds
## only RUNTIME state: current_durability is NEVER written back to a shared resource
## (patterns/resource-driven-design.md -- the sharing trap). Reports via signals so
## the OWNER drives break behavior (weapon disabled / armor -> flesh base / material
## destroyed); this node never reaches up into the scene itself.

## Emitted after every wear() that changes current_durability.
signal durability_changed(current: int, max_val: int)
## Emitted exactly once, the moment current_durability first reaches 0.
signal broke

## Starting and maximum durability.
@export var max_durability: int = 40

var current_durability: int
var _broken: bool = false


func _ready() -> void:
	current_durability = max_durability


## Lose `amount` durability (clamped at 0). Emits durability_changed, and `broke`
## exactly once when it first hits 0. A no-op once already broken or for amount <= 0,
## so a Band C strike (0 wear on the target) never spuriously fires the signal.
func wear(amount: int) -> void:
	if _broken or amount <= 0:
		return
	current_durability = maxi(current_durability - amount, 0)
	durability_changed.emit(current_durability, max_durability)
	if current_durability == 0:
		_broken = true
		broke.emit()


## True once durability has hit 0. The owner gates behavior on this.
func is_broken() -> bool:
	return _broken

# Verified against: Godot 4.7.1 (2026-07-17)
