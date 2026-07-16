extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP Map Bounds Test Harness (Config-Driven Bounds) ===")
	print("")

	_test_simulation_json_has_map_bounds()
	_test_resource_manager_loads_bounds_from_config()
	_test_agent_loads_bounds_from_config()

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


func _test_simulation_json_has_map_bounds() -> void:
	print("[Test] simulation.json declares map bounds")
	var data: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	_assert(data.has("mapMinX"), "simulation.json has mapMinX")
	_assert(data.has("mapMinY"), "simulation.json has mapMinY")
	_assert(data.has("mapMaxX"), "simulation.json has mapMaxX")
	_assert(data.has("mapMaxY"), "simulation.json has mapMaxY")


func _test_resource_manager_loads_bounds_from_config() -> void:
	print("[Test] ResourceManager sources map bounds from ConfigLoader")
	var data: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	var expected_min := Vector2(data["mapMinX"], data["mapMinY"])
	var expected_max := Vector2(data["mapMaxX"], data["mapMaxY"])

	var ResourceManagerScript = preload("res://resources/resource_manager.gd")
	var rm = ResourceManagerScript.new()
	rm._load_config()

	_assert(rm._map_min == expected_min, "ResourceManager._map_min matches simulation.json (got %s)" % rm._map_min)
	_assert(rm._map_max == expected_max, "ResourceManager._map_max matches simulation.json (got %s)" % rm._map_max)
	rm.free()


func _test_agent_loads_bounds_from_config() -> void:
	print("[Test] Agent sources map bounds from ConfigLoader")
	var data: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	var expected_bounds := Rect2(
		Vector2(data["mapMinX"], data["mapMinY"]),
		Vector2(data["mapMaxX"], data["mapMaxY"]) - Vector2(data["mapMinX"], data["mapMinY"])
	)

	var AgentScript = preload("res://agents/agent.gd")
	var agent = AgentScript.new()
	agent._load_sim_config()

	_assert(agent.get_world_bounds() == expected_bounds, "Agent.get_world_bounds() matches simulation.json (got %s)" % agent.get_world_bounds())
	agent.free()
