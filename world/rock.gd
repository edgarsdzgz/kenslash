class_name Rock
extends HarvestableBody
## A destructible MINING target (design-durability.md). Now a THIN subclass of world/harvestable_body.gd:
## the base owns the shared tech -- the exported hardness/integrity/color pushed down in _ready, the
## component wiring + signal connects, the damage-blink flash, and the _spawn_drop() sibling-add. This
## script authors ONLY what makes a rock a rock: its gray stone stats, and the yield-PER-hit behaviour
## (a chip of stone drops on every AFFECTING mine, driven off durability_changed).
##
## No HealthComponent -- you MINE it, not ATK it. A tool wears against `hardness` every hit, but integrity
## only drops when the hit AFFECTS the target (Band A/B); a too-hard rock (Band C) wears the tool yet
## never chips -- durability_changed never fires, so no stone drops and the "need a stronger tool" gate
## falls out for free. Destroyed (queue_free, the base default _on_broke) at 0 integrity.
##
## hardness/integrity/color are @export (declared on the base, valued here in _init) so main.tscn can
## author a soft rock vs an obsidian rock by overriding the instance directly, and the streamer sets
## rock.integrity/hardness per entry -- both override these defaults after construction.

## Deterministic tiny offset (px) a mined stone drops at, just above the rock so it reads as chipping
## off. Fixed (no RNG) for a reproducible headless assertion.
const _YIELD_OFFSET: Vector2 = Vector2(0, -10)

## E2 harvest yield (design-items.md "Harvest yield"): the resource this rock drops PER affecting mine.
## Data-driven export so main.tscn AND streamed instances yield with no code edits. A mineral gives ONE
## stone per successful pick (a tree, by contrast, yields on fell).
@export var yield_item: ItemData = preload("res://data/stone.tres")

## XP granted to the player PER affecting mine (plan-epic1-parts.md Part 1.2, harvest-XP hook). A flat
## TUNING constant -- integer, no Time/OS/RNG -- awarded on every chip (each durability_changed, the
## mine-to-0 included), mirroring the per-hit stone yield. Banked via HarvestableBody._award_harvest_xp.
const XP_PER_MINE: int = 5


## Author this rock's material stats (the base defaults are generic placeholders): a soft gray stone.
func _init() -> void:
	hardness = 6
	integrity = 4
	color = Color(0.5, 0.5, 0.55, 1)


func _on_integrity_changed(current: int, max_val: int) -> void:
	print("[rock] integrity ", current, "/", max_val)
	# Drop ONE Stone per AFFECTING mine: durability_changed fires once per hit that reduces integrity
	# (the mine-to-0 one INCLUDED), so each pick chips its stone here -- NOT in _on_broke (that would
	# double the last stone). A Band-C whiff never reduces integrity, so no stone drops.
	_spawn_drop(yield_item, global_position + _YIELD_OFFSET)
	# Harvest XP PER affecting mine (Part 1.2): fires alongside each stone chip. This hook only runs on an
	# affecting hit, so a Band-C whiff -- which never reaches here -- correctly grants no XP either.
	_award_harvest_xp(XP_PER_MINE)


## Integrity hit 0: the rock is mined out. The stone for THIS final pick was already spawned by
## _on_integrity_changed (durability_changed fires on the mine-to-0 hit too), so we do NOT spawn here --
## that would double the last stone. Just remove it (print, then the base's queue_free).
func _on_broke() -> void:
	print("[rock] mined out -- destroyed")
	queue_free()

# Verified against: Godot 4.7.1 (2026-07-19)
