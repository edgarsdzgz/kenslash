# Inventory & Hotbar -- Design

Decided 2026-07-17. Code-first, NO UI yet (this slice is the data model + input/
selection logic; a visual inventory screen comes later, honoring this same model).

## Core model

ONE array, `Inventory.slots: Array` (default size 6, will grow later). Slot indices
are 0-based; KEYS map to slots via a fixed 10-position ring:

```
key:   1  2  3  4  5  6  7  8  9  0
index: 0  1  2  3  4  5  6  7  8  9
```

`hotbar_size = min(inventory.slots.size(), 10)` -- the leading N slots of the SAME
array are the hotbar. There is no separate hotbar array; hotbar is a WINDOW onto
inventory. Today (6 slots) hotbar_size = 6, so keys 7/8/9/0 map to slots that do not
exist yet -- inert until inventory grows. Growing inventory later (roadmap item)
naturally extends the live hotbar up to the full 10-key ring; beyond 10, later slots
need the future inventory UI to select directly (no key covers them).

Inventory UI layout (for the future screen, not built this slice): row 1 = slots
0-4 (keys 1-5), row 2 = slots 5-9 (keys 6-0), matching the key ring above.

## Equip / selection

`equipped_index: int` -- the slot currently active (drives the Sword Hitbox's live
stats). Default 0 (key '1').

- **Number keys 1-0**: ALWAYS jump `equipped_index` directly to that key's mapped
  slot index, regardless of lock state. (If that slot is empty -> equips "nothing",
  see Unarmed below.)
- **Scroll wheel**: step `equipped_index` by +/-1 through the CURRENT ring (see Lock
  below). Convention (pick one, easy to flip): scroll up = previous, scroll down =
  next -- matches the common convention players expect from hotbar games.
- **Q / E**: step `equipped_index` by -1 / +1 through the same ring as scroll.
  Verified example from the spec: at slot '1' (index 0), Q -> '0', Q again -> '9';
  E does the mirror: '9' -> '0' -> '1' -> '2'. This is the KEY RING order
  [1,2,3,4,5,6,7,8,9,0] wrapping end-to-end, NOT plain index -1/+1 (0 is adjacent to
  1 in the ring, not index 9 adjacent to index 0 numerically... it IS index 9
  adjacent to index 0, since key '0' maps to index 9 and key '1' maps to index 0 --
  so the ring IS just index wraparound over however many hotbar slots are live).

## Hotbar lock / unlock ('g' toggle)

Boolean `hotbar_unlocked`, default false (locked), toggled by an input action
(`toggle_hotbar_unlock`, suggested key 'g').

