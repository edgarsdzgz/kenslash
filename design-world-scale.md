# World Scale & Height Classes -- Design

Decided 2026-07-17. Answers "how big is a rock before it's tall" with a shared
ruler, and formalizes the base-anchored-canopy pattern already built for the tree
(see design-durability.md "Tree depth illusion (Y-sort)") into a reusable rule for
all future content -- bushes, boulders, other players, structures.

## The grid unit

`WorldScale.TILE = 40.0` px (`components/world_scale.gd`). One square. Chosen by
checking it against content already built (see the measured table below) -- a
standard 1-tile-footprint object (a rock, the training dummy) lands exactly on 1.0
tile at this size, so "1 tile" reads as a concrete, checkable claim, not a vibe.

This does NOT change how depth sorting works -- Y-sort (design-durability.md) already
sorts continuously by pixel `global_position.y`, which is a strict generalization of
the user's "y=0 background / y=1 foreground / y=3 background again" example: replace
"row number" with "Y position within that row," and it already behaves exactly as
described, smoothly, not just at integer rows. The grid's job is AUTHORING and
CLASSIFICATION -- a shared unit to size and describe content by -- not making Y-sort
function (that already works, verified).

## Height classes

Two classes, decided by comparing an object's VISUAL height (not its collision size)
to one tile:

- **SHORT** (visual height <= ~1 tile): collision footprint ~= visual footprint. A
  flat obstacle -- things bump into it, full stop. No base/canopy split; no walk-behind
  illusion, because there is no meaningful "upper part" to walk behind. Living
  creatures (player, enemies, future other players) are always SHORT in this genre's
  convention -- characters do not partially occlude each other by height in a top-down
  game; two creatures at the same spot COLLIDE (already built: "solid bodies" behavior
  from the durability slice). Rocks/bushes/small props: SHORT.
- **TALL** (visual height > ~1 tile, typically ~2): the base-anchored pattern. The
  node's origin sits at the BASE (ground contact), a SMALL collision shape at that
  origin blocks movement (roughly footprint-sized, NOT the full visual height), and
  the visual extends upward (negative local Y) through the additional tile(s) above.
  Y-sort (using that same base-point origin) then naturally shows other entities
  passing behind the upper portion when their sort-Y places them "further back."
  Trees are TALL. Later: large rock formations, statues, structures.

The threshold is "does this thing have an upper part worth walking behind," not an
exact pixel cutoff -- judgment call per asset, not a rigid formula.

## Current content, measured (TILE = 40)

| Object | Collision diameter/width | Tiles | Visual height | Tiles | Class |
|--------|--------------------------|-------|----------------|-------|-------|
| Player body | 24 px (r12) | 0.6 | ~24 (D-shape, roughly circular) | 0.6 | SHORT |
| Enemy (chaser) body | 28 px (r14) | 0.7 | ~28 | 0.7 | SHORT |
| Rock (either variant) | ~40 px wide (hexagon) | **1.0** | ~40 (same, no split) | 1.0 | SHORT |
| Tree | 14x14 trunk footprint | 0.35 | 80 px total | **2.0** | TALL |
| Dummy | 24 px footprint (r12) | 0.6 | 80 px total | **2.0** | TALL (reclassified) |

Every current object is now explicitly classified -- nothing left ambiguous. Player,
the chasing Enemy, and both Rock variants are SHORT (collision ~= visual, plain
bump obstacles; this is a deliberate judgment call, not a strict formula -- see
below). Tree and Dummy are TALL (walk-behind).

### Dummy reclassified TALL, 2026-07-17 -- applied + verified

Originally measured SHORT (its old body was a symmetric D-shape, circumradius 20 =
exactly 1.0 tile, centered on the origin like the player/enemy). Playtesting judgment
call: it reads as bigger/taller than that and should support walk-behind -- exactly
the kind of per-object call the height-class threshold is meant to be (a guideline,
not a rigid cutoff). Confirms the TALL recipe is UNIVERSAL, not tree-specific: any
object can be promoted to TALL the same way.

