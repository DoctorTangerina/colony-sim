extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP Blackboard T5 Test Harness (Gatherer Reads Blackboard) ===")
	print("")

	_test_resource_exists_at_true()
	_test_resource_exists_at_false_wrong_type()
	_test_resource_exists_at_false_distant()
	_test_resource_exists_at_false_empty()
	_test_clean_stale_removes_stale()
	_test_clean_stale_keeps_valid()
	_test_clean_stale_returns_count()
	_test_world_state_known_food_position()
	_test_world_state_known_wood_position()
	_test_world_state_no_known_positions()
	_test_move_to_uses_known_food_position()
	_test_pickup_food_uses_known_position_fallback()
	_test_agent_world_state_reads_blackboard()
	_test_nest_periodic_cleanup()

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


func _make_mock_resource_manager(nodes: Array = []) -> Node:
	var script := GDScript.new()
	script.source_code = """extends Node

var active_nodes: Array = []

func get_all_resources() -> Array:
	return active_nodes.duplicate()

func get_nearest_resource(from_position: Vector2, resource_type: String):
	var nearest = null
	var nearest_dist := INF
	for node in active_nodes:
		if node.get("resource_type") != resource_type:
			continue
		var dist := from_position.distance_squared_to(node.get("global_position"))
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest

func resource_exists_at(resource_type: String, position: Vector2) -> bool:
	for node in active_nodes:
		if not node.get("resource_type") == resource_type:
			continue
		if position.distance_to(node.get("global_position")) < 50.0:
			return true
	return false
"""
	script.reload()
	var rm = script.new()
	for node in nodes:
		rm.active_nodes.append(node)
	add_child(rm)
	return rm


func _make_mock_resource_node(res_type: String, pos: Vector2) -> Node:
	var script := GDScript.new()
	script.source_code = """extends Node

var resource_type: String = "Food"
var remaining_amount: int = 100
var global_position: Vector2 = Vector2.ZERO

func extract(amount: int) -> int:
	var actual = mini(amount, remaining_amount)
	remaining_amount -= actual
	return actual
"""
	script.reload()
	var node = script.new()
	node.set("resource_type", res_type)
	node.set("global_position", pos)
	add_child(node)
	return node


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


func _test_resource_exists_at_true() -> void:
	print("[Test] ResourceManager.resource_exists_at returns true for nearby node")
	var node = _make_mock_resource_node("Food", Vector2(100, 200))
	var rm = _make_mock_resource_manager([node])
	_assert(rm.resource_exists_at("Food", Vector2(100, 200)) == true, "Returns true for same position")
	_assert(rm.resource_exists_at("Food", Vector2(130, 220)) == true, "Returns true within 50px")


func _test_resource_exists_at_false_wrong_type() -> void:
	print("[Test] ResourceManager.resource_exists_at returns false for wrong type")
	var node = _make_mock_resource_node("Food", Vector2(100, 200))
	var rm = _make_mock_resource_manager([node])
	_assert(rm.resource_exists_at("Wood", Vector2(100, 200)) == false, "Returns false for wrong type")


func _test_resource_exists_at_false_distant() -> void:
	print("[Test] ResourceManager.resource_exists_at returns false for distant position")
	var node = _make_mock_resource_node("Food", Vector2(100, 200))
	var rm = _make_mock_resource_manager([node])
	_assert(rm.resource_exists_at("Food", Vector2(500, 600)) == false, "Returns false for distant position")


func _test_resource_exists_at_false_empty() -> void:
	print("[Test] ResourceManager.resource_exists_at returns false for empty manager")
	var rm = _make_mock_resource_manager()
	_assert(rm.resource_exists_at("Food", Vector2(100, 200)) == false, "Returns false when no nodes")


func _test_clean_stale_removes_stale() -> void:
	print("[Test] Blackboard.clean_stale_entries removes entries with no matching resource")
	var bb = _make_blackboard()
	var rm = _make_mock_resource_manager()
	bb.add_entry("Food", Vector2(100, 200))
	_assert(bb.get_entry_count() == 1, "Entry exists before clean")
	var removed = bb.clean_stale_entries(rm)
	_assert(removed == 1, "Removed 1 stale entry")
	_assert(bb.get_entry_count() == 0, "No entries after clean")


func _test_clean_stale_keeps_valid() -> void:
	print("[Test] Blackboard.clean_stale_entries keeps entries with matching resource")
	var bb = _make_blackboard()
	var node = _make_mock_resource_node("Food", Vector2(100, 200))
	var rm = _make_mock_resource_manager([node])
	bb.add_entry("Food", Vector2(100, 200))
	var removed = bb.clean_stale_entries(rm)
	_assert(removed == 0, "Removed 0 entries")
	_assert(bb.get_entry_count() == 1, "Entry still exists")


func _test_clean_stale_returns_count() -> void:
	print("[Test] Blackboard.clean_stale_entries returns correct count")
	var bb = _make_blackboard()
	var rm = _make_mock_resource_manager()
	bb.add_entry("Food", Vector2(100, 200))
	bb.add_entry("Wood", Vector2(300, 400))
	var removed = bb.clean_stale_entries(rm)
	_assert(removed == 2, "Removed 2 stale entries")


