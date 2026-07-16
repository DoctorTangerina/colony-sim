extends Node

var tests_passed: int = 0
var tests_failed: int = 0
var _signal_fired := false
var _signal_count := 0


func _ready() -> void:
	print("=== GOAP Blackboard T4 Test Harness (ReportResource Executor) ===")
	print("")

	_test_blackboard_add_entry_returns_true()
	_test_blackboard_add_entry_dedup_returns_false()
	_test_blackboard_get_entries_filter()
	_test_blackboard_has_entry_at()
	_test_blackboard_entries_changed_signal()
	_test_blackboard_remove_entries()
	_test_report_resource_writes_to_blackboard()
	_test_report_resource_clears_discovery_tracking()
	_test_report_resource_handles_dedup()
	_test_report_resource_requires_nest_and_blackboard()

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


func _make_blackboard() -> Node:
	var BlackboardScript = preload("res://organization/blackboard.gd")
	var bb = BlackboardScript.new()
	add_child(bb)
	return bb


func _make_mock_agent() -> Node:
	var agent_script = preload("res://agents/agent.gd")
	var agent = agent_script.new()
	agent.set("agent_id", "test_agent")
	agent.set("held_item", "None")
	agent.set("energy", 100.0)
	agent.set("hunger", 0.0)
	agent.set("nest_ref", null)
	return agent


func _make_mock_nest_with_blackboard() -> Node:
	var BlackboardScript = preload("res://organization/blackboard.gd")
	var nest_script = preload("res://organization/nest.gd")
	var nest = nest_script.new()
	var bb = BlackboardScript.new()
	bb.name = "Blackboard"
	nest.add_child(bb)
	nest.set("_blackboard", bb)
	add_child(nest)
	return nest


func _on_entries_changed(_entries) -> void:
	_signal_fired = true
	_signal_count += 1


func _test_blackboard_add_entry_returns_true() -> void:
	print("[Test] Blackboard add_entry returns true for new entry")
	var bb = _make_blackboard()
	var result: bool = bb.add_entry("Food", Vector2(100, 200))
	_assert(result == true, "add_entry returns true for new entry")
	_assert(bb.get_entry_count() == 1, "Entry count is 1 after add")


func _test_blackboard_add_entry_dedup_returns_false() -> void:
	print("[Test] Blackboard add_entry returns false for duplicate within tolerance")
	var bb = _make_blackboard()
	bb.add_entry("Food", Vector2(100, 200))
	var result: bool = bb.add_entry("Food", Vector2(105, 205))
	_assert(result == false, "add_entry returns false for duplicate within 10px")
	_assert(bb.get_entry_count() == 1, "Entry count still 1 after duplicate")


func _test_blackboard_get_entries_filter() -> void:
	print("[Test] Blackboard get_entries filters by type")
	var bb = _make_blackboard()
	bb.add_entry("Food", Vector2(100, 200))
	bb.add_entry("Wood", Vector2(300, 400))
	var food_entries = bb.get_entries("Food")
	_assert(food_entries.size() == 1, "get_entries('Food') returns 1 entry")
	_assert(food_entries[0]["type"] == "Food", "Filtered entry type is Food")
	var all_entries = bb.get_entries()
	_assert(all_entries.size() == 2, "get_entries() returns all 2 entries")


func _test_blackboard_has_entry_at() -> void:
	print("[Test] Blackboard has_entry_at checks proximity")
	var bb = _make_blackboard()
	bb.add_entry("Food", Vector2(100, 200))
	_assert(bb.has_entry_at("Food", Vector2(100, 200)) == true, "has_entry_at returns true for same position")
	_assert(bb.has_entry_at("Food", Vector2(200, 300)) == false, "has_entry_at returns false for distant position")
	_assert(bb.has_entry_at("Wood", Vector2(100, 200)) == false, "has_entry_at returns false for wrong type")


