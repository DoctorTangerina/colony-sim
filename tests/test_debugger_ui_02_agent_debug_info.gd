extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Debugger UI Ticket 02 Test Harness (Agent.get_debug_info) ===")
	print("")

	_test_debug_info_shape_and_values_with_active_plan()
	_test_debug_info_degrades_to_empty_values_without_a_plan()
	_test_executing_action_reflects_goap_cycle_not_full_plan()

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


func _make_agent() -> Node:
	var agent_scene: PackedScene = preload("res://agents/agent.tscn")
	var agent = agent_scene.instantiate()
	add_child(agent)
	return agent


func _test_debug_info_shape_and_values_with_active_plan() -> void:
	print("[Test] get_debug_info() reports id/role/goal/action/stats/plan for an agent mid-plan")
	var agent = _make_agent()
	agent.agent_id = "agent_42"
	agent.energy = 72.5
	agent.hunger = 34.0
	agent._role_component.load_role("Gatherer")
	agent._goap_cycle.current_goal = "CollectFood"
	agent._goap_cycle.current_plan = ["MoveToFood", "PickupFood", "ReturnToNest"]
	agent._goap_cycle._action_index = 1
	agent._goap_cycle._action_in_progress = true

	var info: Dictionary = agent.get_debug_info()

	_assert(info.get("agent_id") == "agent_42", "agent_id matches (got: %s)" % info.get("agent_id"))
	_assert(info.get("role") == "Gatherer", "role matches (got: %s)" % info.get("role"))
	_assert(info.get("active_goal") == "CollectFood", "active_goal matches (got: %s)" % info.get("active_goal"))
	_assert(info.get("executing_action") == "PickupFood", "executing_action is the action at the current index (got: %s)" % info.get("executing_action"))
	_assert(is_equal_approx(info.get("energy"), 72.5), "energy matches (got: %s)" % info.get("energy"))
	_assert(is_equal_approx(info.get("hunger"), 34.0), "hunger matches (got: %s)" % info.get("hunger"))
	_assert(info.get("plan") == ["MoveToFood", "PickupFood", "ReturnToNest"], "plan is the ordered action-name list (got: %s)" % [info.get("plan")])


func _test_debug_info_degrades_to_empty_values_without_a_plan() -> void:
	print("[Test] get_debug_info() degrades to empty values (not stale ones) with no active goal/plan")
	var agent = _make_agent()
	agent._role_component.load_role("Unassigned")
	agent._goap_cycle.current_goal = ""
	agent._goap_cycle.current_plan = []
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = false

	var info: Dictionary = agent.get_debug_info()

	_assert(info.get("active_goal") == "", "active_goal is empty (got: %s)" % info.get("active_goal"))
	_assert(info.get("executing_action") == "", "executing_action is empty (got: %s)" % info.get("executing_action"))
	_assert(info.get("plan") == [], "plan is empty (got: %s)" % [info.get("plan")])


func _test_executing_action_reflects_goap_cycle_not_full_plan() -> void:
	print("[Test] executing_action is empty while a plan exists but no action is in progress")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")
	agent._goap_cycle.current_goal = "Explore"
	agent._goap_cycle.current_plan = ["RandomExplore"]
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = false

	var info: Dictionary = agent.get_debug_info()

	_assert(info.get("active_goal") == "Explore", "active_goal still reports the current goal (got: %s)" % info.get("active_goal"))
	_assert(info.get("executing_action") == "", "executing_action is empty when no action is in progress (got: %s)" % info.get("executing_action"))
	_assert(info.get("plan") == ["RandomExplore"], "plan still reports the queued actions (got: %s)" % [info.get("plan")])