func _test_world_state_known_food_position() -> void:
	print("[Test] WorldStateBuilder includes known_food_position")
	var state = WorldStateBuilder.build("None", 100.0, 0.0, false, false, false, false, true, false)
	_assert(state.has("known_food_position"), "World state has known_food_position key")
	_assert(state.get("known_food_position") == true, "known_food_position is true when set")


func _test_world_state_known_wood_position() -> void:
	print("[Test] WorldStateBuilder includes known_wood_position")
	var state = WorldStateBuilder.build("None", 100.0, 0.0, false, false, false, false, false, true)
	_assert(state.has("known_wood_position"), "World state has known_wood_position key")
	_assert(state.get("known_wood_position") == true, "known_wood_position is true when set")


func _test_world_state_no_known_positions() -> void:
	print("[Test] WorldStateBuilder default known positions are false")
	var state = WorldStateBuilder.build("None", 100.0, 0.0, false, false, false)
	_assert(state.has("known_food_position"), "World state has known_food_position key")
	_assert(state.get("known_food_position") == false, "Default known_food_position is false")
	_assert(state.has("known_wood_position"), "World state has known_wood_position key")
	_assert(state.get("known_wood_position") == false, "Default known_wood_position is false")


func _test_move_to_uses_known_food_position() -> void:
	print("[Test] MoveTo executor uses known food positions as fallback")
	var agent_script = preload("res://agents/agent.gd")
	var agent = agent_script.new()
	agent.set("agent_id", "test_agent")
	agent.set("held_item", "None")
	agent.set("energy", 100.0)
	agent.set("hunger", 0.0)
	agent.set("nest_ref", null)
	agent.set("known_food_positions", {"Food": [Vector2(400, 500)]})
	agent.set("known_wood_positions", {})

	var move_called := false
	var move_target := Vector2.ZERO
	var agent_script2 = GDScript.new()
	agent_script2.source_code = """extends CharacterBody2D

var agent_id: String = "test"
var held_item: String = "None"
var energy: float = 100.0
var hunger: float = 0.0
var nest_ref = null
var known_food_positions: Dictionary = {}
var known_wood_positions: Dictionary = {}
var _move_called: bool = false
var _move_target: Vector2 = Vector2.ZERO

func move_to(target: Vector2) -> void:
	_move_called = true
	_move_target = target

func get_nest_position() -> Vector2:
	if nest_ref:
		return Vector2(576, 324)
	return Vector2.ZERO

func complete_action() -> void:
	pass
"""
	agent_script2.reload()
	agent.set_script(agent_script2)
	agent.set("known_food_positions", {"Food": [Vector2(400, 500)]})
	agent.set("known_wood_positions", {})
	agent.set("nest_ref", null)

	GoapActionExecutor.execute_action("MoveTo", agent)
	_assert(agent._move_called == true, "move_to was called")
	_assert(agent._move_target.distance_to(Vector2(400, 500)) < 1.0, "Moved to known food position")


func _test_pickup_food_uses_known_position_fallback() -> void:
	print("[Test] PickupFood uses known positions when resource not visible")
	var agent_script = preload("res://agents/agent.gd")
	var agent = agent_script.new()
	agent.set("agent_id", "test_agent")
	agent.set("held_item", "None")
	agent.set("energy", 100.0)
	agent.set("hunger", 0.0)
	agent.set("nest_ref", null)
	agent.set("global_position", Vector2(50, 50))

	var known_pos = Vector2(300, 400)
	var node = _make_mock_resource_node("Food", known_pos)
	var rm = _make_mock_resource_manager([node])
	agent.set("resource_manager_ref", rm)
	agent.set("known_food_positions", {"Food": [known_pos]})

	GoapActionExecutor.execute_action("PickupFood", agent)
	_assert(agent.get("target_resource") != null, "Target resource set from known position")


func _test_agent_world_state_reads_blackboard() -> void:
	print("[Test] Agent _build_world_state reads blackboard for known positions")
	var agent = _make_mock_agent()
	var nest = _make_mock_nest_with_blackboard()
	var blackboard = nest.get_blackboard()
	agent.set("nest_ref", nest)
	agent.set("global_position", Vector2(50, 50))
	agent.set("_discovery_radius", 50.0)

	blackboard.add_entry("Food", Vector2(500, 500))

	var node = _make_mock_resource_node("Food", Vector2(500, 500))
	var rm = _make_mock_resource_manager([node])
	agent.set("resource_manager_ref", rm)

	var world_state = agent._build_world_state()
	_assert(world_state.get("known_food_position") == true, "known_food_position is true from blackboard")
	_assert(agent.get("known_food_positions").has("Food"), "Agent has known_food_positions from blackboard")


func _test_nest_periodic_cleanup() -> void:
	print("[Test] Nest has blackboard_periodic_cleanup timer")
	var nest_script = preload("res://organization/nest.gd")
	var nest = nest_script.new()
	add_child(nest)
	var has_timer = false
	for child in nest.get_children():
		if child is Timer and child.name == "BlackboardCleanupTimer":
			has_timer = true
			break
	_assert(has_timer, "Nest has BlackboardCleanupTimer child")