func _test_blackboard_entries_changed_signal() -> void:
	print("[Test] Blackboard entries_changed signal fires on mutation")
	var bb = _make_blackboard()
	_signal_fired = false
	_signal_count = 0
	bb.entries_changed.connect(_on_entries_changed)
	bb.add_entry("Food", Vector2(100, 200))
	_assert(_signal_fired, "entries_changed signal fired after add_entry")
	_assert(_signal_count == 1, "Signal fired exactly once")

	_signal_fired = false
	bb.remove_entries("Food", Vector2(100, 200))
	_assert(_signal_fired, "entries_changed signal fired after remove_entries")


func _test_blackboard_remove_entries() -> void:
	print("[Test] Blackboard remove_entries removes matching entries")
	var bb = _make_blackboard()
	bb.add_entry("Food", Vector2(100, 200))
	bb.add_entry("Wood", Vector2(300, 400))
	var removed = bb.remove_entries("Food")
	_assert(removed == 1, "remove_entries returns 1 for Food")
	_assert(bb.get_entry_count() == 1, "Only Wood entry remains")
	var remaining = bb.get_entries()
	_assert(remaining[0]["type"] == "Wood", "Remaining entry is Wood")


func _test_report_resource_writes_to_blackboard() -> void:
	print("[Test] ReportResource executor writes discovery to blackboard")
	var agent = _make_mock_agent()
	var nest = _make_mock_nest_with_blackboard()
	var blackboard = nest.get_blackboard()
	agent.set("nest_ref", nest)

	agent.set("discovered_resource_type", "Food")
	agent.set("discovered_resource_pos", Vector2(250, 350))

	GoapActionExecutor.execute_action("ReportResource", agent)

	var entries = blackboard.get_entries("Food")
	_assert(entries.size() == 1, "Blackboard has 1 Food entry after ReportResource")
	_assert(entries[0]["type"] == "Food", "Entry type is Food")
	_assert(entries[0]["position"].distance_to(Vector2(250, 350)) < 1.0, "Entry position matches discovery")


func _test_report_resource_clears_discovery_tracking() -> void:
	print("[Test] ReportResource executor clears discovery tracking after report")
	var agent = _make_mock_agent()
	var nest = _make_mock_nest_with_blackboard()
	agent.set("nest_ref", nest)

	agent.set("discovered_resource_type", "Wood")
	agent.set("discovered_resource_pos", Vector2(400, 500))

	GoapActionExecutor.execute_action("ReportResource", agent)

	_assert(agent.get("discovered_resource_type") == "", "discovered_resource_type cleared after report")
	_assert(agent.get("discovered_resource_pos") == Vector2.ZERO, "discovered_resource_pos cleared after report")


func _test_report_resource_handles_dedup() -> void:
	print("[Test] ReportResource executor handles blackboard dedup gracefully")
	var agent = _make_mock_agent()
	var nest = _make_mock_nest_with_blackboard()
	agent.set("nest_ref", nest)

	agent.set("discovered_resource_type", "Food")
	agent.set("discovered_resource_pos", Vector2(100, 200))
	GoapActionExecutor.execute_action("ReportResource", agent)

	agent.set("discovered_resource_type", "Food")
	agent.set("discovered_resource_pos", Vector2(103, 203))
	GoapActionExecutor.execute_action("ReportResource", agent)

	var entries = nest.get_blackboard().get_entries("Food")
	_assert(entries.size() == 1, "Blackboard still has 1 entry after duplicate report")
	_assert(agent.get("discovered_resource_type") == "", "discovered_resource_type cleared even on dedup")


func _test_report_resource_requires_nest_and_blackboard() -> void:
	print("[Test] ReportResource executor handles missing nest/blackboard gracefully")
	var agent = _make_mock_agent()
	agent.set("nest_ref", null)
	agent.set("discovered_resource_type", "Food")
	agent.set("discovered_resource_pos", Vector2(100, 200))

	GoapActionExecutor.execute_action("ReportResource", agent)
	_assert(true, "ReportResource with null nest does not crash")

	var nest = _make_mock_nest_with_blackboard()
	nest.set("_blackboard", null)
	agent.set("nest_ref", nest)
	agent.set("discovered_resource_type", "Food")
	agent.set("discovered_resource_pos", Vector2(100, 200))

	GoapActionExecutor.execute_action("ReportResource", agent)
	_assert(true, "ReportResource with null blackboard does not crash")
