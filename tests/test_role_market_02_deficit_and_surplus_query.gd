extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Role Market T02 Test Harness (Deficit Posting & Surplus Query) ===")
	print("")

	_test_positive_deficit_posts_exactly_the_shortfall()
	_test_negative_deficit_withdraws_only_the_excess_pending_requests()
	_test_role_at_target_with_empty_queue_causes_no_new_requests_across_evaluations()
	_test_withdraw_requests_removes_only_the_requested_count_leaving_the_rest()
	_test_cached_target_and_surplus_query_reflect_latest_evaluation()
	_test_unassigned_reserve_uses_truthful_holder_counts()

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


func _make_om_with_nest() -> Dictionary:
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	om.setup(nest)

	return {"om": om, "nest": nest}


func _test_positive_deficit_posts_exactly_the_shortfall() -> void:
	print("[Test] A positive Role Deficit posts exactly target - (holders + pending), no more")
	var rig := _make_om_with_nest()
	var om: Node = rig["om"]
	var nest: Node = rig["nest"]

	om.register_agent("a1", "Gatherer")
	for i in range(2, 7):
		om.register_agent("a%d" % i, "Unassigned")

	nest.deposit("Food", 5)
	nest.deposit("Wood", 5)

	om._evaluate_roles()

	# 6 agents, Food low -> Gatherer target = ceil(6 * 0.5) = 3; 1 holder, 0 pending -> deficit = 2.
	_assert(om.get_request_count("Gatherer") == 2, "Deficit of 2 posts exactly 2 Gatherer requests (got %d)" % om.get_request_count("Gatherer"))


func _test_negative_deficit_withdraws_only_the_excess_pending_requests() -> void:
	print("[Test] A negative Role Deficit withdraws only the excess pending requests; the rest survive")
	var rig := _make_om_with_nest()
	var om: Node = rig["om"]
	var nest: Node = rig["nest"]

	for i in range(1, 11):
		om.register_agent("a%d" % i, "Unassigned")

	for i in range(5):
		om.post_request("Explorer")

	nest.deposit("Food", 60)
	nest.deposit("Wood", 60)

	om._evaluate_roles()

	# 10 agents, both abundant -> Explorer target = ceil(10 * 0.4) = 4; 0 holders, 5 pending -> deficit = -1.
	_assert(om.get_request_count("Explorer") == 4, "Only the 1 excess request is withdrawn, 4 still-needed ones survive (got %d)" % om.get_request_count("Explorer"))


func _test_role_at_target_with_empty_queue_causes_no_new_requests_across_evaluations() -> void:
	print("[Test] A role already at target with an empty queue stays untouched across repeated evaluations")
	var rig := _make_om_with_nest()
	var om: Node = rig["om"]
	var nest: Node = rig["nest"]

	om.register_agent("a1", "Explorer")
	for i in range(2, 6):
		om.register_agent("a%d" % i, "Unassigned")

	nest.deposit("Food", 5)
	nest.deposit("Wood", 5)

	# 5 agents, neither abundant -> Explorer falls to the default 0.2 rule -> target = ceil(5 * 0.2) = 1,
	# which the 1 registered holder already satisfies.
	om._evaluate_roles()
	_assert(om.get_request_count("Explorer") == 0, "No Explorer request posted on first evaluation at target (got %d)" % om.get_request_count("Explorer"))

	om._evaluate_roles()
	_assert(om.get_request_count("Explorer") == 0, "Queue stays empty on a subsequent evaluation (got %d)" % om.get_request_count("Explorer"))


func _test_withdraw_requests_removes_only_the_requested_count_leaving_the_rest() -> void:
	print("[Test] withdraw_requests removes exactly N pending requests for a role, leaving the remainder and other roles untouched")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	for i in range(5):
		om.post_request("Gatherer")
	om.post_request("Explorer")
	om.post_request("Explorer")

	om.withdraw_requests("Gatherer", 3)

	_assert(om.get_request_count("Gatherer") == 2, "Withdrawing 3 of 5 leaves exactly 2 Gatherer requests (got %d)" % om.get_request_count("Gatherer"))
	_assert(om.get_request_count("Explorer") == 2, "Explorer requests are untouched by a Gatherer withdrawal (got %d)" % om.get_request_count("Explorer"))


func _test_cached_target_and_surplus_query_reflect_latest_evaluation() -> void:
	print("[Test] get_cached_target/is_role_surplus answer from the latest evaluation, keyed only by role name")
	var rig := _make_om_with_nest()
	var om: Node = rig["om"]
	var nest: Node = rig["nest"]

	om.register_agent("a1", "Gatherer")
	om.register_agent("a2", "Gatherer")
	om.register_agent("a3", "Gatherer")
	om.register_agent("a4", "Explorer")

	nest.deposit("Food", 60)
	nest.deposit("Wood", 60)

	om._evaluate_roles()

	# Both abundant -> Gatherer's only rule (low-triggered) doesn't match, falls to its default of 0.
	_assert(om.get_cached_target("Gatherer") == 0, "Cached Gatherer target reflects the latest evaluation (got %d)" % om.get_cached_target("Gatherer"))
	_assert(om.is_role_surplus("Gatherer"), "3 Gatherer holders against a target of 0 is Surplus")

	# 4 agents, both abundant -> Explorer target = ceil(4 * 0.4) = 2; 1 holder is under target, not Surplus.
	_assert(om.get_cached_target("Explorer") == 2, "Cached Explorer target reflects the latest evaluation (got %d)" % om.get_cached_target("Explorer"))
	_assert(not om.is_role_surplus("Explorer"), "1 Explorer holder against a target of 2 is not Surplus")


func _test_unassigned_reserve_uses_truthful_holder_counts() -> void:
	print("[Test] The Unassigned reserve floor posts through the same deficit path with truthful holder counts")

	var rig_a := _make_om_with_nest()
	var om_a: Node = rig_a["om"]
	var nest_a: Node = rig_a["nest"]

	om_a.register_agent("a1", "Unassigned")
	om_a.register_agent("a2", "Unassigned")
	om_a.register_agent("a3", "Gatherer")
	om_a.register_agent("a4", "Gatherer")
	om_a.register_agent("a5", "Gatherer")

	nest_a.deposit("Food", 60)
	nest_a.deposit("Wood", 60)

	om_a._evaluate_roles()
	_assert(om_a.get_request_count("Unassigned") == 0, "2 existing Unassigned holders already satisfy the reserve floor of 1 (got %d)" % om_a.get_request_count("Unassigned"))

	var rig_b := _make_om_with_nest()
	var om_b: Node = rig_b["om"]
	var nest_b: Node = rig_b["nest"]

	om_b.register_agent("b1", "Gatherer")
	om_b.register_agent("b2", "Gatherer")
	om_b.register_agent("b3", "Gatherer")
	om_b.register_agent("b4", "Gatherer")
	om_b.register_agent("b5", "Gatherer")

	nest_b.deposit("Food", 60)
	nest_b.deposit("Wood", 60)

	om_b._evaluate_roles()
	_assert(om_b.get_request_count("Unassigned") == 1, "0 Unassigned holders leaves the reserve floor of 1 unmet, posting exactly 1 (got %d)" % om_b.get_request_count("Unassigned"))
