extends Node

var tests_passed: int = 0
var tests_failed: int = 0

const SIM_CONFIG_PATH := "res://configs/simulation.json"


func _ready() -> void:
	print("=== Role Market T04 Test Harness (Config-Driven Population) ===")
	print("")

	await _test_default_agent_count_spawns_and_registers_as_unassigned()
	await _test_no_hand_placed_agents_before_spawn_completes()
	await _test_spawned_agents_are_nav_ready_near_the_nest()
	await _test_changing_agent_count_changes_spawned_population()

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
## agent can leave Unassigned before these spawn/registry assertions get a
## chance to inspect it. These tests are about population spawning, not
## role-market dynamics (that's covered in tests/test_role_market_03), so
## dynamic roles are disabled for their duration to keep the spawn snapshot
## deterministic.
func _cleanup_sim(sim: Node, om: Node) -> void:
	for agent_id in om.get_registered_agent_ids():
		om.unregister_agent(agent_id)
	om.set_dynamic_roles(true)
	sim.queue_free()
	await get_tree().physics_frame


func _test_default_agent_count_spawns_and_registers_as_unassigned() -> void:
	print("[Test] Booting headless produces the configured agentCount as registered, Unassigned agents")
	var om = get_node("/root/OrganizationManager")
	var config: Dictionary = ConfigLoader.load_dict(SIM_CONFIG_PATH)
	var expected_count: int = config.get("agentCount", 8)

	var sim = preload("res://simulation/Simulation.tscn").instantiate()
	om.set_dynamic_roles(false)
	add_child(sim)
	for i in range(15):
		await get_tree().physics_frame

	_assert(om.get_total_agent_count() == expected_count,
		"Registered agent count matches agentCount (got %d, expected %d)" % [om.get_total_agent_count(), expected_count])
	_assert(om.get_role_count("Unassigned") == expected_count,
		"Every spawned agent starts Unassigned (got %d)" % om.get_role_count("Unassigned"))

	await _cleanup_sim(sim, om)


## Prior art: test_resource_spawn_navmesh_race.gd - anything spawned onto the
## navmesh must wait for nav-map sync. Simulation now spawns its population
## the same way (no hand-placed nodes), so the agents genuinely don't exist
## in the tree until that wait resolves - checked here on the very next
## frame, before the nav-sync wait has had a chance to complete.
func _test_no_hand_placed_agents_before_spawn_completes() -> void:
	print("[Test] No hand-placed agents remain in the scene - the population only appears after spawning")
	var om = get_node("/root/OrganizationManager")

	var sim = preload("res://simulation/Simulation.tscn").instantiate()
	om.set_dynamic_roles(false)
	add_child(sim)
	await get_tree().process_frame

	var nav_region: Node = sim.get_node("NavigationRegion")
	_assert(nav_region.get_child_count() == 0,
		"NavigationRegion has no pre-placed agent children immediately after instantiation (got %d)" % nav_region.get_child_count())

	for i in range(15):
		await get_tree().physics_frame

	_assert(nav_region.get_child_count() > 0,
		"Agents appear under NavigationRegion once spawning completes (got %d)" % nav_region.get_child_count())

	await _cleanup_sim(sim, om)


func _test_spawned_agents_are_nav_ready_near_the_nest() -> void:
	print("[Test] Spawned agents land near the Nest with a real navmesh position (not the (0,0) sentinel)")
	var om = get_node("/root/OrganizationManager")

	var sim = preload("res://simulation/Simulation.tscn").instantiate()
	om.set_dynamic_roles(false)
	add_child(sim)
	for i in range(15):
		await get_tree().physics_frame

	var nest: Node2D = sim.get_node("Nest")
	var agent_ids: Array = om.get_registered_agent_ids()
	_assert(agent_ids.size() > 0, "At least one agent registered to inspect")

	for agent_id in agent_ids:
		var agent: Node2D = om.get_agent_node(agent_id)
		_assert(agent.global_position != Vector2.ZERO,
			"Agent %s spawned at a real position, not the (0,0) nav-sync sentinel" % agent_id)
		var dist: float = agent.global_position.distance_to(nest.global_position)
		_assert(dist < 100.0,
			"Agent %s spawned near the Nest (got distance %.1f)" % [agent_id, dist])

	await _cleanup_sim(sim, om)


## Mutates configs/simulation.json for the duration of this test only,
## restoring the original text afterward - mirrors test_role_market_01's
## temp-file technique, but here the key already exists and must be
## round-tripped rather than added/removed.
func _test_changing_agent_count_changes_spawned_population() -> void:
	print("[Test] Changing agentCount in the Simulation Config changes the spawned population with no scene edits")
	var om = get_node("/root/OrganizationManager")

	var file := FileAccess.open(SIM_CONFIG_PATH, FileAccess.READ)
	var original_text := file.get_as_text()
	file.close()

	var config: Dictionary = JSON.parse_string(original_text)
	config["agentCount"] = 3

	var write_file := FileAccess.open(SIM_CONFIG_PATH, FileAccess.WRITE)
	write_file.store_string(JSON.stringify(config))
	write_file.close()

	var sim = preload("res://simulation/Simulation.tscn").instantiate()
	om.set_dynamic_roles(false)
	add_child(sim)
	for i in range(15):
		await get_tree().physics_frame

	_assert(om.get_total_agent_count() == 3,
		"Spawned population follows the overridden agentCount (got %d, expected 3)" % om.get_total_agent_count())

	await _cleanup_sim(sim, om)

	var restore_file := FileAccess.open(SIM_CONFIG_PATH, FileAccess.WRITE)
	restore_file.store_string(original_text)
	restore_file.close()
	_assert(FileAccess.get_file_as_string(SIM_CONFIG_PATH) == original_text,
		"simulation.json restored to its original contents")
