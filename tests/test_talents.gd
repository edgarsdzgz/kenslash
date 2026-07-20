class_name TestTalents extends RefCounted
## Talents component + the talent-tree unlock/prereq/spend rules (plan-core-loop.md Phase 2, Part 2.1;
## design-crafting.md "Track A"). Proves the CHARACTER-data talent model (components/talents.gd + the
## data/talents/*.tres tree) validates unlocks purely and deterministically -- no scene, no Time/RNG:
##   * the authored tree loads with the expected nodes/costs/prereqs and a fresh character has NOTHING unlocked;
##   * a node cannot be unlocked without enough AVAILABLE points (available < cost is refused);
##   * a node with a prereq cannot be unlocked while that prereq is locked (points alone are not enough);
##   * with prereqs met AND enough points the unlock SUCCEEDS and reports the EXACT cost the caller must spend;
##   * a prereq node only becomes unlockable AFTER its prereq is unlocked, and the unlocked SET is correct;
##   * re-unlocking (and unknown ids) are refused no-ops that report cost 0 and never grow the set.
## Effects are INERT in Part 2.1 (Part 2.2 applies them + adds respec), so this suite asserts ONLY the
## data model + the unlock gate. Fully standalone: pure component instances, no player wiring (Part 2.2
## wires it onto the player). Registered in tests/smoke_slash.gd, mirroring tests/test_progression.gd.

## The five authored tree ids (data/talents/*.tres). blade_focus -> keen_edge -> master_strike is the
## 2-deep prereq chain (keen requires blade; master requires keen); forager + heavy_hitter are roots.
const BLADE: StringName = &"blade_focus"        # root, cost 1, MELEE_DAMAGE +1
const KEEN: StringName = &"keen_edge"           # cost 2, prereq [blade_focus], MELEE_DAMAGE +1
const MASTER: StringName = &"master_strike"     # cost 3, prereq [keen_edge], MELEE_DAMAGE +2 (third tier)
const FORAGER: StringName = &"forager"          # root, cost 1, HARVEST_YIELD +1
const HEAVY: StringName = &"heavy_hitter"       # root, cost 2, MELEE_DAMAGE +2

## FIX 3 -- the flagship recipe gated behind heavy_hitter + its inputs, for the recipe/talent DECOUPLING assertion.
const FORGE_RECIPE: StringName = &"forge_iron_sword"
const IRON_ORE: ItemData = preload("res://data/iron_ore.tres")
const STICK_ITEM: ItemData = preload("res://data/stick.tres")

## Part 2.2b scene legs: a controlled player proves the perk SUMS reach real gameplay (a swing's atk, a
## harvest's drop count). Remote coord, clear of every other self-contained module (progression 52000,
## xp-award 60000; this sits past them). Own holders, freed per leg.
const HOME: Vector2 = Vector2(70000, 0)
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const TREE_SCENE: PackedScene = preload("res://world/tree.tscn")
const ROCK_SCENE: PackedScene = preload("res://world/rock.tscn")


func run(ctx: TestContext) -> void:
	print("[talents] --- talent tree unlock/prereq/spend (points gate + prereq gate + exact cost) ---")
	_tree_tests(ctx)
	_points_gate_tests(ctx)
	_prereq_and_set_tests(ctx)
	# Part 2.2b: the CharacterSheet spend/respec chokepoint, then the two perk effects on real gameplay.
	_sheet_spend_and_respec_tests(ctx)
	# 2-deep prereq chain (blade -> keen -> master) + transitive orphan-gate + multi-order respec (FIX 3).
	_deep_chain_respec_tests(ctx)
	# Recipe/talent DECOUPLING: respec of a recipe's prereq talent does NOT relock the learned recipe.
	_recipe_survives_prereq_respec_test(ctx)
	await _melee_damage_leg(ctx)
	await _harvest_yield_leg(ctx)
	# Equip-mid-swing corruption gate + mid-swing cancel + non-sword swing bonus (FIX 1/2).
	await _equip_gate_leg(ctx)
	await _cancel_clears_bonus_leg(ctx)
	await _nonsword_bonus_leg(ctx)


## Tree-shape + fresh-state tests -- the authored nodes are present at the documented costs/prereqs and a
## brand-new Talents has nothing unlocked. No unlock yet; pure reads.
func _tree_tests(ctx: TestContext) -> void:
	var t: Talents = Talents.new()

	# The authored tree has all five nodes and no strays.
	ctx.check(t.tree().size() == 5 and t.has_talent(BLADE) and t.has_talent(KEEN) and t.has_talent(MASTER)
			and t.has_talent(FORAGER) and t.has_talent(HEAVY),
		"talent tree loads the 5 authored nodes (blade_focus, keen_edge, master_strike, forager, heavy_hitter)",
		"talent tree missing a node or wrong size (size %d)" % t.tree().size())

	# Costs + the two prereq edges match the authored .tres (pins the tree the test reasons about).
	var keen: TalentData = t.get_talent(KEEN)
	var master: TalentData = t.get_talent(MASTER)
	ctx.check(t.get_talent(BLADE).cost == 1 and keen.cost == 2 and master.cost == 3
			and t.get_talent(FORAGER).cost == 1 and t.get_talent(HEAVY).cost == 2
			and keen.prereqs.size() == 1 and keen.prereqs[0] == BLADE
			and master.prereqs.size() == 1 and master.prereqs[0] == KEEN,
		"authored costs (blade 1, keen 2, master 3, forager 1, heavy 2) and the chain prereqs (keen<-blade, master<-keen) match",
		"authored tree costs/prereqs drifted from the .tres")

	# Unknown id -> no node.
	ctx.check(t.get_talent(&"does_not_exist") == null and not t.has_talent(&"does_not_exist"),
		"an unknown id resolves to no node (get_talent null, has_talent false)",
		"an unknown id wrongly resolved to a node")

	# Fresh character: nothing unlocked.
	ctx.check(t.unlocked_count() == 0 and not t.is_unlocked(BLADE) and not t.is_unlocked(FORAGER),
		"a fresh Talents has an empty unlocked set (count 0, nothing is_unlocked)",
		"a fresh Talents was not empty (count %d)" % t.unlocked_count())


