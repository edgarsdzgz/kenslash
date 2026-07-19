# Environment: Meadow Ground + Terrain Obstacles + Elevation Foundation -- Design + Research (2026-07-19)

Three interlocking world systems (user request). Research-grounded; build AFTER the forks are set.
Elevation is FOUNDATION-ONLY now (no real floors yet), built so floors + isometric are ADDITIVE later.

## Research -- how 2D / isometric games solve these
- **Fake height in 2D**: give an entity a `z` (height off ground) and DRAW it at screen `(x, y - z)`
  with a **ground shadow** at `(x, y)`; collisions compare `z`+height overlap so things at different
  heights pass. The canonical "fake z-axis"; scales to jumping AND stacked floors. (The Waking Cloak
  devblog; Godot forums.)
- **Meadow ground**: a single flat tile is monotonous. Use **low-frequency Perlin/value noise** for
  large smooth color variation, a secondary tint blended via noise, a faint noise overlay to kill grid
  repetition, and scattered **detail variants** (flowers/dirt/tufts). A **noise shader** is the cheap,
  best-looking route. (SLYNYRD pixelblog; Godot Shaders grass-soil shader.)
- **Inside/outside + roofs**: mark **interior regions/tiles**, hide/fade the **roof** for those; a
  **trigger (Area2D)** or a vertical raycast detects entry. Inside/outside is a **region flag** that
  later swaps roof-fade / lighting / music. (GameDev.net; Unreal/Roblox forums.)

## 1. Meadow biome ground (the gray -> a meadow)
- Per-chunk ground layer that reads as grass, not flat gray.
- RECOMMEND a **ground shader** on a chunk-sized ColorRect: low-frequency value noise of WORLD coords
  blends a **meadow palette** (a few greens + sparse dirt/flower accents), deterministic, per-pixel,
  ZERO extra nodes, culled with the chunk. Alt (no shader): scattered green **splotch polygons** over a
  base green (coarser, more nodes).
- Palette to source (tunable): base green ~`#5c8a4a`, light ~`#6fa055`, dark ~`#4a6f3a`, dirt ~`#7a6a4f`,
  flower accents (white/pale-yellow) sparse.
- Streaming: deterministic from world position; no per-frame cost.

## 2. Large unmineable rock terrain (obstacles)
- New **Boulder** entity: a large **StaticBody2D** (solid, blocks movement), UNMINEABLE (no Hurtbox, or a
  never-affected hardness), in sizes rock -> hill -> mountain. Walk-around obstacles that **divide areas**,
  (later) **block vision** (a line-of-sight / fog pass is FUTURE), and are the **foundation for caves** (a
  formation gains an interior region, #3).
- Streamed as chunk content (a new `Kind.BOULDER` or a boulder variant), DETERMINISTIC -- derive
  placement without shifting the existing generator rng ORDER (draw last like bush/pebble, or from a
  hash), so TREE/MINERAL/ENEMY/BUSH/PEBBLE counts stay identical. Y-sorted so the player passes behind
  tall ones.

## 3. Inside/outside + height/elevation FOUNDATION (isometric-ready)
- **Elevation**: adopt the fake-z convention -- entities carry a `z`/elevation (0 = ground now); visual
  drawn offset up by z + a **ground shadow**; depth-sort by `(world_y + z bias)`. Supports jumping AND
  stacked floors later. [FORK below: continuous float z vs discrete int floors vs hybrid.]
- **Inside/outside**: a **region** the player carries (OUTSIDE by default); entering a cave/building
  **trigger (Area2D)** sets INSIDE -- foundation for later roof-fade / lighting / music. Ties into #2.
- **Isometric-ready**: keep a clean split of **logical world position** from **screen projection** so an
  iso projection swaps in later; the depth-sort already accounts for elevation.
- Build NOW (minimal): the z/elevation field + shadow + elevation-aware depth-sort hook, and the
  inside/outside region flag + one trigger. NOT real multi-floor content.

## Forks -- DECIDED (2026-07-19, user)
- **Biome technique = NOISE SHADER** (over splotch-polygons / per-tile grid). A shader on a chunk-sized
  ColorRect samples low-frequency noise of world coords to blend the meadow palette + sparse accents.
- **Elevation model = CONTINUOUS FLOAT z + ground shadow** (over discrete floors / hybrid). Each entity
  carries a float `z` height; drawn at `y - z` with a ground shadow; depth-sort by `y + z`. Foundation
  only now (everything at z=0); supports smooth jumps AND stacked floors additively later.

## Phasing (each headless-verified)
1. Meadow ground -- lowest risk, big visual win.
2. Boulder terrain obstacles -- solid unmineable rocks, streamed, y-sorted.
3. Elevation + inside/outside FOUNDATION -- z field + shadow + elevation-aware sort + region flag + trigger.

## Sources
- The Waking Cloak -- Z-Height: how it's done (draw at x, y-z + shadow + z-overlap collision).
- SLYNYRD Pixelblog 20 -- Top Down Tiles (variation, negative space, blending).
- Godot Shaders -- Grass & Soil tileable-texture + noise shader.
- GameDev.net / Unreal / Roblox dev forums -- roof show/hide by interior region + trigger/raycast.

*Verified against: Godot 4.7.1. Last updated: 2026-07-19*
