extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Debugger UI Ticket 01 Test Harness (Agent Registry Lifecycle) ===")
	print("")

	await _test_agents_register_at_spawn_with_starting_role()
	await _test_agent_unregistered_on_death()
	await _test_id_resolves_to_live_agent_node()
	await _test_role_counts_stay_correct_through_spawn_role_change_death()

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


## Dynamic role evaluation fires on the very first tick (both the OM's eval
## timer and each agent's planning timer start at 0.0), so a freshly spawned
## agent can leave Unassigned before these registry-bookkeeping tests get a
## chance to inspect it. These tests aren't about role-market dynamics (that's
## covered in tests/test_role_market_03), so dynamic roles are disabled for
## their duration to keep spawn/registration state deterministic.
func _make_sim(om: Node) -> Node2D:
	var sim = preload("res://simulation/Simulation.tscn").instantiate()
	om.set_dynamic_roles(false)
	add_child(sim)
	return sim


func _cleanup(sim: Node, om: Node) -> void:
	for agent_id in om.get_registered_agent_ids():
		om.unregister_agent(agent_id)
	om.set_dynamic_roles(true)
	sim.queue_free()
	await get_tree().physics_frame


func _test_agents_register_at_spawn_with_starting_role() -> void:
	print("[Test] Every agent in the scene registers with the OM at spawn, with its starting role")
	var om = get_node("/root/OrganizationManager")
	var sim = _make_sim(om)

	for i in range(15):
		await get_tree().physics_frame

	var config: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	var expected_count: int = config.get("agentCount", 8)

	_assert(om.get_total_agent_count() == expected_count, "All configured Simulation.tscn agents registered (got %d, expected %d)" % [om.get_total_agent_count(), expected_count])
	_assert(om.get_role_count("Unassigned") == expected_count, "All agents start Unassigned (got %d)" % om.get_role_count("Unassigned"))

	await _cleanup(sim, om)


func _test_agent_unregistered_on_death() -> void:
	print("[Test] An agent dying results in agent_unregistered being emitted (no silent registry removal)")
	var om = get_node("/root/OrganizationManager")
	var sim = _make_sim(om)

	for i in range(15):
		await get_tree().physics_frame

	var agent_ids: Array = om.get_registered_agent_ids()
	var total_before: int = agent_ids.size()
	var death_agent_id: String = agent_ids[0]
	var agent = om.get_agent_node(death_agent_id)

	var received := {"fired": false, "agent_id": ""}
	om.agent_unregistered.connect(func(aid: String) -> void:
		received["fired"] = true
		received["agent_id"] = aid
	)

	agent.energy = 0.0
	agent._check_death()

	_assert(received["fired"], "agent_unregistered signal fired on death")
	_assert(received["agent_id"] == death_agent_id, "agent_unregistered carried the dead agent's id")
	_assert(om.get_agent_node(death_agent_id) == null, "Dead agent no longer resolves to a live node")
	_assert(om.get_total_agent_count() == total_before - 1, "Registry count decremented by one (got %d, expected %d)" % [om.get_total_agent_count(), total_before - 1])

	await _cleanup(sim, om)


func _test_id_resolves_to_live_agent_node() -> void:
	print("[Test] Given a registered agent id, get_agent_node resolves to the live Agent node")
	var om = get_node("/root/OrganizationManager")
	var sim = _make_sim(om)

	for i in range(15):
		await get_tree().physics_frame

	var agent_ids: Array = om.get_registered_agent_ids()
	for agent_id in agent_ids:
		var node = om.get_agent_node(agent_id)
		_assert(node != null and node.agent_id == agent_id, "Resolves %s's id to its live Agent node" % agent_id)
	_assert(om.get_agent_node("nonexistent_id") == null, "Unknown id resolves to null")

	await _cleanup(sim, om)


func _test_role_counts_stay_correct_through_spawn_role_change_death() -> void:
	print("[Test] Role counts stay correct through spawn, role change, and death (no double registration)")
	var om = get_node("/root/OrganizationManager")
	var sim = _make_sim(om)

	for i in range(15):
		await get_tree().physics_frame

	var total_before: int = om.get_total_agent_count()
	_assert(total_before > 0, "Agents registered at spawn (got %d)" % total_before)

	var agent_ids: Array = om.get_registered_agent_ids()
	var agent_id: String = agent_ids[0]
	var agent = om.get_agent_node(agent_id)

	om.update_agent_role(agent_id, "Guard")
	_assert(om.get_total_agent_count() == total_before, "update_agent_role does not double-register an already-registered agent (got %d)" % om.get_total_agent_count())
	_assert(om.get_role_count("Guard") == 1, "Guard count reflects the role change (got %d)" % om.get_role_count("Guard"))
	_assert(om.get_role_count("Unassigned") == total_before - 1, "Remaining Unassigned count reflects the role change (got %d)" % om.get_role_count("Unassigned"))

	agent.energy = 0.0
	agent._check_death()

	_assert(om.get_total_agent_count() == total_before - 1, "Total agent count decremented after death (got %d)" % om.get_total_agent_count())
	_assert(om.get_role_count("Guard") == 0, "Guard count decremented to zero after death (got %d)" % om.get_role_count("Guard"))

	await _cleanup(sim, om)
