# Durability & Hardness System -- Design

Decided 2026-07-17. Two DECOUPLED systems: combat HP damage is predictable (ATK/DEF),
durability wear is a separate number (power/hardness). HP damage and wear never share
a value.

## System 1 -- Combat (HP damage)

Classic RPG. `hp_damage = max(0, ATK - DEF)` (subtractive = most predictable; a player
always does a known number). DEF = target natural DEF + armor DEF. If DEF is high enough,
HP damage is **0** -- armor can FULLY block HP. The hit still CONNECTS though (i-frames,
knockback, and durability wear all still apply), so you can wear the armor down even while
dealing 0 HP. Hardness never gates enemy HP -- only DEF does (flesh is never "too hard").

Emergent: vs an over-armored enemy you deal 0 HP, but if your weapon is in the workable
hardness band you grind the armor's durability to 0 -> it BREAKS -> DEF drops to natural
-> now HP gets through. "Break their guard, then break them." Falls out of the two systems.

## System 2 -- Durability (wear), the three-band model

Compares the weapon/tool `power` (its rating on the shared hardness scale) against the
target `hardness` (base material + armor). `over = hardness - power`, `threshold` = the
workable margin.

| Band | Condition                        | weapon wear                     | affects_target |
|------|----------------------------------|---------------------------------|----------------|
| A    | over <= 0 (hardness <= power)    | 0                               | true           |
| B    | 0 < over <= threshold            | ceil(wear_max * over/threshold) | true           |
| C    | over > threshold (too hard)      | wear_max                        | false          |

