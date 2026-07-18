extends Node

var planner = null
var goal_selector = null
var tests_passed: int = 0
var tests_failed: int = 0

var WorldState = preload("res://agents/WorldState.gd")


func _ready() -> void:
	var PlannerScript = preload("res://agents/planner/goap_planner.gd")
	var GoalSelectorScript = preload("res://agents/goal_selector.gd")

	planner = PlannerScript.new()
	planner.name = "GOAPPlanner"
	add_child(planner)

	goal_selector = GoalSelectorScript.new()
	goal_selector.name = "GOAPGoalSelector"
	add_child(goal_selector)
	goal_selector.initialize(planner)

	print("=== GOAP T1 Test Harness ===")
	print("")

	_test_planner_finds_eat_plan()
	_test_planner_finds_rest_plan()
	_test_planner_finds_deposit_plan_with_goto_leg_when_away_from_nest()
	_test_planner_finds_deposit_plan()
	_test_planner_finds_collect_food_plan()
	_test_planner_finds_explore_plan()
	_test_planner_rejects_impossible_goal()
	_test_planner_validate_plan()
	_test_goal_selector_selects_eat_when_hungry()
	_test_goal_selector_selects_rest_when_tired()
	_test_goal_selector_selects_explore_for_explorer()
	_test_goal_selector_selects_collect_for_gatherer()

	print("")
	print("=== Results: %d passed, %d failed ===" % [tests_passed, tests_failed])
	get_tree().quit(0 if tests_failed == 0 else 1)


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		tests_passed += 1
		print("  PASS: %s" % test_name)
	else:
		tests_failed += 1
		print("  FAIL: %s" % test_name)


func _test_planner_finds_eat_plan() -> void:
	print("[Test] Planner finds Eat plan")
	var world := WorldState.build("Food", 100.0, 80.0, false, false, false)
	var plan = planner.create_plan("Eat", world)
	_assert(plan.size() > 0, "Eat plan is not empty")
	_assert("Eat" in plan, "Eat plan contains Eat action")


func _test_planner_finds_rest_plan() -> void:
	print("[Test] Planner finds Rest plan")
	var world := WorldState.build("None", 20.0, 0.0, true, false, false)
	var plan = planner.create_plan("Rest", world)
	_assert(plan.size() > 0, "Rest plan is not empty")
	_assert("Rest" in plan, "Rest plan contains Rest action")


## The core Ticket 2 fix (ADR 5 defect #1): DepositResource's goal precondition
## is relevance-only (has_item), never reachability - the Planner is expected
## to chain in the universal, grounded GoTo[Nest] itself when away from the
## nest, rather than the goal being unselectable until already there. Held
## item is Wood, not Food: Eat also clears has_food (a pre-existing, ticket-2-
## unrelated quirk of DepositResource's effects being expressed in terms of
## has_food/has_wood) and ties DepositResource's cost when holding Food away
## from the nest, which would make this test assert on an ambiguous plan.
func _test_planner_finds_deposit_plan_with_goto_leg_when_away_from_nest() -> void:
	print("[Test] Planner finds DepositResource plan with a GoTo[Nest] leg when away from the nest")
	var world := WorldState.build("Wood", 100.0, 0.0, false, false, false)
	var plan = planner.create_plan("DepositResource", world)
	_assert(plan.size() > 0, "DepositResource plan is not empty when away from the nest")
	_assert("GoTo[Nest]" in plan, "Plan contains a GoTo[Nest] leg")
	_assert("DepositResource" in plan, "Plan contains DepositResource")
	_assert(plan.find("GoTo[Nest]") < plan.find("DepositResource"), "GoTo[Nest] happens before DepositResource")


func _test_planner_finds_deposit_plan() -> void:
	print("[Test] Planner finds DepositResource plan")
	var world := WorldState.build("Food", 100.0, 0.0, true, false, false)
	var plan = planner.create_plan("DepositResource", world)
	_assert(plan.size() > 0, "DepositResource plan is not empty")
	_assert("DepositResource" in plan, "DepositResource plan contains DepositResource action")


func _test_planner_finds_collect_food_plan() -> void:
	print("[Test] Planner finds CollectFood plan")
	var world := WorldState.build("None", 100.0, 0.0, false, false, false, false, true, false)
	var plan = planner.create_plan("CollectFood", world)
	_assert(plan.size() > 0, "CollectFood plan is not empty")
	_assert("PickupFood" in plan, "CollectFood plan contains PickupFood action")


func _test_planner_finds_explore_plan() -> void:
	print("[Test] Planner finds Explore plan")
	var world := WorldState.build("None", 100.0, 0.0, false, false, false)
	var plan = planner.create_plan("Explore", world)
	_assert(plan.size() > 0, "Explore plan is not empty")
	_assert("RandomExplore" in plan, "Explore plan contains RandomExplore action")


