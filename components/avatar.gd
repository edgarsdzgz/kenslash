class_name Avatar
extends RefCounted
## Four-facing avatar for the player AND the enemy (a "sprite with four faces"). Both
## entities share ONE body-facing rule, so this ONE component owns it and each owner just
## "calls down" into update() each frame -- exactly the RefCounted + call-down pattern of
## components/equipment.gd, components/interaction.gd and components/pickup.gd.
##
## The FOUR looks, keyed off the owner's facing direction:
##   * LEFT / RIGHT (horizontal): the authored sideways "D-shape" Body, left/right flipped
##     by scale.x = +/-1 -- the ORIGINAL, unchanged behavior. No face (a profile has none here).
##   * UP (facing away from the viewer): a plain RECTANGLE Body, no face -- we see its back.
##   * DOWN (facing the viewer): the same RECTANGLE Body PLUS a small circle "face" in the
##     upper half, so it reads as looking out at the screen.
##
## RefCounted, NOT a Node: adding an Avatar Node under the player/enemy would bump the global
## Performance.OBJECT_NODE_COUNT that the streaming zero-orphan-leak assertion prints as a
## live baseline -- the SAME reason equipment/interaction/pickup are RefCounted. As a plain
## RefCounted it is invisible to the node monitors, so the four-facing look perturbs no
## streaming node-count anchor. The ONLY new scene nodes are the `Face` Polygon2D children of
## each Body (player.tscn / enemy.tscn / dummy.tscn -- dummy.tscn also runs enemy.gd).
##
## "Call down" wiring (patterns/scene-composition.md): the owner passes its Body + Face
## Polygon2D into setup(); this object writes polygon/scale/visibility onto them but never
## reaches up into the owner. The Face is authored as a CHILD OF the Body, so it inherits the
## Body's visibility (the i-frame blink hides Body -> hides Face) and modulate (the hit-flash /
## white-out tints ride onto the face for free), and is never mis-flipped: the face only shows
## while facing DOWN, where scale.x = 1.0 (no horizontal mirror).

## The authored sideways "D-shape" (the LEFT/RIGHT profile), captured verbatim from the Body's
## scene polygon in setup(). Restored whenever facing horizontal, so a return from up/down puts
## the original silhouette back. Public so a test can assert the Body flipped back to it.
var side_shape: PackedVector2Array = PackedVector2Array()
## The UP/DOWN plain RECTANGLE, built from the AXIS-ALIGNED BOUNDING BOX of side_shape (min/max
## x and y of the D-shape's points). For the player/enemy body (x[-10,10] y[-36,4]) this is
## exactly [(-10,-36),(10,-36),(10,4),(-10,4)]; deriving it from the bbox means a bigger body
## (the training dummy's 2x D-shape) automatically gets its own correctly-sized rectangle.
## Public so a test can assert the Body switched to it when facing vertical.
var vert_shape: PackedVector2Array = PackedVector2Array()

## The Body Polygon2D whose `polygon` and `scale.x` this component drives.
var _body: Polygon2D = null
## The small circular "face" Polygon2D (a child of _body), shown ONLY when facing DOWN.
var _face: Polygon2D = null


## Wire the Body + Face the owner "calls down" (in its _ready), capture the authored D-shape as
## the horizontal `side_shape`, derive the vertical `vert_shape` rectangle from that shape's
## bounding box, and hide the face until update() first shows it. Reproduces the pre-feature
## start pose exactly: Body holds its authored D-shape, no face.
func setup(body: Polygon2D, face: Polygon2D) -> void:
	_body = body
	_face = face
	side_shape = body.polygon
	vert_shape = _rect_from_bbox(side_shape)
	_face.visible = false


## Advance the look one frame from the owner's facing + side (called each physics frame by the
## owner, replacing the old lone `_body.scale.x = float(side)` line). Three states:
##   * Horizontal (|x| >= |y|, incl. a tie / zero facing -- harmless): the D-shape, left/right
##     flipped by scale.x = side (+1/-1). UNCHANGED from the original behavior. No face.
##   * Vertical UP (y < 0): the rectangle, scale.x = 1 (no flip -- a back has no left/right), no face.
##   * Vertical DOWN (y > 0): the rectangle, scale.x = 1, face SHOWN (looking at the viewer).
func update(facing: Vector2, side: int) -> void:
	if absf(facing.x) >= absf(facing.y):
		_body.polygon = side_shape
		_body.scale.x = float(side)
		_face.visible = false
	elif facing.y < 0.0:
		_body.polygon = vert_shape
		_body.scale.x = 1.0
		_face.visible = false
	else:
		_body.polygon = vert_shape
		_body.scale.x = 1.0
		_face.visible = true


## Build the axis-aligned bounding-box rectangle of a polygon: min/max x and y over its points,
## wound as four corners [(minx,miny),(maxx,miny),(maxx,maxy),(minx,maxy)]. An empty input
## yields an empty rectangle (the owner always passes a populated Body polygon).
func _rect_from_bbox(shape: PackedVector2Array) -> PackedVector2Array:
	if shape.is_empty():
		return PackedVector2Array()
	var min_x: float = shape[0].x
	var max_x: float = shape[0].x
	var min_y: float = shape[0].y
	var max_y: float = shape[0].y
	for p in shape:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	return PackedVector2Array([
		Vector2(min_x, min_y), Vector2(max_x, min_y),
		Vector2(max_x, max_y), Vector2(min_x, max_y),
	])

# Verified against: Godot 4.7.1 (2026-07-18)
