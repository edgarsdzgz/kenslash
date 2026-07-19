class_name RegionTrigger
extends Area2D
## One demo/proof INSIDE region (design-environment.md #3, inside/outside foundation). An Area2D that
## detects the player's body entering / leaving and flips the player's Region flag INSIDE / OUTSIDE --
## the seam a future cave / building uses to trigger roof-fade / lighting / music (NONE built now). It
## masks the player_body layer (2) and monitors, so `body_entered` / `body_exited` fire for the player
## CharacterBody2D; it BLOCKS nothing (an Area2D never stops a body). Any body in the "player" group
## with a set_region(bool) method is flipped, so it works for the shipped player unchanged.


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## The player's body entered this region -> mark it INSIDE.
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("set_region"):
		body.set_region(true)


## The player's body left this region -> mark it OUTSIDE.
func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("set_region"):
		body.set_region(false)

# Verified against: Godot 4.7.1 (2026-07-19)