## Points-gate + exact-cost + re-unlock tests on a root node (no prereq in play, so this isolates the
## AVAILABLE-points gate and the reported cost).
func _points_gate_tests(ctx: TestContext) -> void:
	var t: Talents = Talents.new()  # blade_focus: root, cost 1

	# CANNOT unlock without enough points: 0 available < cost 1.
	ctx.check(not t.can_unlock(BLADE, 0),
		"cannot unlock blade_focus with 0 available points (below its cost of 1)",
		"blade_focus wrongly unlockable with 0 points")
	# heavy_hitter (cost 2) is not affordable at 1 either -- the gate is `available >= cost`, not > 0.
	ctx.check(not t.can_unlock(HEAVY, 1) and t.can_unlock(HEAVY, 2),
		"cannot unlock heavy_hitter with 1 point (cost 2) but can with 2 -- gate is available >= cost",
		"heavy_hitter affordability gate wrong at the cost boundary")

	# With enough points can_unlock is true; unlock() SUCCEEDS and reports the EXACT cost (1) for the
	# caller to deduct. The set grows by exactly one.
	ctx.check(t.can_unlock(BLADE, 1),
		"blade_focus is unlockable once available points (1) meet its cost (1)",
		"blade_focus not unlockable at exactly its cost")
	var spent: int = t.unlock(BLADE)
	ctx.check(spent == 1 and t.is_unlocked(BLADE) and t.unlocked_count() == 1,
		"unlocking blade_focus succeeds, reports the EXACT cost 1, and adds exactly it to the unlocked set",
		"blade_focus unlock reported wrong cost / did not enter the set (cost %d, count %d)" % [spent, t.unlocked_count()])

	# RE-UNLOCK is a refused no-op: reports 0, does not grow the set, stays unlocked. And an already-unlocked
	# node is no longer can_unlock even with points to spare.
	var again: int = t.unlock(BLADE)
	ctx.check(again == 0 and t.unlocked_count() == 1 and t.is_unlocked(BLADE) and not t.can_unlock(BLADE, 99),
		"re-unlocking blade_focus is a refused no-op (cost 0, set unchanged) and can_unlock is now false",
		"re-unlock mutated state or stayed unlockable (again %d, count %d)" % [again, t.unlocked_count()])

	# An UNKNOWN id can never be unlocked -- can_unlock false at any points, unlock() reports 0, set unchanged.
	var bogus: int = t.unlock(&"does_not_exist")
	ctx.check(not t.can_unlock(&"does_not_exist", 99) and bogus == 0 and t.unlocked_count() == 1,
		"an unknown id is never unlockable (can_unlock false, unlock returns 0, set unchanged)",
		"an unknown id was treated as unlockable (bogus %d, count %d)" % [bogus, t.unlocked_count()])


## Prereq-gate + unlocked-set tests: keen_edge requires blade_focus, so it must refuse until the prereq is
## unlocked -- even with points to burn -- then succeed. Verifies the final unlocked set is exactly correct.
func _prereq_and_set_tests(ctx: TestContext) -> void:
	var t: Talents = Talents.new()  # keen_edge: cost 2, prereq [blade_focus]

	# CANNOT unlock with an unmet prereq -- 99 points is plenty, but blade_focus is not unlocked yet.
	ctx.check(not t.can_unlock(KEEN, 99),
		"cannot unlock keen_edge while its prereq (blade_focus) is locked, even with 99 points",
		"keen_edge wrongly unlockable with an unmet prereq")
	# unlock() also refuses structurally (no-op, cost 0) regardless of the caller's affordability check.
	var early: int = t.unlock(KEEN)
	ctx.check(early == 0 and not t.is_unlocked(KEEN) and t.unlocked_count() == 0,
		"unlock(keen_edge) is a refused no-op while the prereq is locked (cost 0, not in set)",
		"keen_edge unlocked despite an unmet prereq (early %d)" % early)

	# Unlock the prereq first.
	var pre: int = t.unlock(BLADE)
	ctx.check(pre == 1 and t.is_unlocked(BLADE),
		"unlocking the prereq blade_focus first succeeds (cost 1)",
		"prereq blade_focus did not unlock (pre %d)" % pre)

	# NOW keen_edge is unlockable -- but still gated on its OWN cost (2): affordable at 2, not at 1.
	ctx.check(t.can_unlock(KEEN, 2) and not t.can_unlock(KEEN, 1),
		"with blade_focus unlocked, keen_edge becomes unlockable at its cost (2) but not at 1 point",
		"keen_edge prereq/points gate wrong after the prereq was met")
	var spent: int = t.unlock(KEEN)
	ctx.check(spent == 2 and t.is_unlocked(KEEN),
		"unlocking keen_edge after its prereq succeeds and reports the EXACT cost 2",
		"keen_edge unlock reported wrong cost / did not enter the set (cost %d)" % spent)

	# The unlocked SET is exactly {blade_focus, keen_edge} -- the two we unlocked and nothing else.
	ctx.check(t.unlocked_count() == 2 and t.is_unlocked(BLADE) and t.is_unlocked(KEEN)
			and not t.is_unlocked(FORAGER) and not t.is_unlocked(HEAVY),
		"the unlocked set is exactly {blade_focus, keen_edge} (forager + heavy_hitter stay locked)",
		"the unlocked set was wrong after the prereq chain (count %d)" % t.unlocked_count())


