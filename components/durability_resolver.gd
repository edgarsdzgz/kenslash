class_name DurabilityResolver
## Pure durability math (System 2 in design-durability.md): the three-band
## power-vs-hardness model. No side effects -- returns how much the WEAPON wears and
## whether the strike AFFECTS the target (armor degrades / material is mineable).
## Fully decoupled from HP damage. Unit-testable headless. Never instantiated.

## Resolve one strike. `over = hardness - power`:
##   Band A (over <= 0):             weapon_wear 0,                          affects true
##   Band B (0 < over <= threshold): weapon_wear ceil(wear_max*over/thresh), affects true
##   Band C (over > threshold):      weapon_wear wear_max,                   affects false
## Band C means the target is too hard: the tool wears but cannot carve it (obsidian).
## Returns { "weapon_wear": int, "affects_target": bool }.
static func resolve(power: int, hardness: int, threshold: int, wear_max: int) -> Dictionary:
	var over: int = hardness - power
	if over <= 0:
		return {"weapon_wear": 0, "affects_target": true}
	if over <= threshold:
		return {"weapon_wear": ceili(float(wear_max) * over / threshold), "affects_target": true}
	return {"weapon_wear": wear_max, "affects_target": false}

# Verified against: Godot 4.7.1 (2026-07-17)
