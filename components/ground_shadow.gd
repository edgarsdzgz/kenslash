class_name GroundShadow
extends Polygon2D
## A cheap, reusable ground shadow: a soft dark ellipse drawn under an entity at its ground point
## (design-environment.md #3, elevation foundation). The Elevation component keeps it pinned to the
## ground while the body draws up by z; at z=0 (the only case now) it simply sits under the feet.
## Deterministic -- the ellipse is generated from fixed trig at _ready with NO randomness -- so it
## never perturbs a headless run. Drop one under any entity that wants a shadow (the player now;
## enemies / boulders later just add the same node type). Drawn UNDER the body via a negative z_index.
##
## It IS a visual node (meant to render) -- fine, since it lives in hand-authored scenes, NEVER in the
## streamed chunk path whose node count the streaming tests baseline.

## Ellipse half-width in pixels.
@export var radius_x: float = 12.0
## Ellipse half-height in pixels (flattened -- a top-down ground smudge, not a circle).
@export var radius_y: float = 5.0
## Number of ellipse segments. 16 reads as smooth while staying trivially cheap.
@export var segments: int = 16
## Soft dark tint. Low alpha so the ground / meadow reads through it.
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.28)


func _ready() -> void:
	# Draw beneath the body (which sits at z_index 0), build the ellipse once, tint it. No RNG.
	z_index = -1
	color = shadow_color
	polygon = _build_ellipse()


## Generate the ellipse outline as a ring of `segments` points. Pure math, fully deterministic.
func _build_ellipse() -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a) * radius_x, sin(a) * radius_y))
	return pts

# Verified against: Godot 4.7.1 (2026-07-19)