## Part 2.2b -- the CharacterSheet SPEND + RESPEC chokepoint (pure: a RefCounted CharacterSheet needs no
## scene). Proves unlock_talent deducts the EXACT talent points from the owned Progression and refuses when
## points are insufficient; that the perk SUMS reflect the unlocked set; and every respec rule -- exact
## refund, bonus auto-revert, respec_points decrement, refusal for a prereq of an unlocked node / a
## not-unlocked node / an exhausted allowance.
func _sheet_spend_and_respec_tests(ctx: TestContext) -> void:
	var sheet: CharacterSheet = CharacterSheet.new()

	# Fresh: talents wired, full respec allowance, no perks (nothing unlocked).
	ctx.check(sheet.talents != null and sheet.respec_points == CharacterSheet.RESPEC_START
			and sheet.melee_damage_bonus() == 0 and sheet.harvest_yield_bonus() == 0,
		"fresh CharacterSheet: talents wired, respec_points at the start allowance (%d), both perk sums 0" % CharacterSheet.RESPEC_START,
		"fresh CharacterSheet talents/respec/perk-sums not at defaults")

	# INSUFFICIENT POINTS: 0 talent points -> unlock_talent refused, deducts nothing, node stays locked.
	ctx.check(not sheet.unlock_talent(BLADE) and sheet.progression.talent_points == 0
			and not sheet.talents.is_unlocked(BLADE),
		"unlock_talent refuses blade_focus with 0 talent points and deducts NOTHING (node stays locked)",
		"unlock_talent wrongly spent/unlocked with insufficient points")

	# Bank points, then unlock blade_focus (cost 1, MELEE_DAMAGE +1): deducts EXACTLY 1, bonus becomes +1.
	sheet.progression.talent_points = 5
	var ok_blade: bool = sheet.unlock_talent(BLADE)
	ctx.check(ok_blade and sheet.progression.talent_points == 4 and sheet.melee_damage_bonus() == 1,
		"unlock_talent(blade_focus) succeeds, deducts EXACTLY its cost (5 -> 4), melee bonus becomes +1",
		"blade_focus unlock deducted the wrong points / wrong bonus (pts %d, bonus %d)" % [sheet.progression.talent_points, sheet.melee_damage_bonus()])

	# Unlock keen_edge (cost 2, prereq blade_focus, MELEE_DAMAGE +1): deducts EXACTLY 2, bonus becomes +2.
	var ok_keen: bool = sheet.unlock_talent(KEEN)
	ctx.check(ok_keen and sheet.progression.talent_points == 2 and sheet.melee_damage_bonus() == 2,
		"unlock_talent(keen_edge) deducts EXACTLY its cost (4 -> 2), melee bonus stacks to +2",
		"keen_edge unlock deducted the wrong points / wrong bonus (pts %d, bonus %d)" % [sheet.progression.talent_points, sheet.melee_damage_bonus()])

	# RESPEC REFUSED -- blade_focus is a prereq of the still-unlocked keen_edge: no refund, no respec spent,
	# node stays unlocked (un-picking it would orphan keen_edge).
	var pts_before: int = sheet.progression.talent_points     # 2
	var respec_before: int = sheet.respec_points               # RESPEC_START
	ctx.check(not sheet.respec(BLADE) and sheet.talents.is_unlocked(BLADE)
			and sheet.progression.talent_points == pts_before and sheet.respec_points == respec_before,
		"respec REFUSED for blade_focus while keen_edge (which depends on it) is unlocked -- no refund, no respec spent",
		"respec of a prereq-of-unlocked node was not refused (pts %d, respec %d)" % [sheet.progression.talent_points, sheet.respec_points])

	# RESPEC keen_edge (a leaf now): refunds EXACTLY its cost (2), reverts the bonus (+2 -> +1), spends one
	# respec_point.
	var ok_respec_keen: bool = sheet.respec(KEEN)
	ctx.check(ok_respec_keen and not sheet.talents.is_unlocked(KEEN)
			and sheet.progression.talent_points == pts_before + 2 and sheet.melee_damage_bonus() == 1
			and sheet.respec_points == respec_before - 1,
		"respec(keen_edge) refunds the EXACT cost (2 -> pts %d), reverts the melee bonus (+2 -> +1), respec_points %d -> %d" % [sheet.progression.talent_points, respec_before, sheet.respec_points],
		"respec(keen_edge) refund/bonus/allowance wrong (pts %d, bonus %d, respec %d)" % [sheet.progression.talent_points, sheet.melee_damage_bonus(), sheet.respec_points])

	# With keen_edge gone, blade_focus is a leaf -> respec now ALLOWED: refund 1, bonus reverts to 0.
	var ok_respec_blade: bool = sheet.respec(BLADE)
	ctx.check(ok_respec_blade and not sheet.talents.is_unlocked(BLADE) and sheet.melee_damage_bonus() == 0
			and sheet.respec_points == respec_before - 2,
		"respec(blade_focus) is now allowed (no dependents), refunds 1, melee bonus reverts to 0, respec_points %d -> %d" % [respec_before, sheet.respec_points],
		"respec(blade_focus) not allowed once it was a leaf / wrong refund/bonus")

	# RESPEC of a NOT-unlocked node is refused (forager was never unlocked): changes nothing.
	var respec_now: int = sheet.respec_points
	ctx.check(not sheet.respec(FORAGER) and sheet.respec_points == respec_now,
		"respec REFUSED for forager (never unlocked) -- no respec_point spent",
		"respec of a not-unlocked node was not refused")

	# EXHAUSTED ALLOWANCE: a fresh sheet with respec_points forced to 0 refuses to respec even a valid leaf.
	var s2: CharacterSheet = CharacterSheet.new()
	s2.progression.talent_points = 10
	s2.unlock_talent(BLADE)
	s2.respec_points = 0
	ctx.check(not s2.respec(BLADE) and s2.talents.is_unlocked(BLADE),
		"respec REFUSED when respec_points is 0 (allowance exhausted) -- the leaf stays unlocked",
		"respec was allowed with 0 respec_points")


