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


func _make_sim() -> Node2D:
	var sim = preload("res://simulation/Simulation.tscn").instantiate()
	add_child(sim)
	return sim


func _test_agents_register_at_spawn_with_starting_role() -> void:
	print("[Test] Every agent in the scene registers with the OM at spawn, with its starting role")
	var om = get_node("/root/OrganizationManager")
	var sim = _make_sim()

	for i in range(3):
		await get_tree().physics_frame

	var agent1 = sim.get_node("NavigationRegion/Agent")
	var agent2 = sim.get_node("NavigationRegion/Agent2")

	_assert(om.get_total_agent_count() == 2, "Both Simulation.tscn agents registered (got %d)" % om.get_total_agent_count())
	_assert(om.get_role_count("Unassigned") == 2, "Both agents start Unassigned (got %d)" % om.get_role_count("Unassigned"))

	om.unregister_agent(agent1.agent_id)
	om.unregister_agent(agent2.agent_id)
	sim.queue_free()
	await get_tree().physics_frame


func _test_agent_unregistered_on_death() -> void:
	print("[Test] An agent dying results in agent_unregistered being emitted (no silent registry removal)")
	var om = get_node("/root/OrganizationManager")
	var sim = _make_sim()

	for i in range(3):
		await get_tree().physics_frame

	var agent = sim.get_node("NavigationRegion/Agent")
	var other = sim.get_node("NavigationRegion/Agent2")

	var received := {"fired": false, "agent_id": ""}
	om.agent_unregistered.connect(func(aid: String) -> void:
		received["fired"] = true
		received["agent_id"] = aid
	)

	var death_agent_id: String = agent.agent_id
	agent.energy = 0.0
	agent._check_death()

	_assert(received["fired"], "agent_unregistered signal fired on death")
	_assert(received["agent_id"] == death_agent_id, "agent_unregistered carried the dead agent's id")
	_assert(om.get_agent_node(death_agent_id) == null, "Dead agent no longer resolves to a live node")
	_assert(om.get_total_agent_count() == 1, "Only the surviving agent remains registered (got %d)" % om.get_total_agent_count())

	om.unregister_agent(other.agent_id)
	sim.queue_free()
	await get_tree().physics_frame


func _test_id_resolves_to_live_agent_node() -> void:
	print("[Test] Given a registered agent id, get_agent_node resolves to the live Agent node")
	var om = get_node("/root/OrganizationManager")
	var sim = _make_sim()

	for i in range(3):
		await get_tree().physics_frame

	var agent1 = sim.get_node("NavigationRegion/Agent")
	var agent2 = sim.get_node("NavigationRegion/Agent2")

	_assert(om.get_agent_node(agent1.agent_id) == agent1, "Resolves agent1's id to the live Agent node")
	_assert(om.get_agent_node(agent2.agent_id) == agent2, "Resolves agent2's id to the live Agent node")
	_assert(om.get_agent_node("nonexistent_id") == null, "Unknown id resolves to null")

	om.unregister_agent(agent1.agent_id)
	om.unregister_agent(agent2.agent_id)
	sim.queue_free()
	await get_tree().physics_frame


func _test_role_counts_stay_correct_through_spawn_role_change_death() -> void:
	print("[Test] Role counts stay correct through spawn, role change, and death (no double registration)")
	var om = get_node("/root/OrganizationManager")
	var sim = _make_sim()

	for i in range(3):
		await get_tree().physics_frame

	var agent = sim.get_node("NavigationRegion/Agent")
	var other = sim.get_node("NavigationRegion/Agent2")

	_assert(om.get_total_agent_count() == 2, "Two agents registered at spawn (got %d)" % om.get_total_agent_count())

	om.update_agent_role(agent.agent_id, "Guard")
	_assert(om.get_total_agent_count() == 2, "update_agent_role does not double-register an already-registered agent (got %d)" % om.get_total_agent_count())
	_assert(om.get_role_count("Guard") == 1, "Guard count reflects the role change (got %d)" % om.get_role_count("Guard"))
	_assert(om.get_role_count("Unassigned") == 1, "Remaining Unassigned count reflects the role change (got %d)" % om.get_role_count("Unassigned"))

	agent.energy = 0.0
	agent._check_death()

	_assert(om.get_total_agent_count() == 1, "Total agent count decremented after death (got %d)" % om.get_total_agent_count())
	_assert(om.get_role_count("Guard") == 0, "Guard count decremented to zero after death (got %d)" % om.get_role_count("Guard"))

	om.unregister_agent(other.agent_id)
	sim.queue_free()
	await get_tree().physics_frame
