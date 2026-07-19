class_name Boulder
extends StaticBody2D
## A large UNMINEABLE rock-terrain obstacle (design-environment.md #2 "Large unmineable rock terrain").
## The counterpart to the mineable Rock (world/rock.gd): where a Rock is a HarvestableBody you strike
## with a pickaxe until it yields stone and breaks, a Boulder is permanent TERRAIN -- a big solid mass
## that BLOCKS movement, DIVIDES areas, and is the future foundation for caves (a formation later gains
## an interior region, design-environment.md #3). It is UNMINEABLE by CONSTRUCTION: it has NO Hurtbox on
## the `harvestable` layer, NO HealthComponent, NO DurabilityComponent, and NO drops -- a pick/axe swing
## overlaps nothing, so there is literally no chokepoint through which damage could route. Nothing here
## can ever reduce, yield, or free it; it just stands.
##
## SOLID: the root StaticBody2D sits on the `world` collision layer (bit 1, mask 0), the same layer the
## Rock/Tree bodies use, so the player body (mask 5 = world+enemy_body) and enemy bodies (mask 3 =
## world+player_body) bump into it. Its HEIGHT is visual + collision BULK, not elevation off the ground
## (components/elevation.gd is a separate concern) -- a boulder rests AT z=0; the bigger sizes are simply
## taller silhouettes over a wider footprint.
##
## SIZES (rock -> hill -> mountain): an authorable `size` enum. Bigger = a taller visual rising from the
## base AND a larger solid footprint. The scene (world/boulder.tscn) carries placeholder Body + Collision
## children; _ready() rebuilds both from the per-size table below, so a streamed instance is configured by
## setting `size` BEFORE add_child (the same pattern rock.gd uses for integrity/hardness).
##
## Y-SORT: the node's origin sits at the boulder's FOOT (the south edge of the footprint), and the Body
## polygon rises UPWARD from there (negative y). Godot's built-in y-sort (enabled up the chunk container
## chain, world/streaming_world.tscn + chunk_manager.gd) orders siblings by node position.y, so a player
## standing ABOVE (smaller y) a tall boulder draws BEHIND its silhouette while one below draws in front --
## exactly the foot-anchored convention Elevation.depth_sort_key encodes at z=0 (y + 0 == y). No shadow
## node is spawned: that is the elevation foundation's device for a body drawn UP by z>0, which a
## ground-resting boulder is not (a documented judgment call -- keeps the streamed subtree minimal too).
##
## Deterministic: the visual + collision are pure math from `size`, with NO RNG / Time / OS input, so a
## streamed boulder reproduces byte-identically on every unload/reload.

## Authorable coarse sizes. Bigger = taller visual + wider solid footprint. NEVER renumber -- the value
## rides in a ChunkData entry's state and persists to disk later (same rule as ChunkData's enums).
enum Size { ROCK, HILL, MOUNTAIN }

## Which size this boulder is. Set on the scene (an authored instance) OR by the streamer BEFORE add_child
## (ChunkContent.spawn), read once in _ready to build the matching silhouette + footprint.
@export var size: Size = Size.ROCK

@onready var _body: Polygon2D = $Body
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Build the solid footprint + the visual silhouette for this size. Children exist in the scene as
	# placeholders; overwrite them from the per-size table so one scene serves rock/hill/mountain.
	var foot: Vector2 = _footprint(size)
	var height: float = _visual_height(size)

	# Collision footprint: a fresh RectangleShape2D per instance (never share a mutated resource across
	# boulders). Origin is at the FOOT (south edge), so offset the rect UP by half its depth -- its base
	# then sits exactly at the sort-anchor y, matching the Body silhouette that rises from the same base.
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = foot
	_shape.shape = rect
	_shape.position = Vector2(0.0, -foot.y * 0.5)

	# Visual: a stone silhouette rising from the base (y ~ 0) up to the peak (y = -height). Tinted a
	# little darker at bigger sizes so a mountain reads as a heavier mass than a rock, purely cosmetic.
	_body.polygon = _silhouette(foot.x * 0.5, height)
	_body.color = _tint(size)


## The solid footprint (width, depth in px) for a size. Bigger sizes take up more ground; the depth is
## the north-south extent of the collision rect (its south edge pinned to the foot in _ready).
static func _footprint(s: Size) -> Vector2:
	match s:
		Size.HILL:
			return Vector2(110.0, 68.0)
		Size.MOUNTAIN:
			return Vector2(178.0, 112.0)
		_:
			return Vector2(56.0, 34.0)   # ROCK (default / smallest)


## How tall the visual silhouette rises above the base (px) for a size. Bigger = taller -- the reason a
## player passes BEHIND a mountain but barely behind a rock once the foot-anchored y-sort is in play.
static func _visual_height(s: Size) -> float:
	match s:
		Size.HILL:
			return 116.0
		Size.MOUNTAIN:
			return 196.0
		_:
			return 54.0   # ROCK


## The fill tint for a size -- gray stone, a touch darker/cooler as the mass grows so the three read as
## rock < hill < mountain at a glance. Cosmetic only; nothing gameplay depends on it.
static func _tint(s: Size) -> Color:
	match s:
		Size.HILL:
			return Color(0.42, 0.42, 0.47, 1.0)
		Size.MOUNTAIN:
			return Color(0.37, 0.38, 0.43, 1.0)
		_:
			return Color(0.47, 0.47, 0.51, 1.0)   # ROCK


## Build a rounded rock silhouette as a ring of points: a peak at top-center, widest around a quarter of
## the way up, narrowing to the base at y ~ 0. Pure trig-free math from the base half-width + height (NO
## RNG), so it is fully deterministic and the same for every instance of a size. Winding is irrelevant to
## Polygon2D fill. `hw_base` is half the footprint width; the top shoulders pull in so the mass tapers.
static func _silhouette(hw_base: float, height: float) -> PackedVector2Array:
	var hw_top: float = hw_base * 0.32
	return PackedVector2Array([
		Vector2(0.0, -height),                 # peak
		Vector2(hw_top, -height * 0.70),       # right shoulder
		Vector2(hw_base, -height * 0.24),      # right bulge (widest)
		Vector2(hw_base * 0.55, 0.0),          # right foot
		Vector2(-hw_base * 0.55, 0.0),         # left foot
		Vector2(-hw_base, -height * 0.24),     # left bulge
		Vector2(-hw_top, -height * 0.70),      # left shoulder
	])

# Verified against: Godot 4.7.1 (2026-07-19)