## FIX 3 -- a 2-DEEP prereq chain (blade_focus -> keen_edge -> master_strike) exercises multi-level unlock
## ordering, the TRANSITIVE orphan-gate (a MID node cannot be respecced while its descendant is unlocked),
## multi-ORDER respec (leaf, then mid, then root -- each refunds exactly), and an INDEPENDENT root respecced
## on its own. Pure CharacterSheet (a RefCounted needs no scene). Deterministic integer spend/refund.
func _deep_chain_respec_tests(ctx: TestContext) -> void:
	var s: CharacterSheet = CharacterSheet.new()
	s.progression.talent_points = 10

	# master_strike is gated on keen_edge (its prereq), which is gated on blade_focus -- so it CANNOT unlock
	# before the chain below it, no matter the points. Deducts nothing, node stays locked.
	ctx.check(not s.unlock_talent(MASTER) and not s.talents.is_unlocked(MASTER)
			and s.progression.talent_points == 10,
		"master_strike cannot unlock while its prereq chain (keen_edge/blade_focus) is locked -- deducts nothing",
		"master_strike wrongly unlocked / spent with an unmet 2-deep prereq")

	# Unlock the chain IN ORDER: blade (1) -> keen (2) -> master (3). Points 10 -> 9 -> 7 -> 4; the MELEE sum
	# climbs +1 -> +2 -> +4 (blade +1, keen +1, master +2).
	var c1: bool = s.unlock_talent(BLADE)
	var c2: bool = s.unlock_talent(KEEN)
	var c3: bool = s.unlock_talent(MASTER)
	ctx.check(c1 and c2 and c3 and s.progression.talent_points == 4 and s.melee_damage_bonus() == 4
			and s.talents.is_unlocked(BLADE) and s.talents.is_unlocked(KEEN) and s.talents.is_unlocked(MASTER),
		"the 2-deep chain unlocks IN ORDER (blade -> keen -> master), points 10 -> 4, melee sum climbs to +4",
		"the 2-deep chain did not unlock in order / wrong points/bonus (pts %d, bonus %d)" % [s.progression.talent_points, s.melee_damage_bonus()])

	# TRANSITIVE orphan-gate: with master_strike unlocked, the MID node keen_edge cannot be respecced (it is
	# still a prereq of the unlocked master), and neither can the ROOT blade_focus (prereq of keen) -- both
	# refused, nothing refunded, no respec spent.
	var pts_before: int = s.progression.talent_points        # 4
	var respec_before: int = s.respec_points                  # RESPEC_START (3)
	ctx.check(not s.respec(KEEN) and not s.respec(BLADE)
			and s.talents.is_unlocked(KEEN) and s.talents.is_unlocked(BLADE)
			and s.progression.talent_points == pts_before and s.respec_points == respec_before,
		"respec REFUSED for the mid node keen_edge AND the root blade_focus while master_strike depends on them (transitive orphan-gate)",
		"a prereq-of-unlocked node was respeccable in the 2-deep chain (pts %d, respec %d)" % [s.progression.talent_points, s.respec_points])

	# MULTI-ORDER respec, unwinding leaf -> mid -> root: master (refund 3), then keen (refund 2), then blade
	# (refund 1). Each refunds EXACTLY its cost, the melee sum reverts +4 -> +2 -> +1 -> 0, and respec_points
	# decrement 3 -> 2 -> 1 -> 0. This spends the whole RESPEC_START allowance (3) exactly.
	var r_master: bool = s.respec(MASTER)
	ctx.check(r_master and not s.talents.is_unlocked(MASTER) and s.progression.talent_points == 7
			and s.melee_damage_bonus() == 2 and s.respec_points == respec_before - 1,
		"respec(master_strike) as the leaf refunds EXACTLY 3 (4 -> 7), reverts melee +4 -> +2, respec_points -1",
		"respec(master_strike) refund/bonus/allowance wrong (pts %d, bonus %d, respec %d)" % [s.progression.talent_points, s.melee_damage_bonus(), s.respec_points])
	var r_keen: bool = s.respec(KEEN)
	ctx.check(r_keen and not s.talents.is_unlocked(KEEN) and s.progression.talent_points == 9
			and s.melee_damage_bonus() == 1 and s.respec_points == respec_before - 2,
		"respec(keen_edge) now that master is gone (it is a leaf) refunds EXACTLY 2 (7 -> 9), reverts +2 -> +1",
		"respec(keen_edge) mid-node refund/bonus wrong (pts %d, bonus %d)" % [s.progression.talent_points, s.melee_damage_bonus()])
	var r_blade: bool = s.respec(BLADE)
	ctx.check(r_blade and not s.talents.is_unlocked(BLADE) and s.progression.talent_points == 10
			and s.melee_damage_bonus() == 0 and s.respec_points == respec_before - 3,
		"respec(blade_focus) as the last leaf refunds EXACTLY 1 (9 -> 10), reverts +1 -> 0, allowance now spent",
		"respec(blade_focus) root refund/bonus wrong (pts %d, bonus %d)" % [s.progression.talent_points, s.melee_damage_bonus()])

	# INDEPENDENT root (heavy_hitter) respecced ON ITS OWN -- a fresh sheet (the one above spent its whole
	# allowance). Unlock heavy (cost 2, +2), then respec it straight back: refund 2, bonus reverts to 0.
	var s2: CharacterSheet = CharacterSheet.new()
	s2.progression.talent_points = 5
	s2.unlock_talent(HEAVY)
	ctx.check(s2.melee_damage_bonus() == 2 and s2.progression.talent_points == 3
			and s2.respec(HEAVY) and not s2.talents.is_unlocked(HEAVY)
			and s2.progression.talent_points == 5 and s2.melee_damage_bonus() == 0
			and s2.respec_points == CharacterSheet.RESPEC_START - 1,
		"an INDEPENDENT root (heavy_hitter) unlocks then respecs on its own -- refund 2 (3 -> 5), bonus 2 -> 0",
		"independent-root heavy_hitter unlock/respec wrong (pts %d, bonus %d)" % [s2.progression.talent_points, s2.melee_damage_bonus()])


