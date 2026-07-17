extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T11 Test Harness (Event-Driven Role Acquisition) ===")
	print("")

	_test_role_acquisition_has_no_process_method()
	_test_get_cooldown_is_zero_before_any_role_change()
	_test_get_cooldown_is_positive_immediately_after_role_change()
	await _test_agent_picks_up_role_request_immediately_on_action_completed_in_nest_zone()
	await _test_agent_does_not_pick_up_role_request_on_action_completed_outside_nest_zone()

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


func _make_nest() -> Node2D:
	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	return nest


func _test_role_acquisition_has_no_process_method() -> void:
	print("[Test] RoleAcquisition no longer exposes a per-frame process(delta) method")
	var agent = _make_agent()
	_assert(not agent._role_acquisition.has_method("process"),
		"RoleAcquisition timer-based polling was removed")


func _test_get_cooldown_is_zero_before_any_role_change() -> void:
	print("[Test] get_cooldown() is zero before any role has been acquired")
	var agent = _make_agent()
	_assert(agent._role_acquisition.get_cooldown() == 0.0, "Fresh RoleAcquisition has no cooldown")


func _test_get_cooldown_is_positive_immediately_after_role_change() -> void:
	print("[Test] get_cooldown() is positive immediately after set_role, with no process() ticks")
	var agent = _make_agent()
	agent._role_acquisition.setup(agent._get_om(), agent._role_component, agent._nest_zone, agent.agent_id, 10.0)

	agent._role_acquisition.set_role("Gatherer")

	_assert(agent._role_acquisition.get_cooldown() > 0.0,
		"Cooldown is active right after a role change (got %s)" % agent._role_acquisition.get_cooldown())


func _test_agent_picks_up_role_request_immediately_on_action_completed_in_nest_zone() -> void:
	print("[Test] Agent finishes an action in the nest zone and immediately picks up a pending Gatherer request")
	var om = get_node("/root/OrganizationManager")

	var nest = _make_nest()
	nest.global_position = Vector2.ZERO

	var agent = _make_agent()
	agent.setup(nest, null)
	agent._role_component.load_role("Unassigned")
	agent.current_plan = []
	agent.current_goal = ""

	var nest_shape: CollisionShape2D = nest.get_node("CollisionShape2D")
	var nest_body_radius: float = (nest_shape.shape as CircleShape2D).radius
	agent.global_position = Vector2(nest_body_radius, 0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(agent._nest_zone.is_in_nest_zone(), "Sanity check: agent is inside the nest trigger zone")

	om.post_request("Gatherer")

	agent._on_action_completed()

	_assert(agent._role_component.get_role_name() == "Gatherer",
		"Agent acquired the Gatherer role immediately from _on_action_completed (got: %s)" % agent._role_component.get_role_name())

	om.clear_requests_for_role("Gatherer")


func _test_agent_does_not_pick_up_role_request_on_action_completed_outside_nest_zone() -> void:
	print("[Test] Agent finishing an action outside the nest zone does not immediately acquire a pending role")
	var om = get_node("/root/OrganizationManager")

	var nest = _make_nest()
	nest.global_position = Vector2.ZERO

	var agent = _make_agent()
	agent.setup(nest, null)
	agent._role_component.load_role("Unassigned")
	agent.current_plan = []
	agent.current_goal = ""
	agent.global_position = Vector2(5000, 5000)

	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(not agent._nest_zone.is_in_nest_zone(), "Sanity check: agent is outside the nest trigger zone")

	om.post_request("Explorer")

	agent._on_action_completed()

	_assert(agent._role_component.get_role_name() == "Unassigned",
		"Agent did not acquire a role while outside the nest zone (got: %s)" % agent._role_component.get_role_name())

	om.clear_requests_for_role("Explorer")
