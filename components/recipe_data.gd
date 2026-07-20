class_name RecipeData
extends Resource
## Definition for ONE craftable recipe -- the inputs it consumes, the output it produces, its blueprint-point
## price to LEARN, and the OPTIONAL gates (a prereq talent / a minimum level) that fence it off (plan-core-loop.md
## Phase 3; design-crafting.md "Track B -- Building / crafting", design-multiplayer.md blueprint points). Pure
## DEFINITION data on a shared Resource, exactly like ItemData/ToolData/TalentData: the recipe's id, its I/O
## item references + counts, its learn cost, and its gates. NO runtime/per-character state ever lives here --
## WHICH recipes a given character has learned is CHARACTER state on components/known_recipes.gd, never on this
## shared definition (the sharing trap, patterns/resource-driven-design.md).
##
## INPUTS ARE PARALLEL ARRAYS. `input_items[i]` is consumed `input_counts[i]` at a time -- kept as two parallel
## Arrays (not a Dictionary) so the .tres stays a flat authorable list and the ItemData refs are plain
## ExtResource rows. The two arrays are authored the same length; a malformed recipe (mismatched lengths) is a
## content bug, not a runtime branch here. These I/O fields are DECLARED now but INERT until Part 3.2 -- Part 3.1
## is only the LEARN model (spend a blueprint point, respect the gate, track the known set); NOTHING consumes
## inputs or produces the output yet (that is craft EXECUTION, Part 3.2).
##
## GATES ARE OPTIONAL. `prereq_talent` ("" = none) names a Track A talent id that must be UNLOCKED before the
## recipe can be learned; `min_level` (0 = none) is the lowest character level that may learn it. The caller
## (CharacterSheet.learn_recipe -> KnownRecipes.can_learn) supplies the live talent set + level and enforces
## both -- this resource only DECLARES the gate values, mirroring how TalentData declares its prereqs/cost while
## Talents enforces them. `blueprint_cost` (default 1) is the Track B point price the caller deducts on a
## successful learn.
##
## STATION IS INERT UNTIL PHASE 4. `station_tag` ("" = craft anywhere) DECLARES which crafting station a recipe
## needs to EXECUTE -- authored now so recipes are complete, but NOTHING reads it in Phase 3 (no station exists;
## Phase 4 adds the Station node + the in-range gate that consumes this tag). Learning a recipe is station-
## independent; the tag only ever gates craft EXECUTION, never LEARNING. DETERMINISM: pure declarative data, no
## Time/OS/RNG (NOTES.md rule) -- every field is a fixed authored value the headless tests read exactly.

## Stable identity used everywhere the recipe is addressed (the known set, learn/can_learn lookups, a future save
## blob). A StringName so id compares are pointer-cheap and never collide with display text.
@export var id: StringName = &""
## Human-readable label (debug/logs, a future crafting UI). Never used as an identity key.
@export var display_name: String = "Recipe"
## The item DEFINITIONS this recipe consumes, PARALLEL to input_counts (input_items[i] is spent input_counts[i]
## at a time). ItemData refs (shared definitions), never per-instance stacks. INERT in Part 3.1 -- Part 3.2's
## craft execution reads these to validate + consume inventory. Empty = a recipe with no material cost.
@export var input_items: Array[ItemData] = []
## How many of each input_items[i] one craft consumes, PARALLEL to input_items. Authored the same length as
## input_items. INERT until Part 3.2 (craft execution).
@export var input_counts: Array[int] = []
## The item DEFINITION one craft produces. INERT in Part 3.1 -- Part 3.2 adds this to the inventory on a
## successful craft. A single output (multi-output recipes are not in scope for Epic 1).
@export var output_item: ItemData = null
## How many output_item one craft yields. INERT until Part 3.2 (craft execution).
@export var output_count: int = 1
## Blueprint-point price to LEARN this recipe (Track B). The CALLER (CharacterSheet.learn_recipe) deducts this
## from Progression.blueprint_points after can_learn() clears it; KnownRecipes itself only reports the cost,
## staying decoupled from Progression. Default 1 (one level's worth of Track B currency).
@export var blueprint_cost: int = 1
## OPTIONAL talent gate: a Track A talent id that must be UNLOCKED before this recipe can be learned. "" = no
## talent gate. Enforced by the caller (it passes the unlocked-talent set to can_learn); this only declares it.
@export var prereq_talent: StringName = &""
## OPTIONAL level gate: the lowest character level that may learn this recipe. 0 = no level gate. Enforced by the
## caller (it passes the live level to can_learn); this only declares it.
@export var min_level: int = 0
## INERT until PHASE 4 -- see the class docstring. Which crafting station a recipe needs to EXECUTE ("" = craft
## anywhere). Authored now so recipes are complete, but NOTHING reads it in Phase 3; learning is station-
## independent. Phase 4's Station node + in-range gate consume this.
@export var station_tag: StringName = &""

# Verified against: Godot 4.7.1 (2026-07-19)
