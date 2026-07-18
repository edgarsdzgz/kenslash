# Collision Layer Scheme -- Sword Slash

Deliberate 2D physics layers. No default catch-all layer 1 for gameplay bodies;
every node states its layer and mask on purpose. Names are also registered in
`project.godot` under `[layer_names] 2d_physics/*` so the editor shows them.

| Bit | Value | Name          | Who sits on it                    |
|-----|-------|---------------|-----------------------------------|
| 1   | 1     | world         | (reserved for arena walls later)  |
| 2   | 2     | player_body   | Player CharacterBody2D            |
| 3   | 4     | enemy_body    | Enemy CharacterBody2D             |
| 4   | 8     | player_hitbox | Player/Sword Area2D (the slash)   |
| 5   | 16    | enemy_hurtbox | Enemy/Hurtbox Area2D              |
| 6   | 32    | enemy_hitbox  | Enemy/AttackHitbox Area2D (swing) |
| 7   | 64    | player_hurtbox| Player/Hurtbox Area2D             |
| 8   | 128   | harvestable   | Rock/Tree Hurtbox Area2D (gathering target) |

## Per-node layer/mask

| Node                  | collision_layer   | collision_mask       | monitoring | monitorable |
|-----------------------|-------------------|----------------------|------------|-------------|
| Player (body)         | 2 (player_body)   | 5 (world+enemy_body) | n/a        | n/a         |
| Enemy (body)          | 4 (enemy_body)    | 3 (world+player_body)| n/a        | n/a         |
| Dummy (body)          | 4 (enemy_body)    | 3 (world+player_body)| n/a        | n/a         |
| Sword (Hitbox)        | 8 (player_hitbox) | 0                    | false      | true        |
| Hurtbox (Enemy)       | 16 (enemy_hurtbox)| 8 (player_hitbox)    | true       | false       |
| AttackHitbox (Enemy)  | 32 (enemy_hitbox) | 0                    | false      | true        |
| Hurtbox (Player)      | 64 (player_hurtbox)| 32 (enemy_hitbox)   | true       | false       |
| Rock (StaticBody2D)   | 1 (world)         | 0                    | n/a        | n/a         |
| Hurtbox (Rock)        | 128 (harvestable) | 8 (player_hitbox)    | true       | false       |
| Tree (StaticBody2D)   | 1 (world)         | 0                    | n/a        | n/a         |
| Hurtbox (Tree)        | 128 (harvestable) | 8 (player_hitbox)    | true       | false       |

## Destructible rocks + trees (durability + tool-category slices)

A rock or tree is a `StaticBody2D` whose solid body sits on `world` (bit 1) -- the
same layer reserved for arena walls -- so the player body (mask 5 = world+enemy_body)
bumps into it while gathering. Its `Hurtbox` sits on a layer named `harvestable` (bit
8, value 128, renamed from the durability slice's `mineable` once trees joined rocks
on it) and monitors `player_hitbox` (mask 8), so the Sword hitbox reaches it via the
same one-way Hitbox->Hurtbox rule regardless of which tool is currently equipped.
`harvestable` is its own layer (not reused `enemy_hurtbox`) to keep the "resource
nodes are not enemies" distinction clean: a resource-node Hurtbox has no
HealthComponent (you gather it, not ATK it) and routes hits into a
`material_durability` DurabilityComponent (integrity) instead. The enemy's
AttackHitbox (32, masks nothing that includes 128) can never gather a resource node,
and a resource-node Hurtbox (mask 8) never reacts to an enemy swing.

Physics layer membership only decides WHETHER a Hitbox/Hurtbox pair can overlap at
all -- it does not decide whether a strike actually harvests. That is System 3's
job (design-durability.md), enforced entirely in code at the Hurtbox chokepoint
(`hurtbox.gd _on_area_entered`, Gate 1): every player tool's Hitbox lives on the same
`player_hitbox` layer and CAN overlap any `harvestable` Hurtbox, but the strike is a
total whiff unless `hitbox.harvest_type == hurtbox.required_harvest` (rock =
`Harvest.Type.MINE`, tree = `Harvest.Type.CHOP`). No new physics layer was added for
trees vs rocks on purpose -- the tool-type gate is the only thing that needs to tell
them apart.

Bodies collide as solid obstacles while alive: the player body masks `enemy_body`
and each enemy body masks `player_body`, so neither can walk through the other
(two kinematic bodies just block, they do not push each other). On enemy death
`enemy.gd _on_died()` disables the body's CollisionShape2D via `set_deferred`, so
the player can then pass through the corpse -- pass-through is the kill reward.

## One-way Hitbox -> Hurtbox discipline

Exactly one side monitors. The Sword Hitbox is *monitorable* (visible to others)
but monitors nothing (mask 0). The Enemy Hurtbox *monitors* (mask includes the
player_hitbox layer 8) and is not monitorable itself. So a single `area_entered`
fires -- always on the Hurtbox -- when the slash overlaps it. No double hits, no
"who detects whom" ambiguity.

The Sword's CollisionShape2D starts `disabled = true`; `Player.attack()` rotates
the Sword to the facing angle, enables the shape for `attack_duration` (0.15 s),
then disables it. Enabling the shape while it already overlaps the monitoring
Hurtbox makes the Hurtbox emit `area_entered` on the next physics frame.

Milestone B1 adds the mirror-image pair for the enemy hitting back: the enemy's
`AttackHitbox` sits on `enemy_hitbox` (32), monitorable/never monitors (mask 0),
and the player's `Hurtbox` monitors it on `player_hurtbox` (64, mask 32). Same
one-way rule, opposite direction. The two faction-split hitbox layers
(`player_hitbox` 8 vs `enemy_hitbox` 32) also mean the enemy's swing can never
land on another enemy's Hurtbox (which only masks `player_hitbox`), and the
player's slash can never hit the player (the player Hurtbox only masks
`enemy_hitbox`). The enemy AttackHitbox's CollisionShape2D starts `disabled`;
`Enemy.attack()` rotates the hitbox to face the target and enables it for
`attack_duration` (0.15 s), then a cooldown gates the next swing -- the same
time-windowed toggle the sword uses.

Relation to recipes/health-and-damage.md: that recipe uses a single generic
`hitbox` layer (5) with hitbox mask 0 / hurtbox mask = hitbox-layer. This slice
keeps the identical one-way rule but splits into named `player_hitbox`,
`enemy_hurtbox`, `enemy_hitbox`, and `player_hurtbox` layers, per the milestone's
"no default catch-all layers" ask. That split is exactly the recipe's own
"Faction separation" Variation, so neither side can damage its own faction.

Verified against: Godot 4.7.1 (2026-07-17)