Precondition checked before touching it: does this object's body ROTATE? The
rotating D-shape (player, the chasing Enemy) pivots around its geometric CENTER to
face a direction -- re-anchoring THAT to its base would make it visibly swing/orbit
around an off-center point when rotating, which looks wrong. The Dummy is safe
because `stationary = true` returns before `enemy.gd`'s
`_body.rotation = _facing.angle()` line -- it never rotates. Any FUTURE stationary
or non-rotating tall object is a safe base-anchor candidate the same way; a rotating
one needs a different treatment (not attempted yet -- no current object needs it).

Applied (same zero-risk pattern as the tree -- only the BODY CollisionShape2D and
the Body Polygon2D changed, the Hurtbox -- the single most heavily tested node in
the whole suite, every armor/durability-band leg targets it -- was left completely
untouched): body CollisionShape2D radius 20 -> 12 (a small base footprint, on par
with the player's own 12px radius); Body polygon is the same D-shape family,
vertically stretched 2x and shifted so its span changed from symmetric
`[-20, 20]` (40px, center-anchored) to base-anchored `[-76, 4]` (80px = 2.0 tiles,
transform `new_y = 2*old_y - 36`, x unchanged) -- same construction technique as the
tree, applied to a different silhouette family. Verified: 52/52 smoke assertions
unchanged, exit 0, clean live boot.

Sword blade reach (~39 px, offset 24 + half-length 15) ~= 1.0 tile -- a useful
intuition: melee reach is "about one square." Detection range 180 = 4.5 tiles,
attack range 34 ~= 0.85 tiles.

## Retrofit applied 2026-07-17 (zero risk)

Tree Body visual bumped from 54 px total (1.35 tiles, an approximate "almost tall")
to exactly 80 px (`-76..+4` local Y) = 2.0 tiles, so "trees are 2 tiles tall" is a
literally true claim, not an approximation. The tree's Hurtbox (combat/harvest reach,
40x40) is UNTOUCHED -- same reasoning as the original Y-sort change: only the visual
+ the body-blocking CollisionShape2D (already a small 14x14 trunk footprint) are
affected, so the tool-category test suite needed zero changes.

Player/enemy/dummy/rock sizes were NOT force-retrofitted to land on cleaner
fractions -- the meaningful threshold is "under 1 tile = SHORT," which all four
already satisfy comfortably; forcing exact fractions there has no behavioral payoff.

## Deliberately deferred (not built now)

- **Retrofitting existing numeric literals to reference `WorldScale.TILE`
  symbolically** (e.g. `detection_range: float = WorldScale.TILE * 4.5`). The
  numbers would be unchanged either way -- pure source-readability churn across many
  already-tuned files for no behavioral gain. `WorldScale.TILE` exists now so NEW
  content can size against it going forward; old content is not being rewritten to
  match.
- **Grid-snapped (quantized) depth sorting.** Some tile games snap Y-sort to whole
  grid rows for a cleaner "this row is always in front of that row" feel, avoiding
  pixel-level near-ties. Not needed now -- continuous pixel Y-sort already satisfies
  the requested behavior and is simpler. Revisit only if near-tie flicker is ever
  actually observed.
- **Real `TileMapLayer`-based level authoring.** This doc's grid is a measurement
  convention for hand-placed content; an actual tile-grid-snapped level (per
  `2d/tilemaps.md`) is the open-world/streaming milestone's job, not this slice's.
  Worth building on the SAME `WorldScale.TILE` value when that milestone arrives, so
  chunk sizes are natural tile multiples.

## WxH respec, 2026-07-17 -- applied + verified

Explicit target sizes: Dummy 2x2 (80x80), Player + chasing Enemy 1x2 (40x80 max
bounds), Tree 1x4 (40x160 max bounds). All base-anchored per the TALL recipe.

Interpretation decision (stated plainly, not silent): WxH describes the VISUAL
bounding footprint used for Y-sort/classification, not a literal instruction to
resize combat/physical collision to fill the stated tile dimensions. Existing
Hurtbox and body-collision shapes were left at their separately-tuned gameplay
values -- all already comfortably within the stated bounds (player/enemy collision
radii well under 1 tile; tree trunk 14x14 well under 1 tile). The one exception:
Dummy's body-collision widened 12->20 radius, reflecting its now-explicit "2 wide"
chunkiness (also reverting to its original pre-any-edit value, a proven-safe
number). If literal full-tile collision is wanted instead, that is a deliberate
second pass, not this one.

