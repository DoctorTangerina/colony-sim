extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T13 Test Harness (OM Minimum Unassigned Slot) ===")
	print("")

	_test_min_unassigned_threshold_loaded_from_config()
	_test_target_distribution_sets_unassigned_floor_at_threshold()
	_test_target_distribution_no_floor_below_threshold()
	_test_ten_agents_abundant_resources_still_request_unassigned()
	_test_evaluate_roles_posts_explorer_and_unassigned_requests_for_large_population()

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


func _make_om_with_role_defs() -> Node:
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)
	om._get_role_def("Gatherer")
	om._get_role_def("Explorer")
	om._get_role_def("Guard")
	return om


func _test_min_unassigned_threshold_loaded_from_config() -> void:
	print("[Test] minUnassignedThreshold is loaded from simulation.json, not hardcoded")
	var config: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	_assert(config.has("minUnassignedThreshold"), "simulation.json defines minUnassignedThreshold")

	var om = _make_om_with_role_defs()
	_assert(om._min_unassigned_threshold == config.get("minUnassignedThreshold"),
		"OM's threshold (%s) matches simulation.json's value (%s)" % [om._min_unassigned_threshold, config.get("minUnassignedThreshold")])


func _test_target_distribution_sets_unassigned_floor_at_threshold() -> void:
	print("[Test] Target distribution floors Unassigned at 1 once total agents reach the threshold")
	var om = _make_om_with_role_defs()

	var target = om._compute_target_distribution(60, 60, om._min_unassigned_threshold)
	_assert(target.get("Unassigned", 0) >= 1,
		"Unassigned floor applied at exactly the threshold (got %d)" % target.get("Unassigned", 0))


func _test_target_distribution_no_floor_below_threshold() -> void:
	print("[Test] No Unassigned floor is forced below the configured threshold")
	var om = _make_om_with_role_defs()

	var below: int = om._min_unassigned_threshold - 1
	var target = om._compute_target_distribution(60, 60, below)
	_assert(target.get("Unassigned", 0) == 0,
		"No Unassigned request forced below threshold (got %d)" % target.get("Unassigned", 0))


func _test_ten_agents_abundant_resources_still_request_unassigned() -> void:
	print("[Test] With 10 agents and abundant resources, OM still targets 1 Unassigned")
	var om = _make_om_with_role_defs()

	var target = om._compute_target_distribution(60, 60, 10)
	_assert(target.get("Unassigned", 0) >= 1, "Unassigned target present (got %d)" % target.get("Unassigned", 0))
	_assert(target.get("Explorer", 0) >= 1, "Explorer target still present alongside Unassigned (got %d)" % target.get("Explorer", 0))


func _test_evaluate_roles_posts_explorer_and_unassigned_requests_for_large_population() -> void:
	print("[Test] _evaluate_roles posts Unassigned requests but no excess Explorer requests once holders already meet target")
	var om = _make_om_with_role_defs()

	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	om.setup(nest)

	for i in range(10):
		om.register_agent("agent_%d" % i, "Explorer")

	nest.deposit("Food", 60)
	nest.deposit("Wood", 60)

	om._evaluate_roles()

	_assert(om.get_request_count("Explorer") == 0, "No Explorer requests posted - 10 holders already exceed the target of 4 (got %d)" % om.get_request_count("Explorer"))
	_assert(om.get_request_count("Unassigned") >= 1, "Unassigned request posted (got %d)" % om.get_request_count("Unassigned"))