`affects_target` gates ONLY mineable MATERIAL integrity (Band C = can't carve obsidian).
It does NOT gate enemy HP -- enemies always take the ATK/DEF number above.

BOTH wear: when `affects_target`, the struck armor/material also loses durability
(`wear_taken` per hit). So armor degrades and breaks over a fight; rocks mine away.

## System 3 -- Tool categories (gathering gate)

Separate from combat and durability. Decides whether a tool can HARVEST a resource
node (tree, mineral). Does NOT gate creatures at all.

- `HarvestType` enum: NONE, CHOP (trees/wood), MINE (minerals/ore) -- extensible (DIG...).
- Tool carries `harvest_type` (NONE = pure weapon). Sword=NONE, Axe=CHOP, Pickaxe=MINE.
- Resource node carries `required_harvest` (tree=CHOP, mineral=MINE) + hardness + integrity.

Hitting a RESOURCE = TWO gates, in order:
1. Tool-type: tool.harvest_type must equal resource.required_harvest. Wrong tool = NO
   effect at all -- no harvest AND no wear (the swing whiffs; a sword gets nothing from a
   tree or mineral and is not dulled by it). DECIDED 2026-07-17.
2. Hardness band (System 2): with the RIGHT tool, Band C (too hard) = wear, no harvest;
   Band A/B = harvest (reduce integrity) + wear.

Hitting a CREATURE = NO tool-type gate. Any tool deals ATK HP (System 1) + hardness wear
(System 2). By design tools are worse weapons: ATK pickaxe < axe < sword.

Retcon: the durability-slice rocks become MINERALS (MINE, pickaxe-only) -- the sword no
longer mines them. Add a TREE (CHOP, axe-only), an Axe (atk ~4) and a Pickaxe (atk ~2),
and let the player switch the active tool (swaps the Hitbox atk/power/harvest_type +
active durability). Suggested: sword atk6/power5, axe atk4/power5 CHOP, pickaxe atk2/power7 MINE.

## Stats

Weapon/tool (ItemData-shaped resource for the definition; current durability is RUNTIME
on a DurabilityComponent -- never on the shared resource, per the resource-sharing trap):
- `atk: int`     -- HP damage potential (System 1)
- `power: int`   -- hardness rating (System 2)
- `break_threshold: int` -- workable margin above power
- `wear_max: int`        -- max durability lost per hit
- `max_durability: int`  -- + runtime current_durability

Target:
- `def: int`      -- HP mitigation (enemies/armor)
- `hardness: int` -- base material + armor
- Enemy: HealthComponent (combat HP) [+ optional armor: adds armor_def to DEF, armor_hardness
  to hardness, has its own DurabilityComponent; when it breaks -> DEF/hardness drop to flesh base]
- Material (rock): DurabilityComponent as its INTEGRITY (no combat HP -- you mine it, not ATK it);
  destroyed at 0.

Split rule: **HealthComponent = combat HP (ATK/DEF). DurabilityComponent = wear (hardness).**

## Resolvers -- PURE static functions (unit-testable headless)

```gdscript
class_name CombatResolver
static func hp_damage(atk: int, def: int) -> int:
    return maxi(0, atk - def)   # DEF can fully block: 0 HP is valid

class_name DurabilityResolver
# returns { "weapon_wear": int, "affects_target": bool }
static func resolve(power: int, hardness: int, threshold: int, wear_max: int) -> Dictionary:
    var over: int = hardness - power
    if over <= 0:
        return { "weapon_wear": 0, "affects_target": true }
    if over <= threshold:
        return { "weapon_wear": ceili(float(wear_max) * over / threshold), "affects_target": true }
    return { "weapon_wear": wear_max, "affects_target": false }
```

## Durability does NOT affect effectiveness -- FLAT until break

Core rule: wear never scales how well an item works. Armor at 1% durability protects
EXACTLY like 100% (same DEF + hardness); a pickaxe mines the same amount at any
durability; a weapon deals full ATK + power until it breaks. The ONLY consequence of
wear is the binary BREAK. Rationale: never punish the player for using an item / taking
hits with a slow-bleed nerf -- performance is constant, then it shatters.

Concretely: `current_durability` gates ONLY the `broke` transition. ATK, DEF, power,
hardness, and mining amount are read from the item's stats, never scaled by current
durability.

## Break behavior (the only place effectiveness changes -- at 0, binary)
- Weapon durability 0 -> `broke`: attacks deal nothing (0 ATK / 0 wear / 0 mining) until repaired (repair = later).
- Armor durability 0 -> armor is gone: DEF/hardness drop to natural (flesh) base.
- Material integrity 0 -> destroyed (queue_free; drops = later).

## Architecture (maps to our patterns)
- `DurabilityComponent` (Node, reusable on weapon/armor/material): current/max, `wear(amount)`,
  signals `durability_changed(cur, max)`, `broke`. Runtime state (not on the resource).
- Stats as an ItemData-style Resource (definition) -- `patterns/resource-driven-design.md`.
- `CombatResolver` + `DurabilityResolver` PURE static classes -- one chokepoint each, unit-tested.
- Wired into the EXISTING Hurtbox hit-resolution chokepoint (where damage is already applied).

## Worked numbers (sword: atk 6, power 5, threshold 3, wear_max 4, durability 40)
- Flesh enemy (def 1, hardness 2): hp = max(0,6-1)=5; over=-3 -> Band A, weapon_wear 0.
- Armored enemy (def 4, hardness 7 = flesh 2 + armor 5): hp = max(0,6-4)=2; over=2 -> Band B,
  weapon_wear ceil(4*2/3)=3; armor wears (same at 100% or 1% durability, until it breaks).
- Over-armored enemy (def 8, hardness 7): hp = max(0,6-8)=0 -> 0 HP, but over=2 -> Band B, so the
  armor still wears; grind it to 0 -> armor breaks -> def drops to flesh 2 -> now hp = 4 gets through.
- Soft rock (hardness 6, integrity 10): over=1 -> Band B, weapon_wear ceil(4*1/3)=2, mineable.
- Obsidian (hardness 12): over=7 > 3 -> Band C, weapon_wear 4, NOT mineable (need a stronger tool).

## Asset shapes (placeholder primitives, decided 2026-07-17)

- Minerals (MINE-only resource nodes): HEXAGON Polygon2D (6-point, flat or pointy
  top -- pick one, doc it). Replaces the current square rock body. Applies to both
  the soft mineral and obsidian instances.
- Trees (CHOP-only resource nodes): tall, narrow, VERTICAL brown rectangle Polygon2D
  (e.g. width ~16, height ~48-56 -- noticeably taller than wide, reads as a trunk).
- Player avatar: DIRECTIONAL shape, same "D" family as enemies (rounded front face +
  flat back, patterns already in enemy.gd/enemy.tscn) -- rotates to `facing`, exactly
  like the enemy Body does. Applies to the Player's `Body` Polygon2D only; the sword/
  blade visuals are unaffected.
- APPLIED 2026-07-17 (visual-only; collision/hurtbox shapes deliberately left
  unchanged, same simplification as the enemy D-shape): player Body -> D-shape
  polygon, rotates to `facing` every _simulate() tick. Rock Body -> hexagon
  (circumradius 20, applies to both soft mineral and obsidian since they share
  rock.tscn). Tree Body -> vertical brown rect (16x52, Color 0.45/0.3/0.15).
  Verified: 52/52 smoke assertions still pass, exit 0, clean live boot.

### Tree depth illusion (Y-sort), 2026-07-17 -- APPLIED + VERIFIED

Godot 2D has no true Z-height axis; the mechanism is Y-SORT (CanvasItem.y_sort_enabled)
comparing each node's origin Y -- higher Y (lower on screen / closer to camera) draws
IN FRONT of lower Y. The illusion ("trunk base blocks; canopy above is walk-behind")
comes from anchoring a TALL node's origin at its BASE, not its center, then letting
the tall visual extend upward (negative local Y) from that origin -- the whole node
still sorts by the base point, so canopy correctly overlaps the player when the
player's Y is above the trunk (walked "behind" it) and correctly hides behind the
player when the player's Y is below it.

Applied: `y_sort_enabled = true` on `Main` (main.tscn) -- Player/Enemy/Dummy/rocks/
Tree are all its direct children, so no reparenting needed and no existing
`get_node("X")` path (main.gd, tests) broke. `Background` got `z_index = -10` as
belt-and-suspenders so it always draws behind the y-sorted layer regardless of any
Control-vs-Node2D y-sort transform nuance (its own Y-sort position is already very
negative from `offset_top = -180`, so this is redundant insurance, not a fix).

Tree-specific: the tree's TWO collision shapes are independent and were treated
differently -- (1) the StaticBody2D's own CollisionShape2D (physical blocking, what
stops player movement) shrunk 36x36 -> 14x14, a small trunk footprint centered at the
origin/base, so only the very base blocks movement; (2) the Hurtbox's CollisionShape2D
(combat/harvest reach, what the axe hits) was left UNCHANGED at 40x40 -- deliberately,
so the tool-category test suite (which only touches the Hurtbox) needed zero changes
and stayed at 52/52 green. The Body visual re-anchored from symmetric (-8,-26)..(8,26)
to base-anchored (-8,-50)..(8,4) -- canopy mostly above origin, base at/near y=0.
Rocks were NOT touched -- squat/ground-level silhouettes have no "canopy" to overhang,
so the base/canopy split does not apply to them.

Verified: 52/52 smoke assertions unchanged (Hurtbox untouched -> zero test risk), exit
0, clean live boot after the y_sort + collision-shrink change.

## Slice scope (build now)
Two resolvers (unit-tested all bands + ATK/DEF), DurabilityComponent, sword atk/power/durability
+ break, DEF+hardness on enemies, an armored dummy whose armor wears then drops DEF/hardness, a
destructible rock (mineable vs too-hard), wiring into the Hurtbox flow. Headless-verified.
NO inventory/equip/UI/repair yet (data is ItemData-shaped so it grows into the item system).

*Verified against: Godot 4.7.1. Last updated: 2026-07-17*