**The real design problem this respec surfaced**: Player and the chasing Enemy are
now 1x2 (non-square, taller than wide) -- but their Body previously ROTATED as a
whole to face movement direction (the D-shape convention). Rotating a non-square
tall body around its center makes it visually lay sideways when facing east/west,
destroying the fixed footprint. Resolved by SEPARATING the concerns:
- **Body**: fixed orientation, never rotates. A base-anchored, vertically-stretched
  version of the same D-shape family (same construction as the Dummy/Tree
  technique -- linear transform on the original polygon's Y coordinates, X
  unchanged for Player/Enemy since only height needed to reach 2 tiles; Dummy
  needed BOTH axes scaled 2x since its target is a full 2x2 square).
- **FacingMarker** (NEW): a small dark wedge/arrow, a Polygon2D sibling of Body at
  a fixed local point `(0, -36)` (the vertical middle of the 2-tile body), whose
  `rotation` is set to `facing.angle()` every tick -- replacing the old
  `_body.rotation = facing.angle()` line entirely. Reads like a small compass
  needle mounted mid-body; keeps the "always readable facing" property (still the
  foundation for a future vision cone) without the whole-body rotation problem.
- Added to EVERY `enemy.gd` scene, including the stationary Dummy, even though the
  Dummy never rotates it (its `stationary` branch returns before that line) --
  `@onready` resolves the node reference regardless of runtime code path, so the
  node must exist in the scene or the Dummy would fail to instantiate.
- This is now the STANDARD facing convention for any future rotating TALL entity:
  fixed body, separate rotating marker. A SHORT (roughly-square) entity could still
  get away with whole-body rotation if one is ever built that way, but nothing
  current does.

Exact transforms used (all target base-anchored span `[-76, 4]` = 80px = 2 tiles for
the 1x2 entities; Dummy scaled both axes 2x for the full 2x2):
- Player (original circumradius 12): `new_y = old_y * (10/3) - 36`, x unchanged.
- Enemy (original circumradius 14): `new_y = old_y * (20/7) - 36`, x unchanged.
- Dummy (original circumradius 20): `new_x = old_x * 2`, `new_y = old_y * 2 - 36`.
- Tree: width unchanged (16px), height extended from 80px (2 tiles) to 160px
  (4 tiles): span `[-156, 4]`.

Verified: 52/52 smoke assertions unchanged (Hurtbox/body-collision untouched or,
for Dummy, changed in a way with zero test dependency), exit 0, clean live boot
with the new FacingMarker node structure.

## Hurtbox scope rule: resources vs. creatures (2026-07-17, applied + verified)

Stated principle, validated against isometric (the eventual target camera -- this is
the standard isometric-action-RPG pattern for tall-sprite-vs-ground-position, not a
top-down-specific workaround):
- **Resource nodes (trees, minerals): Hurtbox = base tile only, regardless of visual
  height.** Already true -- tree/rock Hurtboxes were kept small and centered at the
  origin/base throughout every prior edit (originally for zero-test-risk reasons;
  turns out to also be the geometrically correct, permanent rule). A tree can grow
  to any height later without ever touching its Hurtbox.
