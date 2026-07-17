extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T20 Test Harness (GoapCycle Agent Decomposition) ===")
	print("")

	_test_goap_cycle_is_a_child_node()
	_test_process_delegates_to_goap_cycle()
	_test_role_change_clears_plan_immediately()
	_test_agent_selects_goal_and_executes_plan_through_goap_cycle()

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


func _test_goap_cycle_is_a_child_node() -> void:
	print("[Test] Agent owns a GoapCycle child node that holds the planning loop")
	var agent = _make_agent()
	_assert(agent._goap_cycle != null, "GoapCycle child node exists")
	_assert(agent._goap_cycle.has_method("run_planning_cycle"), "GoapCycle exposes run_planning_cycle")
	_assert(agent._goap_cycle.has_method("on_action_completed"), "GoapCycle exposes on_action_completed")
	_assert(agent._goap_cycle.has_method("on_role_changed"), "GoapCycle exposes on_role_changed")


func _test_process_delegates_to_goap_cycle() -> void:
	print("[Test] agent._process(delta) drives GoapCycle's planning timer rather than a timer on agent itself")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")

	_assert(agent._goap_cycle.current_goal == "", "No goal selected before any process tick")

	agent._process(2.5)

	_assert(agent._goap_cycle.current_goal != "",
		"GoapCycle selected a goal once agent._process ticked past the planning interval (got: %s)" % agent._goap_cycle.current_goal)


func _test_role_change_clears_plan_immediately() -> void:
	print("[Test] Role change signal clears the in-flight plan immediately, without waiting for the next planning tick")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")
	agent._goap_cycle.current_goal = "Explore"
	agent._goap_cycle.current_plan = ["RandomExplore"]
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = true

	agent._role_acquisition.setup(agent._get_om(), agent._role_component, agent._nest_zone, agent.agent_id, 10.0)
	agent._role_acquisition.set_role("Gatherer")

	_assert(agent._goap_cycle.current_goal == "", "current_goal cleared immediately on role change (got: %s)" % agent._goap_cycle.current_goal)
	_assert(agent._goap_cycle.current_plan.is_empty(), "current_plan cleared immediately on role change (got: %s)" % [agent._goap_cycle.current_plan])
	_assert(not agent._goap_cycle._action_in_progress, "action_in_progress cleared immediately on role change")

	agent._get_om().clear_requests_for_role("Gatherer")


func _test_agent_selects_goal_and_executes_plan_through_goap_cycle() -> void:
	print("[Test] Agent still selects goals, builds plans, and starts executing them through GoapCycle")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")

	agent._goap_cycle.run_planning_cycle()

	_assert(agent._goap_cycle.current_goal != "", "GoapCycle selected a goal (got: %s)" % agent._goap_cycle.current_goal)
	_assert(not agent._goap_cycle.current_plan.is_empty(), "GoapCycle built a non-empty plan (got: %s)" % [agent._goap_cycle.current_plan])
	_assert(agent._goap_cycle._action_in_progress, "GoapCycle started executing the first action")
