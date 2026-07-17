extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T9 Test Harness (Unassigned Idle Energy Recovery) ===")
	print("")

	_test_unassigned_agent_stands_still()
	_test_unassigned_agent_stops_in_flight_navigation()
	_test_unassigned_agent_energy_rises_over_time()
	_test_unassigned_agent_selects_no_goal_or_plan()
	_test_role_acquisition_resumes_normal_planning()

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


func _test_unassigned_agent_stands_still() -> void:
	print("[Test] Unassigned agent's velocity is zeroed by the planning cycle")
	var agent = _make_agent()
	agent._role_component.load_role("Unassigned")
	agent.velocity = Vector2(999, 999)

	agent._run_planning_cycle()

	_assert(agent.velocity == Vector2.ZERO, "Velocity is Vector2.ZERO after an Unassigned planning cycle")


func _test_unassigned_agent_stops_in_flight_navigation() -> void:
	print("[Test] Unassigned agent's in-flight navigation is cancelled, not just its velocity")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")
	agent._navigator.move_to(Vector2(500, 500))
	_assert(agent._navigator.is_moving(), "Navigator is mid-move before the role change")

	agent._role_component.load_role("Unassigned")
	agent._run_planning_cycle()
	_assert(not agent._navigator.is_moving(), "Navigator move was cancelled by the Unassigned cycle")

	agent.velocity = Vector2(999, 999)
	agent._navigator.process(0.1)
	_assert(agent.velocity == Vector2(999, 999),
		"A stale in-flight move no longer overwrites velocity next frame (Navigator.process is a no-op once stopped)")


func _test_unassigned_agent_energy_rises_over_time() -> void:
	print("[Test] Unassigned agent energy rises across successive planning cycles")
	var agent = _make_agent()
	agent._role_component.load_role("Unassigned")
	agent.energy = 50.0

	agent._run_planning_cycle()
	var after_one: float = agent.energy
	agent._run_planning_cycle()
	var after_two: float = agent.energy

	_assert(after_one > 50.0, "Energy increased after one planning cycle (got %s)" % after_one)
	_assert(after_two > after_one, "Energy increased further after a second cycle (got %s)" % after_two)


func _test_unassigned_agent_selects_no_goal_or_plan() -> void:
	print("[Test] Unassigned agent builds no goal and no plan")
	var agent = _make_agent()
	agent._role_component.load_role("Unassigned")
	agent.current_goal = "CollectFood"
	agent.current_plan = ["PickupFood"]

	agent._run_planning_cycle()

	_assert(agent.current_goal == "", "current_goal cleared for Unassigned (got: %s)" % agent.current_goal)
	_assert(agent.current_plan.is_empty(), "current_plan cleared for Unassigned (got: %s)" % [agent.current_plan])


func _test_role_acquisition_resumes_normal_planning() -> void:
	print("[Test] Accepting a role resumes normal goal selection")
	var agent = _make_agent()
	agent._role_component.load_role("Unassigned")
	agent._run_planning_cycle()
	_assert(agent.current_goal == "", "Agent has no goal while Unassigned")

	agent._role_component.load_role("Explorer")
	agent._run_planning_cycle()

	_assert(agent.current_goal != "", "Agent selected a real goal once assigned a role (got: %s)" % agent.current_goal)
