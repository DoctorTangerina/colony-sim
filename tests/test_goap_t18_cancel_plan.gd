extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T18 Test Harness (Cancel Plan) ===")
	print("")

	_test_cancel_plan_is_callable_without_error()
	_test_role_change_calls_planner_cancel_plan()
	_test_no_stale_plan_or_action_survives_a_role_change()

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


## Wraps the agent's real planner, counting cancel_plan() calls while
## forwarding everything else - used to prove GoapCycle actually calls
## through to the planner's API rather than only clearing its own state.
func _make_cancel_spy_planner(real_planner: Node) -> Node:
	var script := GDScript.new()
	script.source_code = """extends Node
var cancel_plan_calls: int = 0
var real = null

func create_plan(goal_name: String, world_state, allowed_actions: Array = []) -> Array:
	return real.create_plan(goal_name, world_state, allowed_actions)

func validate_plan(plan: Array, world_state) -> bool:
	return real.validate_plan(plan, world_state)

func cancel_plan() -> void:
	cancel_plan_calls += 1
	real.cancel_plan()
"""
	script.reload()
	var spy = script.new()
	spy.real = real_planner
	add_child(spy)
	return spy


func _test_cancel_plan_is_callable_without_error() -> void:
	print("[Test] GoapPlanner.cancel_plan() is a real callable method, not a missing stub")
	var agent = _make_agent()
	agent._planner.cancel_plan()
	_assert(agent._planner.has_method("cancel_plan"), "GoapPlanner exposes cancel_plan()")


func _test_role_change_calls_planner_cancel_plan() -> void:
	print("[Test] A role change routes through GoapCycle to GoapPlanner.cancel_plan()")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")

	var spy := _make_cancel_spy_planner(agent._planner)
	agent._goap_cycle._planner = spy

	agent._role_acquisition.setup(agent._get_om(), agent._role_component, agent._nest_zone, agent.agent_id, 10.0)
	agent._role_acquisition.set_role("Gatherer")

	_assert(spy.cancel_plan_calls == 1, "planner.cancel_plan() was called exactly once on role change (got %d)" % spy.cancel_plan_calls)


func _test_no_stale_plan_or_action_survives_a_role_change() -> void:
	print("[Test] No stale plan or in-progress action survives a role change")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")
	agent._goap_cycle.current_goal = "Explore"
	agent._goap_cycle.current_plan = ["RandomExplore"]
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = true

	agent._role_acquisition.setup(agent._get_om(), agent._role_component, agent._nest_zone, agent.agent_id, 10.0)
	agent._role_acquisition.set_role("Gatherer")

	_assert(agent._goap_cycle.current_goal == "", "Stale Explore goal was dropped (got: %s)" % agent._goap_cycle.current_goal)
	_assert(agent._goap_cycle.current_plan.is_empty(), "Stale RandomExplore plan was dropped (got: %s)" % [agent._goap_cycle.current_plan])
	_assert(not agent._goap_cycle._action_in_progress, "No action is left in-progress after the role change")

	agent._get_om().clear_requests_for_role("Gatherer")
