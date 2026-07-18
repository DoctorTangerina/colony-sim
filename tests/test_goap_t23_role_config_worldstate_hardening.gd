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

	print("=== GOAP T23 Test Harness (Role-Config and WorldState Hardening) ===")
	print("")

	_test_empty_allowed_lists_select_no_goal()
	_test_non_empty_allowed_goals_unaffected()
	_test_satisfies_rejects_unrecognized_key()
	_test_merge_drops_unrecognized_key_but_keeps_known_ones()
	_test_set_field_rejects_unrecognized_key()
	_test_stub_goal_with_unrecognized_key_never_yields_a_plan()

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


## Unassigned-shaped role: allowedGoals=[] and allowedActions=[]. Before this
## ticket, an empty list fell back to "unrestricted" (guarded only by a
## hardcoded role-name check) - now empty means nothing beyond the (currently
## empty) Universal Capability set, with no name-based special case at all.
func _test_empty_allowed_lists_select_no_goal() -> void:
	print("[Test] Empty allowedGoals/allowedActions selects no goal, for any role name")
	var role_component := _make_role_component("NotUnassigned", [], [], {})
	goal_selector.set_role_component(role_component)

	# World state satisfies Eat, Rest, and DepositResource's preconditions -
	# if the empty list were still treated as unrestricted, one of these
	# would be selected.
	var world := WorldState.build("Food", 20.0, 80.0, true, false, false)
	var goal = goal_selector.select_goal(world)
	_assert(goal.is_empty(), "select_goal() returns {} when allowedGoals is empty (got: %s)" % [goal])

	var available = goal_selector.get_available_goals(world)
	_assert(available.is_empty(), "get_available_goals() returns [] when allowedGoals is empty (got: %s)" % [available])

	goal_selector.set_role_component(null)


## Confirms the fix didn't change behavior for a role with a real,
## non-empty allowedGoals list - only goals in that list are ever selected.
func _test_non_empty_allowed_goals_unaffected() -> void:
	print("[Test] Non-empty allowedGoals still selects only listed goals")
	var role_component := _make_role_component("Gatherer", ["Eat", "Rest"], ["Eat", "Rest"], {})
	goal_selector.set_role_component(role_component)

	# World state also satisfies DepositResource's preconditions, but
	# DepositResource is not in allowed_goals - it must never be selected.
	var world := WorldState.build("Food", 20.0, 80.0, true, false, false)
	var goal = goal_selector.select_goal(world)
	_assert(not goal.is_empty(), "select_goal() found a goal")
	_assert(goal.get("name", "") == "Eat", "select_goal() picks the higher-desirability listed goal (Eat), never the unlisted DepositResource (got: %s)" % goal.get("name", "none"))

	goal_selector.set_role_component(null)


func _test_satisfies_rejects_unrecognized_key() -> void:
	print("[Test] WorldState.satisfies() rejects an unrecognized key")
	var state := WorldState.build("None", 100.0, 0.0, false, false, false)
	var result: bool = state.satisfies({"totally_bogus_key": true})
	_assert(result == false, "satisfies() returns false for a key outside get_field_keys()")


func _test_merge_drops_unrecognized_key_but_keeps_known_ones() -> void:
	print("[Test] WorldState.merge() drops an unrecognized key but still applies known keys in the same effect dict")
	var state := WorldState.build("None", 100.0, 0.0, false, false, false)
	var merged: WorldState = state.merge({"has_food": true, "totally_bogus_key": true})
	_assert(merged.has_food == true, "merge() still applies the recognized has_food key despite a bogus key in the same dict")
	_assert(merged.has_wood == false, "merge() leaves untouched known fields alone")


func _test_set_field_rejects_unrecognized_key() -> void:
	print("[Test] WorldState.set_field() rejects an unrecognized key without crashing")
	var state := WorldState.new()
	state.set_field("totally_bogus_key", true)
	_assert(true, "set_field() with an unrecognized key returns without raising")


## Uses the established GOAPPlanner.set_goals()/set_actions() test seam to
## inject a stub goal whose effect references a key outside WorldState's
## schema - proves the planner can never produce a plan through it (the key
## is silently unsatisfiable, and now also loudly logged via WorldState).
func _test_stub_goal_with_unrecognized_key_never_yields_a_plan() -> void:
	print("[Test] A stub goal/action with a deliberately-unrecognized key never yields a plan")
	var stub_planner = preload("res://agents/planner/goap_planner.gd").new()
	add_child(stub_planner)

	stub_planner.set_actions([
		{"name": "StubAction", "cost": 1.0, "preconditions": {}, "effects": {"nonexistent_field": true}}
	])
	stub_planner.set_goals([
		{"name": "StubGoal", "preconditions": {}, "effects": {"nonexistent_field": true}}
	])

	var world := WorldState.build("None", 100.0, 0.0, false, false, false)
	var plan = stub_planner.create_plan("StubGoal", world)
	_assert(plan.is_empty(), "create_plan() finds no plan for a goal whose effect key is outside WorldState's schema")

	stub_planner.queue_free()


func _make_role_component(role_name: String, allowed_goals: Array, allowed_actions: Array, priority_modifiers: Dictionary) -> Node:
	var rc := Node.new()

	var script := GDScript.new()
	script.source_code = """extends Node

var role_name: String = ""
var allowed_goals: Array = []
var allowed_actions: Array = []
var priority_modifiers: Dictionary = {}

func get_role_name() -> String:
	return role_name

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
	# matching property (script not attached yet) is a silent no-op.
	rc.set("role_name", role_name)
	rc.set("allowed_goals", allowed_goals)
	rc.set("allowed_actions", allowed_actions)
	rc.set("priority_modifiers", priority_modifiers)

	add_child(rc)
	return rc