## FIX 3 -- learn is a ONE-TIME gate: a later talent RESPEC of a recipe's prereq talent does NOT relock the
## recipe. Unlock heavy_hitter (forge_iron_sword's prereq_talent), learn the recipe, then respec heavy_hitter
## away and assert the recipe is STILL known AND STILL craftable. Talents own NO recipe state (the learned set
## lives on KnownRecipes; craft() re-checks only known + station + materials, never the learn-time talent gate),
## so a respec cannot touch recipe knowledge -- the two systems are decoupled. Pure CharacterSheet + a
## Crafting.would_craft dry-run (a RefCounted needs no scene). Deterministic membership/integer work, no Time/RNG.
func _recipe_survives_prereq_respec_test(ctx: TestContext) -> void:
	var s: CharacterSheet = CharacterSheet.new()
	s.progression.blueprint_points = 5
	s.progression.talent_points = 5
	s.progression.level = 3
	s.unlock_talent(HEAVY)                             # forge_iron_sword's prereq talent
	var learned: bool = s.learn_recipe(FORGE_RECIPE)   # the one-time gate is satisfied -> recipe known

	# Respec heavy_hitter (an independent root leaf -- no unlocked talent depends on it) straight back, so the
	# talent gate the recipe was learned behind is now GONE from the unlocked set.
	var respecced: bool = s.respec(HEAVY)

	# DECOUPLING: the recipe stays KNOWN (learn is permanent) AND stays CRAFTABLE (would_craft dry-run with the
	# mats + a forge tag) even though its prereq talent was un-picked -- talent respec never relocks recipe knowledge.
	var craft: Crafting = Crafting.new()
	var inv: Inventory = Inventory.new()
	inv.add_item(IRON_ORE, 3)
	inv.add_item(STICK_ITEM, 1)
	var still_craftable: bool = craft.would_craft(FORGE_RECIPE, s, inv, {&"forge": 1})
	ctx.check(learned and respecced and not s.talents.is_unlocked(HEAVY)
			and s.known_recipes.is_known(FORGE_RECIPE) and still_craftable,
		"RESPEC of a recipe's prereq talent does NOT relock the recipe: heavy_hitter respecced away, yet forge_iron_sword stays KNOWN + CRAFTABLE (learn is a one-time gate, decoupled from talent state)",
		"a talent respec relocked/blocked a learned recipe (learned=%s, respecced=%s, heavy_unlocked=%s, known=%s, craftable=%s)" % [str(learned), str(respecced), str(s.talents.is_unlocked(HEAVY)), str(s.known_recipes.is_known(FORGE_RECIPE)), str(still_craftable)])


