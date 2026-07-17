extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T12 Test Harness (Agent Died Signal Wiring) ===")
	print("")

	_test_agent_has_agent_died_signal()
	_test_agent_died_emits_with_agent_id_and_last_role()
	_test_agent_died_does_not_fire_while_energy_positive()
	_test_agent_died_only_fires_once()
	await _test_simulation_wires_agent_died_to_om_handle_agent_death()

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


func _test_agent_has_agent_died_signal() -> void:
	print("[Test] agent.gd exposes an agent_died(agent_id, last_role) signal")
	var agent = _make_agent()
	_assert(agent.has_signal("agent_died"), "Agent has agent_died signal")


func _test_agent_died_emits_with_agent_id_and_last_role() -> void:
	print("[Test] agent_died fires with agent_id and last_role once energy hits zero")
	var agent = _make_agent()
	agent.agent_id = "agent_death_1"
	agent._role_component.load_role("Guard")
	agent.energy = 0.0

	var received := {"fired": false, "agent_id": "", "last_role": ""}
	agent.agent_died.connect(func(aid: String, role: String) -> void:
		received["fired"] = true
		received["agent_id"] = aid
		received["last_role"] = role
	)

	agent._check_death()

	_assert(received["fired"], "agent_died signal fired")
	_assert(received["agent_id"] == "agent_death_1", "agent_died carried agent_id (got %s)" % received["agent_id"])
	_assert(received["last_role"] == "Guard", "agent_died carried last_role (got %s)" % received["last_role"])


func _test_agent_died_does_not_fire_while_energy_positive() -> void:
	print("[Test] agent_died does not fire while energy remains above zero")
	var agent = _make_agent()
	agent.energy = 1.0

	var fired := false
	agent.agent_died.connect(func(_a: String, _r: String) -> void: fired = true)

	agent._check_death()

	_assert(not fired, "agent_died did not fire with positive energy")


func _test_agent_died_only_fires_once() -> void:
	print("[Test] agent_died fires only once even if the death check runs again")
	var agent = _make_agent()
	agent.energy = 0.0

	var counter := {"fire_count": 0}
	agent.agent_died.connect(func(_a: String, _r: String) -> void: counter["fire_count"] += 1)

	agent._check_death()
	agent._check_death()
	agent._check_death()

	_assert(counter["fire_count"] == 1, "agent_died fired exactly once (got %d)" % counter["fire_count"])


func _test_simulation_wires_agent_died_to_om_handle_agent_death() -> void:
	print("[Test] Simulation connects agent_died to OM.handle_agent_death, updating counts")
	var om = get_node("/root/OrganizationManager")

	var sim = preload("res://simulation/Simulation.tscn").instantiate()
	add_child(sim)
	for i in range(5):
		await get_tree().physics_frame

	var agent = sim.get_node("NavigationRegion/Agent")
	agent.agent_id = "sim_death_agent"
	om.register_agent("sim_death_agent", "Guard")

	var death_count_before: int = om.get_death_count()

	agent.energy = 0.0
	agent._check_death()

	_assert(om.get_death_count() == death_count_before + 1,
		"OM death counter incremented (got %d, expected %d)" % [om.get_death_count(), death_count_before + 1])
	_assert(om.get_role_count("Guard") == 0, "OM Guard role count decremented to 0")
	_assert(om.get_total_agent_count() == 0, "OM total agent count decremented to 0")

	om.unregister_agent("sim_death_agent")
	sim.queue_free()
