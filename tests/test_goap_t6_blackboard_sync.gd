extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T6 Test Harness (BlackboardSync Module) ===")
	print("")

	_test_sync_includes_entry_confirmed_by_resource_manager()
	_test_sync_excludes_stale_entry()
	_test_sync_handles_food_and_wood_together()
	_test_sync_returns_empty_dict_for_empty_blackboard()

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


func _make_mock_resource_manager(existing_positions: Array = []) -> Node:
	var script := GDScript.new()
	script.source_code = """extends Node

var existing_positions: Array = []

func resource_exists_at(resource_type: String, position: Vector2) -> bool:
	for entry in existing_positions:
		if entry["type"] == resource_type and entry["position"].distance_to(position) < 1.0:
			return true
	return false
"""
	script.reload()
	var rm = script.new()
	rm.existing_positions = existing_positions
	add_child(rm)
	return rm


func _test_sync_includes_entry_confirmed_by_resource_manager() -> void:
	print("[Test] sync_known_positions includes entries the ResourceManager confirms")
	var bb := _make_blackboard()
	bb.add_entry("Food", Vector2(100, 200))
	var rm := _make_mock_resource_manager([{"type": "Food", "position": Vector2(100, 200)}])

	var result := BlackboardSync.sync_known_positions(bb, rm)

	_assert(result.has("Food"), "Result has Food key")
	_assert(result["Food"].size() == 1, "Result has 1 Food position")
	_assert(result["Food"][0].distance_to(Vector2(100, 200)) < 1.0, "Position matches blackboard entry")


func _test_sync_excludes_stale_entry() -> void:
	print("[Test] sync_known_positions excludes entries the ResourceManager no longer confirms")
	var bb := _make_blackboard()
	bb.add_entry("Food", Vector2(100, 200))
	var rm := _make_mock_resource_manager([])

	var result := BlackboardSync.sync_known_positions(bb, rm)

	_assert(not result.has("Food"), "Stale Food entry excluded from result")


func _test_sync_handles_food_and_wood_together() -> void:
	print("[Test] sync_known_positions handles Food and Wood in one pass")
	var bb := _make_blackboard()
	bb.add_entry("Food", Vector2(100, 200))
	bb.add_entry("Wood", Vector2(300, 400))
	var rm := _make_mock_resource_manager([
		{"type": "Food", "position": Vector2(100, 200)},
		{"type": "Wood", "position": Vector2(300, 400)},
	])

	var result := BlackboardSync.sync_known_positions(bb, rm)

	_assert(result.has("Food") and result.has("Wood"), "Result has both Food and Wood keys")


func _test_sync_returns_empty_dict_for_empty_blackboard() -> void:
	print("[Test] sync_known_positions returns empty dict when blackboard has no entries")
	var bb := _make_blackboard()
	var rm := _make_mock_resource_manager([])

	var result := BlackboardSync.sync_known_positions(bb, rm)

	_assert(result.is_empty(), "Result is empty dict")
