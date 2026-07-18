extends Node

var tests_passed: int = 0
var tests_failed: int = 0

const TEMP_ROLE_FILE := "__test_role_market_01.json"
const TEMP_ROLE_PATH := "res://configs/roles/%s" % TEMP_ROLE_FILE


func _ready() -> void:
	print("=== Role Market T01 Test Harness (Startup Role Scan) ===")
	print("")

	_test_startup_scan_loads_all_role_defs_without_manual_priming()
	_test_new_role_json_participates_with_no_engine_changes()
	_test_unassigned_has_no_config_file_and_is_never_scanned()
	_test_guard_distribution_is_zeroed_but_goals_and_actions_untouched()

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


func _test_startup_scan_loads_all_role_defs_without_manual_priming() -> void:
	print("[Test] OM._ready() scans configs/roles/ and loads every def with no manual priming")
	var om = _make_om()

	_assert(om._role_defs.has("Gatherer"), "Gatherer def loaded on startup")
	_assert(om._role_defs.has("Explorer"), "Explorer def loaded on startup")
	_assert(om._role_defs.has("Guard"), "Guard def loaded on startup")
	_assert(om._role_defs.get("Gatherer", {}).get("name") == "Gatherer", "Loaded def carries the role's own name field")


func _test_new_role_json_participates_with_no_engine_changes() -> void:
	print("[Test] Dropping a new role JSON makes it participate in target computation with no engine changes")

	var file := FileAccess.open(TEMP_ROLE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"name": "TestScout",
		"allowedGoals": [],
		"allowedActions": [],
		"priorityModifiers": {},
		"distribution": {
			"rules": [{ "default": true, "percent": 0.25 }]
		},
		"color": "#ffffff"
	}))
	file.close()

	var om = _make_om()
	_assert(om._role_defs.has("TestScout"), "New role file is discovered on startup with no engine changes")

	var target: Dictionary = om._compute_target_distribution(0, 0, 4)
	_assert(target.get("TestScout", 0) == 1, "New role participates in target computation (got %d)" % target.get("TestScout", 0))

	var dir := DirAccess.open("res://configs/roles")
	dir.remove(TEMP_ROLE_FILE)
	_assert(not FileAccess.file_exists(TEMP_ROLE_PATH), "Temporary test role file cleaned up")


func _test_unassigned_has_no_config_file_and_is_never_scanned() -> void:
	print("[Test] Unassigned stays special-cased: no config file, never scanned into role defs")
	_assert(not FileAccess.file_exists("res://configs/roles/unassigned.json"), "No unassigned.json exists in the roles config directory")

	var om = _make_om()
	_assert(not om._role_defs.has("Unassigned"), "Unassigned is never scanned into _role_defs")


func _test_guard_distribution_is_zeroed_but_goals_and_actions_untouched() -> void:
	print("[Test] Guard's distribution is zeroed while its goals/actions/priority modifiers stay intact")
	var om = _make_om()

	var guard_def: Dictionary = om._role_defs.get("Guard", {})
	var rules: Array = guard_def.get("distribution", {}).get("rules", [])
	var default_rule: Dictionary = {}
	for rule in rules:
		if rule.get("default", false):
			default_rule = rule
			break

	_assert(default_rule.get("percent", -1.0) == 0.0, "Guard's default distribution rule is zeroed")
	_assert(guard_def.get("allowedGoals", []) == ["DefendNest", "AttackEnemy"], "Guard's allowed goals are untouched")
	_assert(guard_def.get("allowedActions", []) == ["MoveTo"], "Guard's allowed actions are untouched")
	_assert(guard_def.get("priorityModifiers", {}).get("DefendNest", 0.0) == 3.0, "Guard's priority modifiers are untouched")

	var target: Dictionary = om._compute_target_distribution(0, 0, 20)
	_assert(target.get("Guard", -1) == 0, "Guard's target is zero under the zeroed distribution (got %d)" % target.get("Guard", -1))