func _test_planner_rejects_impossible_goal() -> void:
	print("[Test] Planner rejects impossible goal")
	var world := WorldState.build("None", 100.0, 0.0, false, false, false)
	var plan = planner.create_plan("Eat", world)
	_assert(plan.size() == 0, "Eat plan is empty when no food")


func _test_planner_validate_plan() -> void:
	print("[Test] Planner validates plan")
	var world := WorldState.build("Food", 100.0, 0.0, false, false, false)
	var plan := ["GoTo[Nest]", "Eat"]
	var valid = planner.validate_plan(plan, world)
	_assert(valid, "GoTo[Nest]+Eat plan is valid from has_food+!at_nest")

	var invalid_plan := ["DepositResource"]
	var invalid = planner.validate_plan(invalid_plan, world)
	_assert(not invalid, "DepositResource is invalid when agent has no item")


func _test_goal_selector_selects_eat_when_hungry() -> void:
	print("[Test] GoalSelector selects Eat when hungry")
	var role_component := _make_role_component(["Eat", "Rest"], [], {})
	goal_selector.set_role_component(role_component)

	var world := WorldState.build("Food", 100.0, 80.0, false, false, false)
	var goal = goal_selector.select_goal(world)
	_assert(not goal.is_empty(), "GoalSelector found a goal")
	_assert(goal.get("name", "") == "Eat", "GoalSelector selects Eat (got: %s)" % goal.get("name", "none"))

	goal_selector.set_role_component(null)


func _test_goal_selector_selects_rest_when_tired() -> void:
	print("[Test] GoalSelector selects Rest when tired")
	var role_component := _make_role_component(["Eat", "Rest"], [], {})
	goal_selector.set_role_component(role_component)

	var world := WorldState.build("None", 20.0, 0.0, true, false, false)
	var goal = goal_selector.select_goal(world)
	_assert(not goal.is_empty(), "GoalSelector found a goal")
	_assert(goal.get("name", "") == "Rest", "GoalSelector selects Rest (got: %s)" % goal.get("name", "none"))

	goal_selector.set_role_component(null)


func _test_goal_selector_selects_explore_for_explorer() -> void:
	print("[Test] GoalSelector selects Explore for Explorer role")
	var role_component := _make_role_component(
		["Explore", "Eat", "Rest"],
		[],
		{"Explore": 2.0}
	)
	goal_selector.set_role_component(role_component)

	var world := WorldState.build("None", 100.0, 0.0, true, false, false)
	var goal = goal_selector.select_goal(world)
	_assert(not goal.is_empty(), "GoalSelector found a goal")
	var goal_name = goal.get("name", "")
	_assert(goal_name == "Explore", "GoalSelector selects Explore for Explorer (got: %s)" % goal_name)

	goal_selector.set_role_component(null)


func _test_goal_selector_selects_collect_for_gatherer() -> void:
	print("[Test] GoalSelector selects Collect for Gatherer role")
	var role_component := _make_role_component(
		["CollectFood", "CollectWood", "DepositResource", "Eat", "Rest"],
		[],
		{"CollectFood": 2.0, "CollectWood": 2.0}
	)
	goal_selector.set_role_component(role_component)

	var world := WorldState.build("None", 100.0, 0.0, false, false, false, false, true, false)
	var goal = goal_selector.select_goal(world)
	_assert(not goal.is_empty(), "GoalSelector found a goal")
	var goal_name = goal.get("name", "")
	_assert(goal_name == "CollectFood" or goal_name == "CollectWood",
		"GoalSelector selects Collect for Gatherer (got: %s)" % goal_name)

	goal_selector.set_role_component(null)


func _make_role_component(allowed_goals: Array, allowed_actions: Array, priority_modifiers: Dictionary) -> Node:
	var rc := Node.new()

	var script := GDScript.new()
	script.source_code = """extends Node

var allowed_goals: Array = []
var allowed_actions: Array = []
var priority_modifiers: Dictionary = {}

func get_allowed_goals() -> Array:
	return allowed_goals

func get_allowed_actions() -> Array:
	return allowed_actions

func get_priority_modifier(goal_name: String) -> float:
	return priority_modifiers.get(goal_name, 1.0)
"""
	script.reload()
	rc.set_script(script)

	# Must run after set_script(): Object.set() on a plain Node with no
	# matching property (script not attached yet) is a silent no-op, not a
	# deferred assignment - these would otherwise be dropped and every
	# stub role component would report empty allowed_goals/allowed_actions
	# regardless of what's passed in here.
	rc.set("allowed_goals", allowed_goals)
	rc.set("allowed_actions", allowed_actions)
	rc.set("priority_modifiers", priority_modifiers)

	add_child(rc)
	return rc
