extends Node

var planner = null
var goal_selector = null
var tests_passed: int = 0
var tests_failed: int = 0
var _signal_received := false
var _old_role := ""
var _new_role := ""


func _ready() -> void:
	var PlannerScript = preload("res://agents/planner/goap_planner.gd")
	var GoalSelectorScript = preload("res://agents/goal_selector.gd")
	var RoleComponentScript = preload("res://agents/role_component.gd")

	planner = PlannerScript.new()
	add_child(planner)

	goal_selector = GoalSelectorScript.new()
	add_child(goal_selector)
	goal_selector.initialize(planner)

	print("=== GOAP T3 Test Harness (Role Component) ===")
	print("")

	_test_role_loads_explorer()
	_test_role_loads_gatherer()
	_test_role_loads_guard()
	_test_role_unassigned_empty()
	_test_global_actions_always_included()
	_test_priority_modifier_applied()
	_test_role_change_clears_goal()
	_test_explorer_restricted_goals()
	_test_gatherer_restricted_goals()

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


func _make_role_component() -> Node:
	var RoleComponentScript = preload("res://agents/role_component.gd")
	var rc = RoleComponentScript.new()
	add_child(rc)
	return rc


func _test_role_loads_explorer() -> void:
	print("[Test] RoleComponent loads Explorer")
	var rc = _make_role_component()
	rc.load_role("Explorer")
	_assert(rc.get_role_name() == "Explorer", "Role name is Explorer")
	_assert(rc.get_allowed_goals().size() > 0, "Explorer has allowed goals")
	_assert("Explore" in rc.get_allowed_goals(), "Explorer can Explore")


func _test_role_loads_gatherer() -> void:
	print("[Test] RoleComponent loads Gatherer")
	var rc = _make_role_component()
	rc.load_role("Gatherer")
	_assert(rc.get_role_name() == "Gatherer", "Role name is Gatherer")
	_assert("CollectFood" in rc.get_allowed_goals(), "Gatherer can CollectFood")
	_assert("CollectWood" in rc.get_allowed_goals(), "Gatherer can CollectWood")
	_assert("DepositResource" in rc.get_allowed_goals(), "Gatherer can DepositResource")


func _test_role_loads_guard() -> void:
	print("[Test] RoleComponent loads Guard")
	var rc = _make_role_component()
	rc.load_role("Guard")
	_assert(rc.get_role_name() == "Guard", "Role name is Guard")
	_assert("DefendNest" in rc.get_allowed_goals(), "Guard can DefendNest")
	_assert("AttackEnemy" in rc.get_allowed_goals(), "Guard can AttackEnemy")


func _test_role_unassigned_empty() -> void:
	print("[Test] Unassigned role has empty lists")
	var rc = _make_role_component()
	rc.load_role("Unassigned")
	_assert(rc.get_role_name() == "Unassigned", "Role name is Unassigned")
	_assert(rc.get_allowed_goals().size() == 0, "Unassigned has no allowed goals")
	_assert(rc.get_allowed_actions().size() == 2, "Unassigned has only global actions")


func _test_global_actions_always_included() -> void:
	print("[Test] Global actions always included")
	var rc = _make_role_component()
	rc.load_role("Explorer")
	var actions = rc.get_allowed_actions()
	_assert("Eat" in actions, "Explorer has Eat action")
	_assert("Rest" in actions, "Explorer has Rest action")


func _test_priority_modifier_applied() -> void:
	print("[Test] Priority modifiers from role config")
	var rc = _make_role_component()
	rc.load_role("Explorer")
	_assert(rc.get_priority_modifier("Explore") == 2.0, "Explorer Explore modifier is 2.0")
	_assert(rc.get_priority_modifier("Eat") == 0.5, "Explorer Eat modifier is 0.5")
	_assert(rc.get_priority_modifier("Unknown") == 1.0, "Unknown goal modifier is 1.0")


func _test_role_change_clears_goal() -> void:
	print("[Test] Role change emits signal")
	var rc = _make_role_component()
	_signal_received = false
	_old_role = ""
	_new_role = ""
	rc.role_changed.connect(_on_role_changed_signal)
	rc.load_role("Explorer")
	_assert(_signal_received, "Role changed signal emitted")
	_assert(_old_role == "" or _old_role == "Unassigned", "Old role is empty or Unassigned")
	_assert(_new_role == "Explorer", "New role is Explorer")

	_signal_received = false
	_old_role = ""
	_new_role = ""
	rc.load_role("Gatherer")
	_assert(_signal_received, "Role changed signal emitted again")
	_assert(_old_role == "Explorer", "Old role is Explorer")
	_assert(_new_role == "Gatherer", "New role is Gatherer")


func _on_role_changed_signal(old_role: String, new_role: String) -> void:
	_signal_received = true
	_old_role = old_role
	_new_role = new_role


func _test_explorer_restricted_goals() -> void:
	print("[Test] Explorer cannot CollectFood")
	var rc = _make_role_component()
	rc.load_role("Explorer")
	_assert(not rc.has_goal("CollectFood"), "Explorer cannot CollectFood")
	_assert(not rc.has_goal("CollectWood"), "Explorer cannot CollectWood")
	_assert(not rc.has_goal("DefendNest"), "Explorer cannot DefendNest")


func _test_gatherer_restricted_goals() -> void:
	print("[Test] Gatherer cannot Explore")
	var rc = _make_role_component()
	rc.load_role("Gatherer")
	_assert(not rc.has_goal("Explore"), "Gatherer cannot Explore")
	_assert(not rc.has_goal("DefendNest"), "Gatherer cannot DefendNest")
