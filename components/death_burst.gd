class_name DeathBurst
extends Node2D
## A one-shot "pop into little circles" effect. Place it at a world position and
## call play(): it spawns `count` circles at the center that fly outward to
## evenly-spaced directions while fading, then frees itself and emits `finished`.
##
## process_mode = ALWAYS so it keeps animating while the SceneTree is paused --
## that lets a death sequence "stop" the level and still show the burst.

signal finished

## Number of circles / directions. 8 gives the four cardinals + four diagonals.
@export var count: int = 8
## How far each circle travels from the center, in pixels.
@export var travel: float = 44.0
## Seconds for the whole burst.
@export var duration: float = 0.45
## Radius of each little circle, in pixels.
@export var circle_radius: float = 5.0
## Circle color. Defaults to the player's blue.
@export var color: Color = Color(0.35, 0.7, 1.0)


func _ready() -> void:
	# Keep animating even when get_tree().paused is true.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Spawn the circles and animate them outward. Awaitable via the `finished` signal.
func play() -> void:
	var shape: PackedVector2Array = _make_circle(circle_radius)
	# Parallel so all circles animate at once; the node owns the tween, and
	# because this node is PROCESS_MODE_ALWAYS the tween runs during a pause.
	var tween: Tween = create_tween().set_parallel(true)
	for i in count:
		var dir: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(count))
		var circle: Polygon2D = Polygon2D.new()
		circle.polygon = shape
		circle.color = color
		add_child(circle)
		tween.tween_property(circle, "position", dir * travel, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(circle, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	finished.emit()
	queue_free()


## Build a small filled circle as a polygon (no texture assets needed).
func _make_circle(r: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var segments: int = 12
	for i in segments:
		pts.append(Vector2.RIGHT.rotated(TAU * float(i) / float(segments)) * r)
	return pts

# Verified against: Godot 4.7.1 (2026-07-17)
