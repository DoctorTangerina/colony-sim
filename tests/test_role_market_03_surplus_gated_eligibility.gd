extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Role Market T03 Test Harness (Surplus-Gated Eligibility & Bookkeeping) ===")
	print("")

	await _test_assigned_non_surplus_agent_refuses_then_takes_once_surplus()
	await _test_unassigned_agent_takes_any_request_regardless_of_surplus()
	await _test_transition_to_unassigned_updates_holder_counts_truthfully()
	await _test_request_fulfilled_signal_fires_once_with_agent_and_role()

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


## Places the agent inside the nest and waits the frames the trigger zone
## needs to register it - prior art: test_goap_t11.
func _place_in_nest_and_wait(agent: Node, nest: Node2D) -> void:
	nest.global_position = Vector2.ZERO
	var nest_shape: CollisionShape2D = nest.get_node("CollisionShape2D")
	var nest_body_radius: float = (nest_shape.shape as CircleShape2D).radius
	agent.global_position = Vector2(nest_body_radius, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame


## Sets up an agent already assigned to `role_name` with no cooldown pending,
## bypassing set_role() (which would start the Role Cooldown) - mirrors how
## register_initial_role documents itself as pure initialization, not a
## role-change event.
func _assign_without_cooldown(agent: Node, om: Node, role_name: String) -> void:
	agent._role_component.load_role(role_name)
	agent._role_acquisition.current_role = role_name
	om.update_agent_role(agent.agent_id, role_name, "test_setup")


func _cleanup(agent: Node, nest: Node, om: Node) -> void:
	om.unregister_agent(agent.agent_id)
	om.clear_requests_for_role("Gatherer")
	om.clear_requests_for_role("Explorer")
	om.clear_requests_for_role("Unassigned")
	om._cached_targets = {}
	agent.queue_free()
	nest.queue_free()


func _test_assigned_non_surplus_agent_refuses_then_takes_once_surplus() -> void:
	print("[Test] An assigned agent whose role is at/under target refuses an open request; takes it once Surplus")
	var om = get_node("/root/OrganizationManager")

	var nest = _make_nest()
	var agent = _make_agent()
	agent.setup(nest, null)
	agent._goap_cycle.current_plan = []
	agent._goap_cycle.current_goal = ""

	_assign_without_cooldown(agent, om, "Gatherer")
	await _place_in_nest_and_wait(agent, nest)
	_assert(agent._nest_zone.is_in_nest_zone(), "Sanity check: agent is inside the nest trigger zone")

	om.post_request("Explorer")
	om._cached_targets["Gatherer"] = 5

	agent._role_acquisition.check_and_acquire_role()
	_assert(agent._role_component.get_role_name() == "Gatherer",
		"Gatherer under target refuses the open Explorer request (got: %s)" % agent._role_component.get_role_name())
	_assert(om.get_request_count("Explorer") == 1, "Explorer request is left untouched in the queue")

	om._cached_targets["Gatherer"] = 0
	agent._role_acquisition.check_and_acquire_role()
	_assert(agent._role_component.get_role_name() == "Explorer",
		"Gatherer now Surplus takes the Explorer request (got: %s)" % agent._role_component.get_role_name())
	_assert(om.get_request_count("Explorer") == 0, "Explorer request is consumed from the queue")

	_cleanup(agent, nest, om)


func _test_unassigned_agent_takes_any_request_regardless_of_surplus() -> void:
	print("[Test] An Unassigned agent takes any open request even when no role is Surplus")
	var om = get_node("/root/OrganizationManager")

	var nest = _make_nest()
	var agent = _make_agent()
	agent.setup(nest, null)
	agent._goap_cycle.current_plan = []
	agent._goap_cycle.current_goal = ""

	await _place_in_nest_and_wait(agent, nest)
	_assert(agent._nest_zone.is_in_nest_zone(), "Sanity check: agent is inside the nest trigger zone")
	_assert(agent._role_component.get_role_name() == "Unassigned", "Sanity check: agent starts Unassigned")

	om.post_request("Gatherer")
	om._cached_targets["Gatherer"] = 0
	om._cached_targets["Unassigned"] = 99

	agent._role_acquisition.check_and_acquire_role()
	_assert(agent._role_component.get_role_name() == "Gatherer",
		"Unassigned agent takes the Gatherer request despite no Surplus role (got: %s)" % agent._role_component.get_role_name())

	_cleanup(agent, nest, om)


func _test_transition_to_unassigned_updates_holder_counts_truthfully() -> void:
	print("[Test] A taken Unassigned request updates OM holder counts truthfully, closing the stale-bookkeeping gap")
	var om = get_node("/root/OrganizationManager")

	var nest = _make_nest()
	var agent = _make_agent()
	agent.setup(nest, null)
	agent._goap_cycle.current_plan = []
	agent._goap_cycle.current_goal = ""

	_assign_without_cooldown(agent, om, "Gatherer")
	await _place_in_nest_and_wait(agent, nest)

	var gatherer_before: int = om.get_role_count("Gatherer")
	var unassigned_before: int = om.get_role_count("Unassigned")

	om.post_request("Unassigned")
	om._cached_targets["Gatherer"] = 0

	agent._role_acquisition.check_and_acquire_role()
	_assert(agent._role_component.get_role_name() == "Unassigned",
		"Surplus Gatherer takes the Unassigned request (got: %s)" % agent._role_component.get_role_name())
	_assert(om.get_role_count("Gatherer") == gatherer_before - 1,
		"Gatherer holder count decrements on transition to Unassigned (got %d)" % om.get_role_count("Gatherer"))
	_assert(om.get_role_count("Unassigned") == unassigned_before + 1,
		"Unassigned holder count increments truthfully (got %d)" % om.get_role_count("Unassigned"))

	_cleanup(agent, nest, om)


func _test_request_fulfilled_signal_fires_once_with_agent_and_role() -> void:
	print("[Test] role_request_fulfilled fires exactly once per taken request, carrying the agent and role")
	var om = get_node("/root/OrganizationManager")

	var nest = _make_nest()
	var agent = _make_agent()
	agent.setup(nest, null)
	agent._goap_cycle.current_plan = []
	agent._goap_cycle.current_goal = ""

	await _place_in_nest_and_wait(agent, nest)

	var received: Array = []
	var callback := func(agent_id: String, role_name: String) -> void:
		received.append({"agent_id": agent_id, "role_name": role_name})
	om.role_request_fulfilled.connect(callback)

	om.post_request("Gatherer")
	agent._role_acquisition.check_and_acquire_role()

	om.role_request_fulfilled.disconnect(callback)

	_assert(received.size() == 1, "Signal fired exactly once (got %d)" % received.size())
	if received.size() == 1:
		_assert(received[0]["agent_id"] == agent.agent_id, "Signal carried the acquiring agent's id")
		_assert(received[0]["role_name"] == "Gatherer", "Signal carried the acquired role's name")

	_cleanup(agent, nest, om)
