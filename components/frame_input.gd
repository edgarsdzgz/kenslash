class_name FrameInput
extends RefCounted
## One tick of player intent, decoupled from its SOURCE. The controller's
## movement/attack math consumes this instead of reading Input directly, so the
## SAME controller can run from the local keyboard now, or networked peer input /
## AI / tests later. This is the multiplayer + testability seam -- see
## patterns/multiplayer-architecture.md ("input-driven controller" guardrail).

## Desired movement direction this tick; length <= 1 (already deadzone-filtered
## and clamped, as from Input.get_vector).
var move: Vector2 = Vector2.ZERO
## True on the tick the attack was pressed (edge-triggered).
var attack: bool = false

# Verified against: Godot 4.7.1 (2026-07-17)
