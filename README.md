# Kenslash

A top-down (heading toward isometric) hack-and-slash and gathering game built in
**Godot 4.7**, code-first and fully headless-tested. You wander a streaming open
world, fight enemies with a sword combo, and harvest it with the right tools --
built from the start to hold a large, player-modified world without the memory
sprawl that sinks games like it.

> Status: **playable prototype.** Single-player, placeholder-primitive visuals
> (shapes and colors, no art yet). The foundations for disk persistence and online
> multiplayer are deliberately in place but not yet built (see Roadmap).

## What's in it

**Combat**
- A 3-hit sword combo -- arc sweep, reverse arc, then a forward lunge -- chained by
  attacking again within a 0.5s window (miss it and it resets). The swing is
  hard-gated and its speed is a tunable stat.
- Knockback, invincibility frames (with a blink tell), and hit feedback.
- Enemies with an idle -> chase -> attack state machine, plus a stationary training
  dummy. A distinct death sequence (pass-through corpse, jerk-stop lurch, blink).

**Two decoupled stat systems** (the design backbone)
- **Combat damage**: classic `max(0, ATK - DEF)` -- predictable, DEF can fully block.
- **Durability wear**: a separate `power` vs `hardness` calculation with a three-band
  model (soft / workable / too-hard). A weapon can hit for damage yet still wear on a
  hard surface; a pickaxe can carve rock it slowly loses durability to. Durability
  never changes an item's effectiveness -- it works the same at 1% as at 100%, until
  it breaks.

**Tools and gathering**
- Sword, axe, and pickaxe, each with its own attack, power, and durability.
- A tool-category gate: only an axe harvests trees, only a pickaxe mines minerals; a
  sword whiffs on both. All tools damage creatures per their attack stat.

**Inventory and hotbar**
- A six-slot inventory; the hotbar is a window onto it. Number keys jump directly,
  scroll / Q / E cycle, `G` toggles a whole-inventory scroll mode. Empty slot = an
  unarmed fallback. Every key is reassignable (InputMap-driven, no hardcoded keys).

**Streaming open world** (the part built to scale)
- The world is chunked. **Dormant content is plain data; only chunks near the player
  become live Nodes**, freed again when you leave. Cost scales with proximity, not
  with how much world exists -- proven in the test suite: the active set stays bounded
  no matter how far you roam, and unloaded chunks free with zero orphaned nodes.
- Your changes persist: mine a rock, wander off, come back -- it's still mined. Die and
  respawn with the whole world kept (harvested stays harvested).
- A minimal HUD shows health, the equipped tool and its durability, and the hotbar.

## Engineering approach

This project is built **code-first** -- authored and iterated without the Godot
editor GUI -- and **verified headlessly**. Every system is backed by an automated
smoke suite (**141 assertions**) that runs in seconds with no display, covering combat
math, durability bands, tool gating, inventory logic, and the streaming world's
bounded-memory and no-leak guarantees. Design decisions are captured in the
`design-*.md` docs alongside the code, and the project follows a small set of self-
imposed rules (`CONVENTIONS.md`) such as file-size limits that keep responsibilities
in components rather than monoliths.

## Running it

Requires **Godot 4.7.x** (standard build). From the project directory:

```bash
godot --path .
```

The game boots into the streaming world. On Windows you can also use the bundled
launcher scripts (`play.cmd` to double-click, or `play.ps1` / `play.sh` with flags:
`--test`, `--editor`, `--import`).

### Controls (all reassignable)

| Action | Default |
|--------|---------|
| Move (8-directional) | `WASD` / arrow keys |
| Attack (3-hit combo) | `Space` / `J` |
| Equip hotbar slot 1-6 | `1`-`6` |
| Cycle hotbar | `Q` / `E` or mouse wheel |
| Toggle whole-inventory scroll | `G` |

## Testing

The headless smoke suite is the source of truth:

```bash
# via the launcher
./play.sh --test
# or directly
godot --headless --path . -s res://tests/smoke_slash.gd
```

Exit code 0 means all 141 assertions passed. Tests are split by system under
`tests/` (units, combat, durability/tools, streaming, playable, HUD) over a shared
`TestContext`.

## Project layout

```
components/   reusable components + pure resolvers (combat, durability, inventory,
              chunk data/generator, health, hitbox/hurtbox, world scale)
player/       player controller (movement, combo, equip, respawn)
enemy/        enemy AI (idle/chase/attack FSM) + training dummy
world/        rocks, trees, and the chunk streaming system
              (chunk_data / chunk_generator / chunk_manager / streaming_world)
ui/           HUD
data/         ToolData resources (sword / axe / pickaxe)
tests/        headless smoke suite (per-system modules)
main.tscn     combat/test arena fixture (not the game's boot scene)
design-*.md   design specs (combat, durability, inventory, world scale,
              streaming, playable loop)
DESIGN.md     the running design overview   CONVENTIONS.md   project rules
play.*        launcher scripts (kenslash)
```

## Roadmap

Deferred by design, with the seams already in place:
- **Disk persistence** -- the chunk load/unload lifecycle already retains a
  per-chunk data store with a dirty flag; disk save is "flush dirty chunks, read-else-
  generate on load."
- **Online multiplayer** (co-op-first) -- the controller is already input-struct
  driven (swappable for networked input), and the same spatial grid that streams the
  world is the network interest set.
- Biome variety, disk-backed worlds surviving long uptimes, combat juice (screen
  shake / hit-stop), an enemy vision cone, and an art pass.

## License

To be decided.