## Part 2.2b MELEE_DAMAGE -- a controlled player's swing deals measurably MORE atk after a MELEE talent is
## unlocked. combat.gd adds the sheet's melee_damage_bonus onto the Sword Hitbox atk for the swing's
## duration (read off the OWNING player), so the boost is observable mid-swing on player._sword.atk and
## reverts between swings. The default equipped tool is the sword; its base atk is the between-swings value.
func _melee_damage_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0  # inert like the other remote players; nothing to grab out here
	holder.add_child(player)
	player.global_position = HOME
	await ctx.settle_idle()
	await ctx.tree.physics_frame

	# Between swings, no bonus is applied: player._sword.atk is the equipment-owned base, and the sheet
	# reports a 0 melee bonus with nothing unlocked.
	var base_atk: int = player._sword.atk
	ctx.check(player.character().melee_damage_bonus() == 0,
		"a fresh player's melee_damage_bonus is 0 (no talents unlocked)",
		"fresh player melee bonus not 0 (got %d)" % player.character().melee_damage_bonus())

	# A swing with NO talent leaves the atk at base (attack() runs to its first await synchronously, so
	# _begin_swing has already applied the -- here zero -- bonus by the time control returns to us).
	player._combo_index = 0
	player.attack()  # started, NOT awaited -- read the boosted atk mid-swing, then drain to completion
	var swing_atk_no_talent: int = player._sword.atk
	ctx.check(swing_atk_no_talent == base_atk,
		"a swing with no MELEE talent keeps the base atk (%d) -- no bonus added" % base_atk,
		"an un-talented swing changed the atk (base %d, swing %d)" % [base_atk, swing_atk_no_talent])
	await _drain_swing(ctx, player)

	# Bank points and unlock blade_focus (MELEE +1) + heavy_hitter (MELEE +2) -> a +3 melee bonus.
	player.character().progression.talent_points = 10
	var ok1: bool = player.character().unlock_talent(BLADE)
	var ok2: bool = player.character().unlock_talent(HEAVY)
	ctx.check(ok1 and ok2 and player.character().melee_damage_bonus() == 3,
		"unlocking blade_focus (+1) and heavy_hitter (+2) sums to a +3 melee bonus",
		"melee bonus after two MELEE talents wrong (got %d)" % player.character().melee_damage_bonus())

	# Now a swing deals measurably MORE: the Sword Hitbox atk is base + 3 for the swing's duration -- the
	# EXACT value the Hurtbox reads on overlap, so the strike lands 3 more HP damage.
	player._combo_index = 0
	player.attack()  # started, NOT awaited
	var swing_atk_talent: int = player._sword.atk
	ctx.check(swing_atk_talent == base_atk + 3,
		"a swing WITH the MELEE talents deals measurably more: atk %d -> %d (+3 bonus, the delta the Hurtbox reads)" % [base_atk, swing_atk_talent],
		"MELEE talent did not boost the swing atk (base %d, swing %d, expected %d)" % [base_atk, swing_atk_talent, base_atk + 3])
	await _drain_swing(ctx, player)

	# The bonus is swing-scoped: once the swing ends the equipment-owned base atk is restored exactly.
	ctx.check(player._sword.atk == base_atk,
		"the MELEE bonus is swing-scoped: atk reverts to the base (%d) between swings" % base_atk,
		"the MELEE bonus leaked past the swing (atk %d, base %d)" % [player._sword.atk, base_atk])

	holder.queue_free()
	await ctx.tree.physics_frame


## Part 2.2b HARVEST_YIELD -- a fell/mine yields measurably MORE for a player with the forager talent. The
## yield path resolves the harvester through the "player" group (same as the harvest-XP hook), so this leg
## takes over that group with its OWN controlled player, measures the baseline drop counts, unlocks forager
## (+1), and measures the boosted counts. The incidental shared main player is displaced from the group for
## the leg and restored at teardown, so nothing else is polluted.
func _harvest_yield_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0
	holder.add_child(player)
	player.global_position = HOME + Vector2(0, 5000)
	await ctx.settle_idle()
	await ctx.tree.physics_frame

	# Take over the "player" group so the yield path resolves OUR controlled player, not the incidental
	# shared main player. Displaced members are restored at teardown.
	var displaced: Array = []
	for other in ctx.tree.get_nodes_in_group("player"):
		if other != player:
			other.remove_from_group("player")
			displaced.append(other)

	# --- BASELINE (no forager) --------------------------------------------------
	# Tree fell -> exactly yield_amount wood. Read the authored base off a throwaway instance, freed
	# immediately so it never lingers as an orphan node (the streaming zero-orphan baseline is strict).
	var probe: StaticBody2D = TREE_SCENE.instantiate() as StaticBody2D
	var tree_amt: int = int(probe.get("yield_amount"))  # authored base (3)
	probe.free()
	var base_wood: int = await _fell_and_count(ctx, holder, HOME + Vector2(200, 5000))
	ctx.check(base_wood == tree_amt,
		"BASELINE (no forager): a felled tree yields exactly yield_amount wood (%d)" % tree_amt,
		"baseline tree-fell yield wrong (got %d, expected %d)" % [base_wood, tree_amt])
	# Rock mined once -> exactly 1 stone.
	var base_stone: int = await _mine_once_and_count(ctx, holder, HOME + Vector2(400, 5000))
	ctx.check(base_stone == 1,
		"BASELINE (no forager): one affecting mine yields exactly 1 stone",
		"baseline rock per-mine yield wrong (got %d, expected 1)" % base_stone)

	# --- UNLOCK FORAGER (HARVEST_YIELD +1) --------------------------------------
	player.character().progression.talent_points = 5
	var okf: bool = player.character().unlock_talent(FORAGER)
	ctx.check(okf and player.character().harvest_yield_bonus() == 1,
		"unlock_talent(forager) succeeds and the harvest_yield bonus becomes +1",
		"forager unlock / harvest bonus wrong (ok %s, bonus %d)" % [str(okf), player.character().harvest_yield_bonus()])

	# --- BOOSTED (forager unlocked) ---------------------------------------------
	# Tree fell -> yield_amount + 1 wood (the delta).
	var boosted_wood: int = await _fell_and_count(ctx, holder, HOME + Vector2(600, 5000))
	ctx.check(boosted_wood == tree_amt + 1,
		"forager makes a felled tree yield measurably MORE: %d -> %d wood (+1 delta)" % [tree_amt, boosted_wood],
		"forager tree-fell delta wrong (got %d, expected %d)" % [boosted_wood, tree_amt + 1])
	# Rock mined once -> 2 stone (the delta).
	var boosted_stone: int = await _mine_once_and_count(ctx, holder, HOME + Vector2(800, 5000))
	ctx.check(boosted_stone == 2,
		"forager makes one affecting mine yield measurably MORE: 1 -> 2 stone (+1 delta)",
		"forager rock per-mine delta wrong (got %d, expected 2)" % boosted_stone)

	# --- Teardown: restore the displaced group members, free the holder ----------
	for other in displaced:
		if is_instance_valid(other):
			other.add_to_group("player")
	holder.queue_free()
	await ctx.tree.physics_frame