- **Creature nodes (player, enemies): Hurtbox = full body extent, so a hit can land
  anywhere on the visible silhouette.** This was NOT true until this pass -- Player/
  Enemy/Dummy Hurtboxes were still small circles centered at the origin, a leftover
  from before bodies were TALL. Since the WxH respec made bodies extend mostly
  ABOVE the origin, those small origin-centered circles only covered the character's
  feet -- a visually-connecting swing on the torso would have mechanically MISSED.
  Fixed: each creature Hurtbox is now a RectangleShape2D matching the Body polygon's
  full bounding box (base-anchored, position `(0,-36)` = the vertical middle of the
  `[-76,4]` span), not a small origin-centered circle:
  - Player: 24x80 (matches its 1x2 visual bounds)
  - Enemy: 28x80
  - Dummy: 80x80 (matches its 2x2 visual bounds)
  Node-level `global_position` (used for knockback direction) is unaffected -- only
  the child CollisionShape2D's shape/local offset changed, so knockback math needed
  no changes. Verified: 52/52 smoke assertions unchanged (no test position tweaks
  needed -- all combat tests position along the horizontal plane, y~0, which sits
  comfortably inside every new Hurtbox's y-range), exit 0, clean live boot.

## CORRECTION 2026-07-17: characters resized 1x2 -> 0.5x1, FacingMarker removed

Undoes part of the "WxH respec" section above for Player and the chasing Enemy
ONLY. The Dummy (2x2) is explicitly UNCHANGED -- this correction does not touch
it at all, per direct instruction.

**New size**: Player and Enemy are now 0.5x1 tiles (20px wide x 40px tall) --
THINNER than a tile, only AS TALL as one tile (not two). Both use the identical
20x40 silhouette now (previously slightly different, r12 vs r14); differentiated
only by body color, a deliberate simplification.

**"Top half overlappable" -- the TALL recipe applied at a finer grain within a
single tile, not across two.** Origin = base (with the same "+4 sink below origin"
margin used throughout, keeping the combat-critical y=0 plane safely inside every
shape's range, not at a boundary). The BOTTOM HALF of the 40px height is solid
(body CollisionShape2D, physical blocking, `RectangleShape2D(20,20)` at
`(0,-6)` -- spans local y `[-16,4]`); the TOP HALF is visual-only / walk-behind
(no collision there at all). The Hurtbox (combat, "hit anywhere on the body" rule
from the prior correction -- UNCHANGED in principle) covers the FULL 40px height,
`RectangleShape2D(20,40)` at `(0,-16)` -- spans `[-36,4]`.

**FacingMarker REMOVED entirely** (the rotating-wedge component from two
corrections ago). Replaced with a simpler, more classic technique: the Body's
D-shape (rounded front / flat back, same construction as always) is built once at
its default "facing right" orientation, and flipped left/right by setting
`_body.scale.x` to `+1` (right) or `-1` (left) -- a true HORIZONTAL MIRROR around
the vertical axis, leaving y untouched.

CORRECTION (2026-07-18 -- bug fix): an earlier version of this note used
`_body.rotation = 0/PI` and wrongly claimed the shape is "vertically symmetric about
its origin, so 180deg == a horizontal mirror." It is NOT: the polygon is
BASE-ANCHORED (spans roughly y -36..+4, centroid well above the origin), so a 180deg
rotation about the origin flips it vertically too and drops the shape ~one body-height
down-screen on every left turn. The fix is `scale.x = +/-1` (mirror only), which is
also the standard sprite-flip idiom. Applies to Player (`_body.scale.x = side_facing`)
and the chasing Enemy (`_body.scale.x = _side_facing`); collision (a separate
CollisionShape2D) is unaffected. Lesson: flip a non-origin-symmetric shape with
`scale.x`, never `rotation`.

**Facing is now TWO separate concepts, decoupled on purpose**:
- `facing` (Player, public) / `_facing` (Enemy, private): the FULL direction,
  updates on every non-zero input/chase-direction including pure up/down and
  diagonals. Drives the sword/attack aim -- UNCHANGED behavior from before.
- `side_facing` (Player) / `_side_facing` (Enemy): LEFT (-1) or RIGHT (+1) only.
  Updates ONLY when the input/chase-direction has a nonzero x component (a side
  or a diagonal). A PURE up or down press/alignment leaves it untouched, holding
  whatever side was last faced. Drives ONLY `_body.rotation` (0 or PI).
  Diagonal input DOES flip it (it has an x component), matching "the game knows
  up/down/diagonal for aiming, but the D faces the last SIDE direction given."

Applies identically to Player (input-driven) and the chasing Enemy (AI-chase-
driven) -- the same left/right-only, up/down-preserving rule, by symmetry, even
though the request was phrased around player controls. The Dummy never rotates at
all (its `stationary` branch returns before any facing code), so it needed no
change beyond removing its now-orphaned FacingMarker node (dead weight only,
zero behavioral/visual effect -- not a change to "the creature" itself).

Verified: 80/80 smoke assertions (73 prior + 7 new, proving exactly this
decoupling: right/left flip correctly; pure UP and pure DOWN both update `facing`
but leave `side_facing`/rotation untouched; a diagonal correctly flips
`side_facing`), exit 0, clean live boot. No prior test positions needed
adjustment -- the "+4 sink" margin was deliberately preserved at the new smaller
scale specifically to keep the y=0 combat-test plane safely inside every shape.

*Verified against: Godot 4.7.1. Last updated: 2026-07-17*
