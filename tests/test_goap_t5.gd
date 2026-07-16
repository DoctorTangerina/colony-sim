extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T5 Test Harness (OM Evaluation Loop) ===")
	print("")

	_test_target_distribution_low_food()
	_test_target_distribution_abundant()
	_test_target_distribution_balanced()
	_test_om_evaluation_posts_requests()
	_test_om_evaluation_clears_excess()
	_test_dynamic_roles_disabled()
	_test_unassigned_counts_in_denominator()

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


func _test_target_distribution_low_food() -> void:
	print("[Test] Target distribution with low food")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)
	om.register_agent("a1", "Explorer")
	om.register_agent("a2", "Explorer")
	om.register_agent("a3", "Guard")

	om._get_role_def("Gatherer")
	om._get_role_def("Explorer")
	om._get_role_def("Guard")

	var target = om._compute_target_distribution(5, 50, 3)
	_assert(target.get("Gatherer", 0) >= 1, "Low food produces Gatherer request (got %d)" % target.get("Gatherer", 0))


func _test_target_distribution_abundant() -> void:
	print("[Test] Target distribution with abundant resources")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)
	om.register_agent("a1", "Gatherer")

	om._get_role_def("Gatherer")
	om._get_role_def("Explorer")
	om._get_role_def("Guard")

	var target = om._compute_target_distribution(60, 60, 1)
	_assert(target.get("Explorer", 0) >= 1, "Abundant resources produce Explorer request (got %d)" % target.get("Explorer", 0))


func _test_target_distribution_balanced() -> void:
	print("[Test] Target distribution balanced")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	om._get_role_def("Gatherer")
	om._get_role_def("Explorer")
	om._get_role_def("Guard")

	var target = om._compute_target_distribution(30, 30, 4)
	var total_requests := 0
	for role in target:
		total_requests += target[role]
	_assert(total_requests > 0, "Balanced distribution produces requests (total=%d)" % total_requests)
	_assert(target.get("Guard", 0) >= 1, "Always produces at least one Guard")


func _test_om_evaluation_posts_requests() -> void:
	print("[Test] OM evaluation posts requests based on nest storage")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	var nest_script = preload("res://organization/nest.gd")
	var nest = nest_script.new()
	add_child(nest)

	om._get_role_def("Gatherer")
	om._get_role_def("Explorer")
	om._get_role_def("Guard")

	om.setup(nest)
	om.register_agent("a1", "Explorer")

	nest.deposit("Food", 5)
	nest.deposit("Wood", 5)

	om._evaluate_roles()
	_assert(om.get_total_request_count() > 0, "OM posted requests after evaluation (count=%d)" % om.get_total_request_count())


func _test_om_evaluation_clears_excess() -> void:
	print("[Test] OM evaluation clears excess requests")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	var nest_script = preload("res://organization/nest.gd")
	var nest = nest_script.new()
	add_child(nest)

	om._get_role_def("Gatherer")
	om._get_role_def("Explorer")
	om._get_role_def("Guard")

	om.setup(nest)
	om.register_agent("a1", "Gatherer")
	om.register_agent("a2", "Gatherer")

	om.post_request("Gatherer")
	om.post_request("Gatherer")
	om.post_request("Gatherer")

	nest.deposit("Food", 60)
	nest.deposit("Wood", 60)

	om._evaluate_roles()
	_assert(om.get_request_count("Gatherer") <= 2, "Excess Gatherer requests cleared (count=%d)" % om.get_request_count("Gatherer"))


func _test_dynamic_roles_disabled() -> void:
	print("[Test] Dynamic roles disabled prevents evaluation")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	om.set_dynamic_roles(false)
	om.register_agent("a1", "Explorer")

	var nest_script = preload("res://organization/nest.gd")
	var nest = nest_script.new()
	add_child(nest)
	om.setup(nest)

	nest.deposit("Food", 5)
	om._eval_timer = 0.0
	om._process(0.1)
	_assert(om.get_total_request_count() == 0, "No requests posted when dynamic roles disabled")


func _test_unassigned_counts_in_denominator() -> void:
	print("[Test] Unassigned agents count in denominator")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	om._get_role_def("Gatherer")
	om._get_role_def("Explorer")
	om._get_role_def("Guard")

	om.register_agent("a1", "Unassigned")
	om.register_agent("a2", "Unassigned")
	om.register_agent("a3", "Unassigned")

	var nest_script = preload("res://organization/nest.gd")
	var nest = nest_script.new()
	add_child(nest)
	om.setup(nest)

	nest.deposit("Food", 5)
	om._evaluate_roles()
	_assert(om.get_total_request_count() > 0, "Unassigned agents trigger role requests (count=%d)" % om.get_total_request_count())
