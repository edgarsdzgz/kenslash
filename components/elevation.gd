class_name Elevation
extends RefCounted
## Elevation FOUNDATION (design-environment.md #3, DECIDED fork: continuous float z + ground shadow).
## Gives an entity a height `z` off the ground -- 0.0 = on the ground (the only value now) -- that
## affects ONLY how it is DRAWN and DEPTH-SORTED, never its logical world position. That split is
## deliberately isometric-ready: the real position stays where the scene put it, so a screen
## projection can swap in later without moving anything. RefCounted, NOT a Node, exactly like
## components/combat.gd and the other subsystems, so it never perturbs the streaming node-count /
## orphan baselines (the ground SHADOW it pins IS a node, but authored in the scene, not spawned here).
##
## FOUNDATION ONLY: everything is z=0 today, so the body offset is zero and `y + z == y` -- behaviour
## is byte-identical to before. Real jumps / stacked floors / an isometric projection are purely
## ADDITIVE on top: raise z and the body draws UP (screen y - z) while the shadow stays on the ground,
## and the depth key already accounts for elevation.

## Height off the ground in pixels. 0.0 = on the ground (the only value now). Never negative.
var z: float = 0.0
## The entity's visual body (Polygon2D / Node2D): drawn offset UP by z (screen y - z). Read + written.
var _visual: Node2D = null
## The ground shadow node (a GroundShadow), PINNED to the real ground point regardless of z.
var _shadow: Node2D = null
## The visual's authored local y, captured at setup so set_z offsets relative to it (z=0 -> unchanged).
var _base_visual_y: float = 0.0
## The shadow's authored local position, captured so it can be re-pinned to the ground as z varies.
var _base_shadow_pos: Vector2 = Vector2.ZERO


## Depth-sort key: order by (world_y + z bias) rather than plain y, so an elevated entity sorts
## correctly against ground content (design-environment.md #3). Standalone + static so streamed
## content (world/boulder.gd and future chunk content) can call it WITHOUT holding an instance --
## e.g. Elevation.depth_sort_key(global_position.y, 0.0). At z=0 this is just world_y (unchanged).
static func depth_sort_key(world_y: float, height: float) -> float:
	return world_y + height


## Wire the entity's visual body + its ground shadow (the owner "calls down" in _ready). Captures the
## authored poses, then applies the z=0 pose so the shadow sits at the ground point immediately.
func setup(visual: Node2D, shadow: Node2D) -> void:
	_visual = visual
	_shadow = shadow
	if _visual != null:
		_base_visual_y = _visual.position.y
	if _shadow != null:
		_base_shadow_pos = _shadow.position
	apply()


## Set the elevation and re-apply the draw offset. Clamped at 0 (no sub-ground). Real jumps will drive
## this each frame later; today only a test drives it, to prove the hook is additive.
func set_z(value: float) -> void:
	z = maxf(0.0, value)
	apply()


## Redraw for the current z: offset the body UP by z (y - z) while the shadow stays pinned to the
## ground point. At z=0 the body returns to its authored y and nothing moves -- the foundation contract.
func apply() -> void:
	if _visual != null:
		_visual.position.y = _base_visual_y - z
	if _shadow != null:
		_shadow.position = _base_shadow_pos


## This entity's depth key at a given world y (instance convenience over the static utility).
func depth_key(world_y: float) -> float:
	return depth_sort_key(world_y, z)

# Verified against: Godot 4.7.1 (2026-07-19)
