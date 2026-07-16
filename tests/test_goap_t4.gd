extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T4 Test Harness (OM + Nest Trigger) ===")
	print("")

	_test_om_post_and_take()
	_test_om_clear_requests()
	_test_om_agent_tracking()
	_test_om_role_change_log()
	_test_om_death_counter()
	_test_nest_deposit()
	_test_nest_thresholds()

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


func _test_om_post_and_take() -> void:
	print("[Test] OM post_request and take_request")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	om.post_request("Gatherer")
	om.post_request("Gatherer")
	om.post_request("Explorer")
	_assert(om.get_request_count("Gatherer") == 2, "Two Gatherer requests posted")
	_assert(om.get_request_count("Explorer") == 1, "One Explorer request posted")
	_assert(om.get_total_request_count() == 3, "Three total requests")

	var taken = om.take_request("Gatherer")
	_assert(taken == true, "take_request returns true for existing request")
	_assert(om.get_request_count("Gatherer") == 1, "One Gatherer request remaining")

	var not_taken = om.take_request("Guard")
	_assert(not_taken == false, "take_request returns false for non-existing request")


func _test_om_clear_requests() -> void:
	print("[Test] OM clear_requests_for_role")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	om.post_request("Gatherer")
	om.post_request("Gatherer")
	om.post_request("Explorer")
	om.clear_requests_for_role("Gatherer")
	_assert(om.get_request_count("Gatherer") == 0, "Gatherer requests cleared")
	_assert(om.get_request_count("Explorer") == 1, "Explorer requests remain")


func _test_om_agent_tracking() -> void:
	print("[Test] OM agent role tracking")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	om.register_agent("agent_1", "Explorer")
	om.register_agent("agent_2", "Gatherer")
	_assert(om.get_role_count("Explorer") == 1, "One Explorer agent")
	_assert(om.get_role_count("Gatherer") == 1, "One Gatherer agent")
	_assert(om.get_total_agent_count() == 2, "Two total agents")

	om.update_agent_role("agent_1", "Gatherer")
	_assert(om.get_role_count("Explorer") == 0, "Zero Explorer agents after change")
	_assert(om.get_role_count("Gatherer") == 2, "Two Gatherer agents after change")

	om.unregister_agent("agent_2")
	_assert(om.get_total_agent_count() == 1, "One agent after unregister")


func _test_om_role_change_log() -> void:
	print("[Test] OM role change log")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	om.register_agent("agent_1", "Explorer")
	om.update_agent_role("agent_1", "Gatherer")
	var log = om.get_role_change_log()
	_assert(log.size() == 1, "One log entry")
	_assert(log[0]["agent_id"] == "agent_1", "Log agent_id is agent_1")
	_assert(log[0]["old_role"] == "Explorer", "Log old_role is Explorer")
	_assert(log[0]["new_role"] == "Gatherer", "Log new_role is Gatherer")


func _test_om_death_counter() -> void:
	print("[Test] OM death counter")
	var om_script = preload("res://organization/organization_manager.gd")
	var om = om_script.new()
	add_child(om)

	om.register_agent("agent_1", "Guard")
	om.handle_agent_death("agent_1")
	_assert(om.get_death_count() == 1, "Death count is 1")
	_assert(om.get_role_count("Guard") == 0, "Guard count is 0 after death")
	_assert(om.get_total_agent_count() == 0, "Agent count is 0 after death")


func _test_nest_deposit() -> void:
	print("[Test] Nest deposit and storage")
	var nest_script = preload("res://organization/nest.gd")
	var nest = nest_script.new()
	add_child(nest)

	nest.deposit("Food", 5)
	nest.deposit("Wood", 3)
	var summary = nest.get_storage_summary()
	_assert(summary["Food"] == 5, "Food storage is 5")
	_assert(summary["Wood"] == 3, "Wood storage is 3")
	_assert(nest.get_storage("Food") == 5, "get_storage Food returns 5")


func _test_nest_thresholds() -> void:
	print("[Test] Nest threshold signals")
	var nest_script = preload("res://organization/nest.gd")
	var nest = nest_script.new()
	add_child(nest)

	var results := {"low_received": false, "abundant_received": false, "low_type": "", "abundant_type": ""}

	nest.storage_low.connect(func(rt: String) -> void:
		results["low_received"] = true
		results["low_type"] = rt
	)
	nest.storage_abundant.connect(func(rt: String) -> void:
		results["abundant_received"] = true
		results["abundant_type"] = rt
	)

	for i in range(8):
		nest.deposit("Food", 1)
	_assert(results["low_received"], "storage_low signal emitted when Food <= 10")
	_assert(results["low_type"] == "Food", "storage_low type is Food")

	for i in range(45):
		nest.deposit("Food", 1)
	_assert(results["abundant_received"], "storage_abundant signal emitted when Food >= 50")
	_assert(results["abundant_type"] == "Food", "storage_abundant type is Food")
