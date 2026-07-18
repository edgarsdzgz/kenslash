class_name CombatResolver
## Pure combat math (System 1 in design-durability.md): subtractive HP damage. No
## side effects, no state -- the single source of truth for how ATK meets DEF, so it
## is unit-testable headless by calling the static func directly. Never instantiated.

## HP damage a strike deals: subtractive, floored at 0. `hp_damage = max(0, atk - def)`.
## DEF can FULLY block -- 0 HP is a valid result (an over-armored target takes nothing),
## and the hit still CONNECTS (i-frames, knockback, durability wear all still apply), so
## you can grind the armor down even while dealing 0 HP. Flesh is never "too hard" --
## hardness (System 2) does NOT gate this number, only DEF does.
static func hp_damage(atk: int, def: int) -> int:
	return maxi(0, atk - def)

# Verified against: Godot 4.7.1 (2026-07-17)
