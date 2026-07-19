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

## The four authored tree ids (data/talents/*.tres). keen_edge is the prereq node (requires blade_focus).
const BLADE: StringName = &"blade_focus"    # root, cost 1, MELEE_DAMAGE +1
const KEEN: StringName = &"keen_edge"        # cost 2, prereq [blade_focus], MELEE_DAMAGE +1
const FORAGER: StringName = &"forager"       # root, cost 1, HARVEST_YIELD +1
const HEAVY: StringName = &"heavy_hitter"    # root, cost 2, MELEE_DAMAGE +2


func run(ctx: TestContext) -> void:
	print("[talents] --- talent tree unlock/prereq/spend (points gate + prereq gate + exact cost) ---")
	_tree_tests(ctx)
	_points_gate_tests(ctx)
	_prereq_and_set_tests(ctx)


## Tree-shape + fresh-state tests -- the authored nodes are present at the documented costs/prereqs and a
## brand-new Talents has nothing unlocked. No unlock yet; pure reads.
func _tree_tests(ctx: TestContext) -> void:
	var t: Talents = Talents.new()

	# The authored tree has all four nodes and no strays.
	ctx.check(t.tree().size() == 4 and t.has_talent(BLADE) and t.has_talent(KEEN)
			and t.has_talent(FORAGER) and t.has_talent(HEAVY),
		"talent tree loads the 4 authored nodes (blade_focus, keen_edge, forager, heavy_hitter)",
		"talent tree missing a node or wrong size (size %d)" % t.tree().size())

	# Costs + the one prereq edge match the authored .tres (pins the tree the test reasons about).
	var keen: TalentData = t.get_talent(KEEN)
	ctx.check(t.get_talent(BLADE).cost == 1 and keen.cost == 2 and t.get_talent(FORAGER).cost == 1
			and t.get_talent(HEAVY).cost == 2 and keen.prereqs.size() == 1 and keen.prereqs[0] == BLADE,
		"authored costs (blade 1, keen 2, forager 1, heavy 2) and keen_edge's prereq (blade_focus) match",
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

# Verified against: Godot 4.7.1 (2026-07-19)