- **Locked** (default): scroll/Q/E wrap ONLY within `[0, hotbar_size)`.
- **Unlocked**: scroll/Q/E wrap within `[0, inventory.slots.size())` -- the WHOLE
  inventory, including slots beyond the hotbar window. Number keys are UNCHANGED in
  both modes -- they still jump straight to their fixed slot (spec: "if I scroll to
  some random item, but press the '2' hotkey, I will switch to the item in slot
  '2'"). Unlock does not move or rebind anything; it only widens the scroll/Q/E
  range. Toggling lock does not change `equipped_index`.
- Honest current-slice note: since inventory size == hotbar_size == 6 today, locked
  and unlocked behave IDENTICALLY until inventory grows past 6. The mechanism is
  still built and tested now (with a synthetic >6-slot inventory in tests) so it is
  correct the moment inventory grows -- no rework later.

## Auto-populate (today's slice; "sort" is explicitly deferred)

On inventory init (today: a fixed starting loadout, no pickup system yet), empty
slots auto-fill with the tools the player has, TOOL-PRIORITY order (weapons count as
tools): sword, axe, pickaxe (extend this order as tools are added). Non-tool items
are out of scope this slice (no non-tool items exist yet) but the array supports
mixed content later.

`sort()` -- DEFERRED per the user ("if we hit 'sort' we will develop that later"):
tools fill the hotbar first, non-tools push to the back/background of inventory
(beyond the hotbar window). Stub the method now (documented no-op / TODO), implement
later once non-tool items exist.

## Unarmed damage

If `equipped_index` points at an empty slot, or (later) a non-tool item, the player
is UNARMED: a baseline low ATK with NO durability/hardness interaction (no weapon =
nothing to wear, no harvest capability). Modeled as a constant fallback stat block
(NOT a real inventory item) the Player reads when the equipped slot has no ToolData.
Suggested: atk 1, harvest_type NONE, no DurabilityComponent (hitbox.durability stays
null, matching the existing precedent for non-wearing strikes).

## Architecture (maps to existing patterns)

- `Inventory` (RefCounted or Node, owned by Player): `slots: Array[ToolData]` (null =
  empty), `equipped_index`, `hotbar_unlocked`, `hotbar_size` (computed), methods
  `equip_index(i)`, `cycle(delta: int)` (respects lock), `add_tool(tool: ToolData)`
  (auto-populate first empty slot), `sort()` (stub).
  Godot 4.2+ typed arrays (`Array[ToolData]`) welcome here.
- Player reads `inventory.equipped_index` -> the ToolData (or null -> unarmed) and
  applies its stats to the Sword Hitbox + swaps to that tool's DurabilityComponent +
  blade_color, same mechanism already scoped for tool-switching in the durability
  slice (Part B). Equip is the SAME operation whether triggered by number key,
  scroll, or Q/E -- one `_equip(index)` chokepoint.
- Input: new InputMap actions `tool_1`..`tool_0` (or a single generic handler reading
  number key events), `toggle_hotbar_unlock` ('g'). Mouse wheel via
  `InputEventMouseButton` (`BUTTON_WHEEL_UP`/`BUTTON_WHEEL_DOWN`) in `_unhandled_input`,
  or InputMap actions bound to wheel -- verify current 4.7 binding approach when built.

## Build sequencing

1. (Leftover from durability slice, build first as the substrate) Minimal multi-tool
   wiring: axe + pickaxe ToolData instances, a tree (CHOP) + mineral retcon (rocks
   require MINE, sword can no longer mine them), the two-gate harvest check on
   Hurtbox, and a basic "equip a ToolData onto the Sword Hitbox" operation.
2. Inventory + hotbar on top: the array/lock/equip/cycle model above, wired to keys
   1-0 + scroll + Q/E + G, auto-populated with the player's starting tools, unarmed
   fallback. Headless-verified (direct-jump, ring wrap incl. the 1->0->9 example,
   lock vs unlock range with a synthetic bigger inventory, unarmed stats when equipped
   slot empty).
   NO visual UI this slice -- prove the model + input logic headless; a real
   inventory screen (the 2-row 1-5/6-0 layout) is a later, separate UI pass.

## Reassignable input -- standing convention (2026-07-17, verified)

Every key in this game is reassignable, even with no rebind menu built yet. The
mechanism is Godot's InputMap two-layer indirection, applied without exception:

- **Layer 1 (reassignable)**: physical key -> named action (e.g. key `1` ->
  action `"tool_1"`), configured in `project.godot`'s `[input]` section today, or
  changeable live later via `InputMap.action_erase_events()` +
  `action_add_event()` from a future settings menu. This is the ONLY layer a
  rebind ever touches.
- **Layer 2 (fixed, in code)**: named action -> game meaning (e.g. action
  `"tool_1"` -> `inventory.equip_index(0)`). This mapping is a compile-time
  constant in `player.gd` and NEVER changes. This is what makes "rebind key 1"
  change WHICH KEY equips the first hotbar slot, never WHICH SLOT is first --
  the slot order is permanently tied to the action name, not the physical key.

Code must NEVER check a physical key directly (`Input.is_physical_key_pressed`,
raw `KEY_*`/`keycode` comparisons). Every input reads `Input.is_action_pressed(...)`
/ `is_action_just_pressed(...)` / `get_vector(...)` against a named InputMap
action. This has been true since the original movement recipe (WASD, attack) and
now extends to the inventory/hotbar build: `tool_1`..`tool_9`, `tool_0`,
`toggle_hotbar_unlock`, `inventory_prev`, `inventory_next` are all named actions,
bound via `physical_keycode` (layout-independent -- the correct choice for
rebindable keys, since it identifies the physical key position rather than the
character a keyboard layout produces for it) to 1-9/0/G/Q/E by default.

Verified 2026-07-17: audited `player.gd` for any raw keycode/physical-key check
(none found) and confirmed the action->slot mapping is a fixed table (`tool_1`
always -> `equip_index(0)`, etc., never derived from which key fired).

**One honest exception**: the mouse wheel (`_unhandled_input`, `MOUSE_BUTTON_WHEEL_UP`/
`_DOWN`) reads Godot's raw button-index constants directly, not through a named
InputMap action -- it is not itself rebindable to a different button/device. Q/E
are the fully-rebindable equivalent for the same cycle behavior, so the gap is
narrow, but it is a real, deliberate scope boundary, not an oversight. Revisit if
wheel rebinding is ever actually wanted (InputMap actions CAN carry mouse-button
events too, so closing this gap later is a small, compatible change).

*Verified against: Godot 4.7.1. Last updated: 2026-07-17*
