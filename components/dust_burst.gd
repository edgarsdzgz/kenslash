class_name DustBurst
extends Node2D
## Kick-off dust puff for the dodge dash (design-controls.md "make the dodge READ as a dash"). A
## one-shot burst that mirrors components/death_burst.gd's self-freeing transient pattern: place it
## at the launch point, call play(), and it spawns a handful of tiny dusty puffs that EXPAND +
## FADE outward, then frees itself. Purely visual -- it carries no data, no physics body, and no
## group the gameplay reads, so it perturbs no combat/streaming state.
##
## Deterministic like the tree wood-burst ring (world/tree.gd _spawn_yield): the puffs fan out on a
## FIXED per-index angle pattern (TAU * i / COUNT), never RNG / wall-clock, so a headless run repeats
## byte-for-byte. Spawned as a WORLD SIBLING of the player (get_parent()) so it stays put and fades
## where it was dropped while the player dashes on.

## Number of puffs -- a small handful (6), fanned to evenly-spaced bearings.
const COUNT: int = 6
## How far each puff drifts from the launch point, in pixels. Small (~0.35 tile) so the burst reads
## as a kick-off scuff at the feet, not a full explosion.
const TRAVEL: float = 14.0
## Seconds for the whole puff (drift + expand + fade). Short so it clears well before the dash
## cooldown, and the leak-watchdog margin in the test comfortably covers it.
const DURATION: float = 0.28
## Base radius of each little puff polygon, in pixels (before the expand scale-up).
const PUFF_RADIUS: float = 3.0
## How much each puff grows over its life (2.2x) so it reads as dust billowing outward as it thins.
const EXPAND: float = 2.2
## Dusty grey/tan tint -- a scuffed-earth kick-off, distinct from the player's blue and the death
## burst's blue. Alpha starts below 1 so it looks like light dust, not a solid pop.
const DUST_COLOR: Color = Color(0.72, 0.66, 0.55, 0.7)


## Spawn a DustBurst as a WORLD SIBLING at `pos` and play it. The one-line trigger Locomotion calls
## at dash start -- mirrors how player.gd spawns a DeathBurst on death (new -> add_child on the world
## -> position -> play), so the burst lives and frees in the world, never under the moving player.
static func burst_at(world: Node, pos: Vector2) -> void:
	if world == null:
		return
	var fx: DustBurst = DustBurst.new()
	world.add_child(fx)
	fx.global_position = pos
	fx.play()


## Spawn the puffs and animate them outward (drift + expand + fade) in parallel, then free self.
## Joins the "dash_dust" group so a test can find + count the transient without it being anything the
## gameplay reads. Awaitable via the tween, matching death_burst.gd's play() shape.
func play() -> void:
	add_to_group("dash_dust")
	var shape: PackedVector2Array = _make_circle(PUFF_RADIUS)
	var tween: Tween = create_tween().set_parallel(true)
	for i in COUNT:
		var dir: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(COUNT))
		var puff: Polygon2D = Polygon2D.new()
		puff.polygon = shape
		puff.color = DUST_COLOR
		add_child(puff)
		tween.tween_property(puff, "position", dir * TRAVEL, DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "scale", Vector2(EXPAND, EXPAND), DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "modulate:a", 0.0, DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	queue_free()


## Build a small filled circle as a polygon (no texture assets needed) -- same helper shape as
## death_burst.gd so the dust reads as the same primitive family.
func _make_circle(r: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var segments: int = 10
	for i in segments:
		pts.append(Vector2.RIGHT.rotated(TAU * float(i) / float(segments)) * r)
	return pts

# Verified against: Godot 4.7.1 (2026-07-19)
