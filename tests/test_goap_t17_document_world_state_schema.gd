extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T17 Test Harness (Document World State Schema) ===")
	print("")

	_test_all_action_precondition_and_effect_keys_are_documented()
	_test_all_goal_precondition_and_effect_keys_are_documented()
	_test_known_position_fields_are_permanent_schema_members()

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


## Every precondition/effect key across configs/actions and configs/goals
## must be a field WorldState actually tracks - an undocumented key is
## silently dropped by WorldState.satisfies()/merge(), which is exactly the
## bug this ticket closes (a stray "resource_reported" key used to make
## DiscoverResource's goal unreachable without any error).
func _collect_state_keys(entries: Array) -> Array:
	var keys := {}
	for entry in entries:
		for section in ["preconditions", "effects"]:
			var section_dict: Dictionary = entry.get(section, {})
			for key in section_dict.keys():
				keys[key] = true
	return keys.keys()


func _test_all_action_precondition_and_effect_keys_are_documented() -> void:
	print("[Test] Every actions.json precondition/effect key is a documented WorldState field")
	var actions: Array = ConfigLoader.load_array("res://configs/actions/actions.json")
	var field_keys: Array = WorldState.new().get_field_keys()

	var undocumented: Array = []
	for key in _collect_state_keys(actions):
		if key not in field_keys:
			undocumented.append(key)

	_assert(undocumented.is_empty(), "No undocumented keys in actions.json (got: %s)" % [undocumented])


func _test_all_goal_precondition_and_effect_keys_are_documented() -> void:
	print("[Test] Every goals.json precondition/effect key is a documented WorldState field")
	var goals: Array = ConfigLoader.load_array("res://configs/goals/goals.json")
	var field_keys: Array = WorldState.new().get_field_keys()

	var undocumented: Array = []
	for key in _collect_state_keys(goals):
		if key not in field_keys:
			undocumented.append(key)

	_assert(undocumented.is_empty(), "No undocumented keys in goals.json (got: %s)" % [undocumented])


func _test_known_position_fields_are_permanent_schema_members() -> void:
	print("[Test] known_food_position/known_wood_position remain permanent WorldState fields")
	var field_keys: Array = WorldState.new().get_field_keys()

	_assert("known_food_position" in field_keys, "known_food_position is a documented field")
	_assert("known_wood_position" in field_keys, "known_wood_position is a documented field")
