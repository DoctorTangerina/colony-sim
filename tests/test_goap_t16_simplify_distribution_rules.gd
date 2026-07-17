extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T16 Test Harness (Simplify Distribution Rules) ===")
	print("")

	_test_role_jsons_have_no_extension_fields()
	_test_gatherer_triggers_on_food_low_alone()
	_test_gatherer_triggers_on_wood_low_alone()
	_test_gatherer_does_not_trigger_when_both_abundant()
	_test_explorer_does_not_boost_when_only_one_resource_abundant()
	_test_explorer_boosts_when_both_resources_abundant()
	_test_guard_always_targets_ten_percent()

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


## Recursively walks a loaded JSON value (Dictionary/Array/scalar) looking for
## any of the removed rule-extension keys, wherever they might be nested.
func _contains_banned_key(value: Variant, banned_keys: Array) -> bool:
	if value is Dictionary:
		for key in value.keys():
			if key in banned_keys:
				return true
			if _contains_banned_key(value[key], banned_keys):
				return true
	elif value is Array:
		for item in value:
			if _contains_banned_key(item, banned_keys):
				return true
	return false


func _test_role_jsons_have_no_extension_fields() -> void:
	print("[Test] gatherer/explorer/guard.json contain no multiply_level, and_type, or and_level")
	var banned := ["multiply_level", "and_type", "and_level"]

	for role_file in ["gatherer", "explorer", "guard"]:
		var data: Dictionary = ConfigLoader.load_dict("res://configs/roles/%s.json" % role_file)
		_assert(not _contains_banned_key(data, banned),
			"%s.json has no removed extension fields" % role_file)


func _test_gatherer_triggers_on_food_low_alone() -> void:
	print("[Test] Gatherer triggers when only Food is low (OR semantics)")
	var om = _make_om_with_role_defs()

	var target = om._compute_target_distribution(5, 60, 10)
	_assert(target.get("Gatherer", 0) == 5,
		"Gatherer hits the boosted 50%% target on Food-low alone (got %d)" % target.get("Gatherer", 0))


func _test_gatherer_triggers_on_wood_low_alone() -> void:
	print("[Test] Gatherer triggers when only Wood is low (OR semantics)")
	var om = _make_om_with_role_defs()

	var target = om._compute_target_distribution(60, 5, 10)
	_assert(target.get("Gatherer", 0) == 5,
		"Gatherer hits the boosted 50%% target on Wood-low alone (got %d)" % target.get("Gatherer", 0))


func _test_gatherer_does_not_trigger_when_both_abundant() -> void:
	print("[Test] Gatherer falls back to its default (0%) target when neither resource is low")
	var om = _make_om_with_role_defs()

	var target = om._compute_target_distribution(60, 60, 10)
	_assert(target.get("Gatherer", 0) == 0,
		"Gatherer target is 0 when both resources are abundant (got %d)" % target.get("Gatherer", 0))


func _test_explorer_does_not_boost_when_only_one_resource_abundant() -> void:
	print("[Test] Explorer requires BOTH resources abundant (AND semantics), not just one")
	var om = _make_om_with_role_defs()

	var target = om._compute_target_distribution(60, 5, 10)
	_assert(target.get("Explorer", 0) == 2,
		"Explorer falls back to its default 20%% target with only Food abundant (got %d)" % target.get("Explorer", 0))


func _test_explorer_boosts_when_both_resources_abundant() -> void:
	print("[Test] Explorer hits its boosted target once both resources are abundant")
	var om = _make_om_with_role_defs()

	var target = om._compute_target_distribution(60, 60, 10)
	_assert(target.get("Explorer", 0) == 4,
		"Explorer hits the boosted 40%% target with both resources abundant (got %d)" % target.get("Explorer", 0))


func _test_guard_always_targets_ten_percent() -> void:
	print("[Test] Guard's target is a flat 10% regardless of resource levels")
	var om = _make_om_with_role_defs()

	var low_scenario = om._compute_target_distribution(5, 5, 10)
	var abundant_scenario = om._compute_target_distribution(60, 60, 10)

	_assert(low_scenario.get("Guard", 0) == 1, "Guard target is 10%% of 10 when resources are low (got %d)" % low_scenario.get("Guard", 0))
	_assert(abundant_scenario.get("Guard", 0) == 1, "Guard target is 10%% of 10 when resources are abundant (got %d)" % abundant_scenario.get("Guard", 0))
