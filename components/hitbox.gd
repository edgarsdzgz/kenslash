class_name Hitbox
extends Area2D
## Deals a strike. Pure data -- the Hurtbox does the detecting and runs BOTH resolvers
## (one-way discipline, recipes/health-and-damage.md). Carries the two decoupled stat
## sets from design-durability.md: combat (atk) and durability (power/break_threshold/
## wear_max). `durability` points at the WEAPON's wear component when this hitbox is a
## wearable weapon (the player's sword); it stays null for strikes that never wear a
## weapon (the enemy's contact attack).

## System 1 -- HP damage potential. The Hurtbox applies max(0, atk - target.def).
@export var atk: int = 3
## System 2 -- this tool's rating on the shared hardness scale.
@export var power: int = 0
## System 2 -- workable margin above power before the target is "too hard" (Band C).
@export var break_threshold: int = 1
## System 2 -- max durability this strike can cost the weapon in a single hit.
@export var wear_max: int = 0
## System 3 -- this tool's gather category (Harvest.Type), design-durability.md.
## NONE = a pure weapon that cannot harvest anything (whiffs on any resource node).
@export var harvest_type: int = Harvest.Type.NONE
## Knockback impulse (pixels/sec) pushed into whatever this hitbox strikes, directed
## away from the hitbox's position. 0 = no knockback.
@export var knockback: float = 0.0

## The WEAPON's runtime wear, assigned by the owner in code (call-down). Null = this
## strike never wears a weapon (e.g. an enemy's fists), so the Hurtbox skips System 2.
var durability: DurabilityComponent = null

# Verified against: Godot 4.7.1 (2026-07-17)