## FIX 1/2 -- equip-mid-swing must NOT corrupt the base atk. The bug: combat's swing-scoped MELEE bonus and
## equipment's equip_tool both write the Sword Hitbox atk; a tool swap mid-swing overwrote the base while a
## bonus was applied, so the swing-end clear subtracted it from the WRONG base -> permanent corruption. The
## fix GATES equip while a swing is in flight (the input-processing methods skip). This leg unlocks a MELEE
## talent, begins a swing, drives the REAL scroll-wheel equip path mid-swing (gated -> no swap), drains the
## swing, and asserts BOTH tools keep their correct base atk -- then that the SAME swap works normally AFTER.
## The wheel path (handle_wheel_input) takes the event + is_attacking as plain arguments, so this drives the
## true equip chokepoint deterministically (no Input-singleton frame-timing fragility).
func _equip_gate_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0
	holder.add_child(player)
	player.global_position = HOME + Vector2(0, 10000)
	await ctx.settle_idle()
	await ctx.tree.physics_frame

	# The default equipped tool is the sword; record its base atk and the axe's authored base. A wheel-down
	# notch cycles equipped_index 0 (sword) -> 1 (axe), so a successful equip lands on the axe.
	var sword_base: int = player._sword.atk
	var axe_base: int = Player.AXE_DATA.atk
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true

	# Unlock a MELEE talent (blade_focus, +1) so a swing applies a real bonus onto the Sword Hitbox atk.
	player.character().progression.talent_points = 5
	var okb: bool = player.character().unlock_talent(BLADE)
	ctx.check(okb and player.character().melee_damage_bonus() == 1,
		"equip-gate setup: blade_focus unlocked, melee bonus +1",
		"equip-gate setup failed (ok %s, bonus %d)" % [str(okb), player.character().melee_damage_bonus()])

	# Begin a swing (index 0), NOT awaited: _begin_swing has applied the +1 bonus, so atk is base+1 in flight.
	player._combo_index = 0
	player.attack()
	ctx.check(player._combat.is_attacking() and player._sword.atk == sword_base + 1,
		"a swing is in flight with the melee bonus applied (atk %d = base %d + 1)" % [player._sword.atk, sword_base],
		"swing did not apply the bonus / not attacking (atk %d, base %d)" % [player._sword.atk, sword_base])

	# MID-SWING: drive the REAL scroll-wheel equip path with is_attacking=true -- it must SKIP the equip,
	# leaving the sword active, the equipped_index un-cycled, and atk untouched (the same notch equips the axe
	# below when NOT attacking, so this proves the gate blocked a swap that would otherwise have corrupted atk).
	player._equipment.handle_wheel_input(wheel, player._combat.is_attacking())
	ctx.check(player._equipment._active_tool == Player.SWORD_DATA and player._sword.atk == sword_base + 1
			and player.inventory.equipped_index == 0,
		"a mid-swing wheel-equip is GATED: sword stays active, index un-cycled, atk unchanged (still %d)" % player._sword.atk,
		"a mid-swing equip was NOT gated (active tool/index/atk changed, atk %d)" % player._sword.atk)

	# Drain the swing; its end clears the bonus, restoring the sword's EXACT base -- no corruption.
	await _drain_swing(ctx, player)
	ctx.check(player._sword.atk == sword_base and player._combat._melee_bonus_applied == 0,
		"after the swing the sword base atk is restored EXACTLY (%d), bonus tracker 0 -- no corruption" % sword_base,
		"the swing left the sword base corrupted (atk %d, base %d, bonus %d)" % [player._sword.atk, sword_base, player._combat._melee_bonus_applied])

	# Now (not attacking) the SAME wheel notch SUCCEEDS: the axe equips at its correct, uncorrupted base.
	player._equipment.handle_wheel_input(wheel, player._combat.is_attacking())
	ctx.check(player._equipment._active_tool == Player.AXE_DATA and player._sword.atk == axe_base,
		"AFTER the swing the swap works: the axe equips at its correct base atk (%d), uncorrupted" % axe_base,
		"the post-swing axe equip failed / base corrupted (atk %d, expected %d)" % [player._sword.atk, axe_base])

	holder.queue_free()
	await ctx.tree.physics_frame


## FIX 2 -- a mid-swing CANCEL (the death path routes through combat.cancel_swing) must clear the MELEE bonus
## and restore the Sword Hitbox base atk EXACTLY, so a cancelled swing never strands the bonus on the next
## swing's base. Unlock a MELEE talent, begin a swing (bonus applied), cancel it, assert the base is restored.
func _cancel_clears_bonus_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0
	holder.add_child(player)
	player.global_position = HOME + Vector2(0, 12000)
	await ctx.settle_idle()
	await ctx.tree.physics_frame

	var sword_base: int = player._sword.atk
	player.character().progression.talent_points = 5
	player.character().unlock_talent(BLADE)  # MELEE +1

	# Begin a swing: the bonus is applied, atk = base + 1, in flight.
	player._combo_index = 0
	player.attack()
	ctx.check(player._combat.is_attacking() and player._sword.atk == sword_base + 1
			and player._combat._melee_bonus_applied == 1,
		"pre-cancel: a swing is in flight with the +1 bonus applied (atk %d, tracker 1)" % player._sword.atk,
		"pre-cancel state wrong (atk %d, base %d, tracker %d)" % [player._sword.atk, sword_base, player._combat._melee_bonus_applied])

	# Cancel mid-swing (the death path): remove the bonus, restore the base EXACTLY, zero the tracker, clear
	# the attacking latch.
	player._combat.cancel_swing()
	ctx.check(player._sword.atk == sword_base and player._combat._melee_bonus_applied == 0
			and not player._combat.is_attacking(),
		"cancel_swing restores the base atk EXACTLY (%d), zeroes the bonus tracker, clears the attacking latch" % sword_base,
		"cancel_swing left atk/bonus/attacking wrong (atk %d, base %d, tracker %d)" % [player._sword.atk, sword_base, player._combat._melee_bonus_applied])

	holder.queue_free()
	await ctx.tree.physics_frame


