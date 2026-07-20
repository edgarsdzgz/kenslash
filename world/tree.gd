extends HarvestableBody
## A destructible CHOP-only resource node (System 3, design-durability.md). Now a THIN subclass of
## world/harvestable_body.gd: the base owns the shared tech -- the exported hardness/integrity/color
## pushed down in _ready, the component wiring + signal connects, the damage-blink flash, and the
## _spawn_drop() sibling-add. This script authors ONLY what makes a tree a tree: its green wood stats,
## the yield-ON-fell behaviour, and the fall/break animation.
##
## NOTE: no `class_name` here -- `Tree` collides with Godot's own native `Tree` control class ("Class
## 'Tree' hides a native class" parse error), so this is a plain script (referenced by path/node lookup,
## never by type name), per the design task's explicit fallback. It IS-A HarvestableBody all the same.
##
## The CHOP-only gate lives on the Hurtbox's `required_harvest` (checked at the Hurtbox chokepoint,
## Gate 1) -- this script does not re-check tool type itself. No HealthComponent: you FELL it, not ATK it.
## hardness/integrity/color are @export (declared on the base, valued here in _init) so main.tscn can
## author variants by overriding the instance directly.

## Radius (px) of the deterministic ring the felled wood scatters onto. Small (~0.3 tile,
## components/world_scale.gd TILE 40) so the burst reads as landing at the stump.
const _YIELD_RING_RADIUS: float = 12.0

## E2 harvest yield (design-items.md "Harvest yield"): the resource a felled tree drops and how many.
## Data-driven exports so main.tscn AND streamed instances yield with no code edits. A tree yields
## NOTHING per chop -- only felling (integrity 0) bursts this wood.
@export var yield_item: ItemData = preload("res://data/wood.tres")
@export var yield_amount: int = 3

## XP granted to the player for FELLING this tree (plan-epic1-parts.md Part 1.2, harvest-XP hook). A flat
## TUNING constant -- integer, no Time/OS/RNG -- awarded ONCE on fell (integrity 0), unlike the rock's
## per-mine chip. Banked via the base HarvestableBody._award_harvest_xp("player"-group) helper.
const XP_PER_FELL: int = 15


## Author this tree's material stats (the base defaults are generic placeholders): soft green wood the
## axe (power 5) fells with zero wear (Band A).
func _init() -> void:
	hardness = 3
	integrity = 6
	color = Color(0.25, 0.55, 0.25, 1)


func _on_integrity_changed(current: int, max_val: int) -> void:
	# A tree yields NOTHING per chop (unlike the rock's per-hit chip) -- it only bursts wood on fell.
	print("[tree] integrity ", current, "/", max_val)


## Integrity hit 0: the tree is felled -- tip it over, blink as it BREAKS, THEN burst its wood (only
## after it has fallen), lie a beat, and free. Overrides the base's plain queue_free.
func _on_broke() -> void:
	print("[tree] felled")
	# Harvest XP on FELL (Part 1.2): award once at the felling moment (integrity 0), independent of the
	# wood-burst which the fall animation defers -- so a headless test sees the XP the instant it topples.
	_award_harvest_xp(XP_PER_FELL)
	_fall_break_and_free()


## Fell sequence, in order: (1) the trunk tips 90deg to the SIDE, AWAY from the player, pivoting at its
## base (the Body's origin sits at the trunk foot -- the "break" point); (2) it BLINKS -- two quick color
## flashes -- at the moment it comes apart; (3) ONLY THEN does it burst its wood, so the drops appear at
## the stump AFTER the fall, not on the felling hit; (4) it lingers a beat, then frees. The solid body is
## dropped immediately so the player can walk through the falling/downed trunk. Direction: player to our
## LEFT -> fall right (+90deg); to our RIGHT -> fall left; default right. Ease-in so it accelerates like a
## real fall. Runs a tween, so a headless test just waits (watchdog) for the drops / the free.
func _fall_break_and_free() -> void:
	var body_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape != null:
		body_shape.set_deferred("disabled", true)
	var fall_dir: float = 1.0
	# Player to our LEFT -> fall right (+90deg); to our RIGHT -> fall left. Resolved through the shared base
	# _local_player() ("player"-group) helper (Player is-a Node2D, so global_position reads unchanged).
	var p: Player = _local_player()
	if p != null and p.global_position.x > global_position.x:
		fall_dir = -1.0
	var tween: Tween = create_tween()
	# 1) tip over
	tween.tween_property(_body, "rotation", fall_dir * PI / 2.0, 0.55) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 2) break-blink: two quick color flashes as the trunk snaps
	tween.tween_property(_body, "color", HIT_FLASH_COLOR, 0.08)
	tween.tween_property(_body, "color", color, 0.08)
	tween.tween_property(_body, "color", HIT_FLASH_COLOR, 0.08)
	tween.tween_property(_body, "color", color, 0.08)
	# 3) NOW drop the wood -- only after the tree has fallen and broken
	tween.tween_callback(_spawn_yield)
	# 4) lie fallen for a beat, then vanish
	tween.tween_interval(0.15)
	tween.tween_callback(queue_free)


## Burst `yield_amount` count-1 Wood Drops around the stump on fell (E2, design-items.md). Positions are
## DETERMINISTIC -- a fixed ring by index (no RNG, no Time/OS) -- so the headless test can assert exactly
## how many land and where. Each drop is placed by the base _spawn_drop() helper (deferred sibling-add),
## called once per index. Pickup / lifetime / persistence are all E3.
func _spawn_yield() -> void:
	if yield_item == null:
		return
	var origin: Vector2 = global_position
	# Forager talent (HARVEST_YIELD, Part 2.2b): a felled tree bursts MORE wood for a player with the perk.
	# The bonus is resolved through the "player" group (the SAME way the harvest-XP hook resolves it) and
	# added to the base yield_amount; 0 for no/plain player, so the un-talented burst is byte-identical.
	var n: int = maxi(yield_amount + _harvest_yield_bonus(), 1)
	for i in range(n):
		var angle: float = TAU * float(i) / float(n)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * _YIELD_RING_RADIUS
		_spawn_drop(yield_item, origin + offset)

# Verified against: Godot 4.7.1 (2026-07-19)
