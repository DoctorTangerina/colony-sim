extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Role Market T05 Test Harness (OrganizationManager.get_debug_info) ===")
	print("")

	_test_debug_info_shape_and_values_with_nest_wired()
	_test_debug_info_reports_zeros_and_empties_before_nest_is_wired()
	_test_death_counter_is_not_included()

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


func _make_om() -> Node:
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)
	return om


func _make_om_with_nest() -> Dictionary:
	var om := _make_om()
	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	om.setup(nest)
	return {"om": om, "nest": nest}


func _test_debug_info_shape_and_values_with_nest_wired() -> void:
	print("[Test] get_debug_info() reports storage, role counts, cached targets, pending requests, settings, and log once the Nest is wired")
	var rig := _make_om_with_nest()
	var om: Node = rig["om"]
	var nest: Node = rig["nest"]

	om.register_agent("a1", "Gatherer")
	om.register_agent("a2", "Explorer")
	om.register_agent("a3", "Unassigned")
	om.register_agent("a4", "Unassigned")

	nest.deposit("Food", 5)
	nest.deposit("Wood", 5)

	# 4 agents, both Food/Wood low -> Gatherer target = ceil(4*0.5) = 2 (1 holder -> deficit 1, posts 1 request).
	# Neither abundant -> Explorer falls to its default 0.2 rule -> target = ceil(4*0.2) = 1 (already met).
	# Guard's default rule is zeroed -> target 0. Unassigned floor doesn't apply (4 < minUnassignedThreshold of 5).
	om._evaluate_roles()

	# A role change after evaluation exercises the log independently of the pending-request math above.
	om.update_agent_role("a3", "Gatherer")

	var info: Dictionary = om.get_debug_info()

	_assert(info.get("storage") == {"Food": 5, "Wood": 5}, "storage reflects Nest deposits (got %s)" % [info.get("storage")])

	var role_counts: Dictionary = info.get("role_counts", {})
	_assert(role_counts.get("Gatherer") == 2, "Gatherer holder count includes the role change (got %s)" % role_counts.get("Gatherer"))
	_assert(role_counts.get("Explorer") == 1, "Explorer holder count matches registration (got %s)" % role_counts.get("Explorer"))
	_assert(role_counts.get("Guard") == 0, "Guard holder count is zero, not missing (got %s)" % role_counts.get("Guard"))
	_assert(role_counts.get("Unassigned") == 1, "Unassigned holder count drops after the role change (got %s)" % role_counts.get("Unassigned"))

	var cached_targets: Dictionary = info.get("cached_targets", {})
	_assert(cached_targets.get("Gatherer") == 2, "Cached Gatherer target from the last evaluation (got %s)" % cached_targets.get("Gatherer"))
	_assert(cached_targets.get("Explorer") == 1, "Cached Explorer target from the last evaluation (got %s)" % cached_targets.get("Explorer"))
	_assert(cached_targets.get("Guard") == 0, "Cached Guard target is zero, not missing (got %s)" % cached_targets.get("Guard"))
	_assert(cached_targets.get("Unassigned") == 0, "Cached Unassigned target defaults to zero below the reserve floor (got %s)" % cached_targets.get("Unassigned"))

	var pending_requests: Dictionary = info.get("pending_requests", {})
	_assert(pending_requests.get("Gatherer") == 1, "Gatherer's deficit of 1 is reflected as a pending request (got %s)" % pending_requests.get("Gatherer"))
	_assert(pending_requests.get("Explorer") == 0, "Explorer has no pending requests at target (got %s)" % pending_requests.get("Explorer"))
	_assert(pending_requests.get("Guard") == 0, "Guard has no pending requests at target (got %s)" % pending_requests.get("Guard"))

	_assert(info.get("dynamic_roles_enabled") == true, "dynamic_roles_enabled matches the config default (got %s)" % info.get("dynamic_roles_enabled"))
	_assert(is_equal_approx(info.get("role_cooldown"), 10.0), "role_cooldown matches the config default (got %s)" % info.get("role_cooldown"))
	_assert(info.get("min_unassigned_threshold") == 5, "min_unassigned_threshold matches the config default (got %s)" % info.get("min_unassigned_threshold"))

	var log: Array = info.get("role_change_log", [])
	_assert(log.size() == 1, "role_change_log has exactly the one logged transition (got %d)" % log.size())
	if log.size() == 1:
		var entry: Dictionary = log[0]
		_assert(entry.get("agent_id") == "a3", "Log entry records the correct agent id (got %s)" % entry.get("agent_id"))
		_assert(entry.get("old_role") == "Unassigned", "Log entry records the old role (got %s)" % entry.get("old_role"))
		_assert(entry.get("new_role") == "Gatherer", "Log entry records the new role (got %s)" % entry.get("new_role"))


func _test_debug_info_reports_zeros_and_empties_before_nest_is_wired() -> void:
	print("[Test] get_debug_info() reports zeros/empty storage and role-market fields (not an error) before setup() wires the Nest")
	var om := _make_om()

	# Register/post/change state directly, without ever calling setup() - the
	# snapshot should still degrade to zeros/empty for storage and role-market
	# fields per the not-yet-registered-agent posture, while settings and the
	# log (which don't depend on the Nest) keep reporting their true state.
	om.register_agent("a1", "Gatherer")
	om.post_request("Explorer")
	om.update_agent_role("a1", "Explorer")

	var info: Dictionary = om.get_debug_info()

	_assert(info.get("storage") == {"Food": 0, "Wood": 0}, "storage reports zeros with no Nest wired (got %s)" % [info.get("storage")])
	_assert(info.get("role_counts") == {}, "role_counts reports empty with no Nest wired (got %s)" % [info.get("role_counts")])
	_assert(info.get("cached_targets") == {}, "cached_targets reports empty with no Nest wired (got %s)" % [info.get("cached_targets")])
	_assert(info.get("pending_requests") == {}, "pending_requests reports empty with no Nest wired (got %s)" % [info.get("pending_requests")])

	_assert(info.get("dynamic_roles_enabled") == true, "dynamic_roles_enabled still reports its true value with no Nest wired (got %s)" % info.get("dynamic_roles_enabled"))
	_assert(is_equal_approx(info.get("role_cooldown"), 10.0), "role_cooldown still reports its true value with no Nest wired (got %s)" % info.get("role_cooldown"))
	_assert(info.get("min_unassigned_threshold") == 5, "min_unassigned_threshold still reports its true value with no Nest wired (got %s)" % info.get("min_unassigned_threshold"))

	var log: Array = info.get("role_change_log", [])
	_assert(log.size() == 1, "role_change_log still reports real history with no Nest wired (got %d)" % log.size())


func _test_death_counter_is_not_included() -> void:
	print("[Test] get_debug_info() never includes the death counter")
	var om := _make_om()
	om.register_agent("a1", "Gatherer")
	om.handle_agent_death("a1")

	var info: Dictionary = om.get_debug_info()

	_assert(not info.has("death_count"), "death_count key is absent from the snapshot")
	_assert(not info.has("death_counter"), "death_counter key is absent from the snapshot")
