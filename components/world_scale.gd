class_name WorldScale
## The canonical world grid unit. A pure constant holder (never instantiated,
## like harvest_type.gd) so every future size/distance decision has one shared
## ruler instead of arbitrary per-scene pixel guesses. design-world-scale.md is
## the full spec; this is the one number everything else measures against.

## One grid square, in pixels. Chosen against current content (see
## design-world-scale.md "Current content, measured"): a standard 1-tile-footprint
## object (a rock, the training dummy) lands exactly on 1.0 tile at this size.
const TILE: float = 40.0

## Chunk grid (Milestone C, design-world-streaming.md). A chunk is a square of
## CHUNK_TILES x CHUNK_TILES tiles -- the addressable unit the dormant/active
## streaming split keys on (Minecraft's 16 convention; tunable). CHUNK_PX is the
## pixel span of one chunk edge: 40.0 * 16 = 640.0.
const CHUNK_TILES: int = 16
const CHUNK_PX: float = TILE * CHUNK_TILES

## Which chunk a world position falls in. FLOOR division, correct for NEGATIVE
## coordinates -- the world extends in all directions, so this MUST NOT truncate
## toward zero the way GDScript's integer `%`/`/` does. `floori` floors toward
## negative infinity, so pos (-1,-1) -> chunk (-1,-1) and (-641,0) -> (-2,0), not
## (0,0)/(-1,0). Verified cases: (0,0)->(0,0), (639,639)->(0,0), (640,0)->(1,0),
## (-1,-1)->(-1,-1), (-640,-640)->(-1,-1), (-641,0)->(-2,0).
static func world_to_chunk(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / CHUNK_PX), floori(world_pos.y / CHUNK_PX))


## Top-left world position of a chunk = coord * CHUNK_PX. Inverse-consistent with
## world_to_chunk: world_to_chunk(chunk_origin(c)) == c for every coord.
static func chunk_origin(coord: Vector2i) -> Vector2:
	return Vector2(coord) * CHUNK_PX

# Verified against: Godot 4.7.1 (2026-07-17)