## FIX 2 -- the MELEE bonus lands on a NON-sword swing too, confirming EVERY swing path routes through
## _begin_swing (not just the sword arc the melee leg covers). Empties the equipped slot (the unarmed fist --
## a distinct _punch path), unlocks a MELEE talent, and begins a jab: the fist Hitbox atk includes the bonus
## mid-swing, then reverts to the unarmed base after.
func _nonsword_bonus_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0
	holder.add_child(player)
	player.global_position = HOME + Vector2(0, 14000)
	await ctx.settle_idle()
	await ctx.tree.physics_frame

	# Empty the equipped slot -> the unarmed fist (a NON-sword, NON-combo swing path: _punch).
	player.inventory.equip_index(5)  # slot 5 is empty (sword/axe/pickaxe seed slots 0-2)
	player._apply_equipped()
	ctx.check(player._is_unarmed and player._sword.atk == Player.UNARMED_ATK,
		"unarmed setup: no tool equipped, fist atk at the unarmed base (%d)" % Player.UNARMED_ATK,
		"unarmed setup failed (unarmed %s, atk %d)" % [str(player._is_unarmed), player._sword.atk])
	var fist_base: int = player._sword.atk

	player.character().progression.talent_points = 5
	player.character().unlock_talent(BLADE)  # MELEE +1

	# Begin the jab (unarmed -> _punch), NOT awaited: _begin_swing applies the +1 bonus onto the fist atk.
	player._combo_index = 0
	player.attack()
	ctx.check(player._combat.is_attacking() and player._sword.atk == fist_base + 1,
		"a NON-sword (unarmed jab) swing includes the melee bonus mid-swing (atk %d = base %d + 1)" % [player._sword.atk, fist_base],
		"the melee bonus did not land on the unarmed swing (atk %d, base %d)" % [player._sword.atk, fist_base])

	await _drain_swing(ctx, player)
	ctx.check(player._sword.atk == fist_base,
		"the unarmed swing's bonus is swing-scoped: fist atk reverts to the base (%d) after" % fist_base,
		"the unarmed swing leaked the bonus (atk %d, base %d)" % [player._sword.atk, fist_base])

	holder.queue_free()
	await ctx.tree.physics_frame


## Fell a fresh tree under `parent` at `at`, wait (watchdog) for its deferred fall+burst, and return the
## number of Wood drops it spawned. The tree bursts its wood via a tween callback only AFTER it topples, so
## a watchdog polls the drop count rather than assuming a same-frame spawn (mirrors test_harvest).
func _fell_and_count(ctx: TestContext, parent: Node, at: Vector2) -> int:
	var sub: Node2D = Node2D.new()
	parent.add_child(sub)
	var tree_node: StaticBody2D = TREE_SCENE.instantiate() as StaticBody2D
	sub.add_child(tree_node)
	tree_node.global_position = at
	await ctx.tree.physics_frame
	var expect: int = int(tree_node.get("yield_amount")) + player_bonus_hint(ctx)
	var mat: DurabilityComponent = tree_node.get_node("Material") as DurabilityComponent
	mat.wear(mat.current_durability)  # integrity -> 0 -> topple -> burst
	var watchdog: SceneTreeTimer = ctx.tree.create_timer(3.0)
	while _count_drops(sub) < expect and watchdog.time_left > 0.0:
		await ctx.tree.physics_frame
	return _count_drops(sub)


## Mine a fresh rock under `parent` at `at` exactly once (one affecting hit) and return the Stone drop count
## that single chip spawned. Rock integrity is > 1, so it survives the single mine (not freed).
func _mine_once_and_count(ctx: TestContext, parent: Node, at: Vector2) -> int:
	var sub: Node2D = Node2D.new()
	parent.add_child(sub)
	var rock_node: Rock = ROCK_SCENE.instantiate() as Rock
	sub.add_child(rock_node)
	rock_node.global_position = at
	await ctx.tree.physics_frame
	var mat: DurabilityComponent = rock_node.get_node("Material") as DurabilityComponent
	mat.wear(1)  # one affecting mine -> _on_integrity_changed chips its stone(s)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame  # settle the deferred drop add_child
	return _count_drops(sub)


## The group-resolved harvester's HARVEST_YIELD bonus, so _fell_and_count's watchdog knows how many drops to
## wait for (the SAME bonus the yield path reads). Resolves the "player" group exactly like the game code.
func player_bonus_hint(ctx: TestContext) -> int:
	var p: Player = ctx.tree.get_first_node_in_group("player") as Player
	return p.character().harvest_yield_bonus() if p != null else 0


## The live Drop instances directly under a node (empty if none). Mirrors test_harvest._drops.
func _count_drops(parent: Node) -> int:
	var n: int = 0
	for child in parent.get_children():
		if child is Drop:
			n += 1
	return n


## Drain any in-flight swing to completion (watchdog), so a started-but-not-awaited attack() finishes and
## its swing-scoped state (the MELEE bonus) is cleared before the next assertion. Mirrors the drain loops
## in test_combat / test_context.
func _drain_swing(ctx: TestContext, player: Player) -> void:
	for _i in range(60):
		if not player._attacking:
			return
		await ctx.tree.physics_frame

# Verified against: Godot 4.7.1 (2026-07-19)
