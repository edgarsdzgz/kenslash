class_name HealthComponent
extends Node
## Owns hit points for whatever entity it is attached to. Knows nothing about
## physics or visuals; reports state changes via signals so UI, feedback, and
## death logic can bind without coupling to this node.

signal damaged(amount: int, current: int)
signal died

## Starting and maximum hit points.
@export var max_health: int = 6

var current_health: int


func _ready() -> void:
	current_health = max_health


## Apply damage. Emits `damaged`, and `died` exactly once when it reaches 0.
func take_damage(amount: int) -> void:
	if current_health <= 0:
		return # Already dead; the guard stops `died` firing twice in one frame.
	current_health = maxi(current_health - amount, 0)
	damaged.emit(amount, current_health)
	if current_health == 0:
		died.emit()


func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)


## Reset to full HP so the entity can live -- and die -- again. Used by the player's
## respawn-in-place path (design-playable-loop.md D1). A plain reset: it emits NOTHING,
## leaving the `damaged`/`died` semantics unchanged (a later 0 re-fires `died`).
func revive() -> void:
	current_health = max_health

# Verified against: Godot 4.7.1 (2026-07-17)
