extends Node

## Diagnostic harness for the reported bug: explorer stalls at nest, gatherer
## beelines to undiscovered resources, gatherer skips delivering held items.
## Not a permanent regression test - see Phase 1 of the diagnosing-bugs skill.

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Bug Diagnostic: Resource Visibility / Exploration Gating ===")
	print("")

	_test_food_visible_ignores_distance()
	_test_explorer_gets_no_goal_when_undiscovered_resource_exists()
	_test_gatherer_can_collect_undiscovered_resource_directly()
	_test_gatherer_deprioritizes_deposit_vs_new_collection()

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


func _make_agent() -> Node:
	var agent_scene: PackedScene = preload("res://agents/agent.tscn")
	var agent = agent_scene.instantiate()
	add_child(agent)
	return agent


func _make_mock_resource_manager(nodes: Array) -> Node:
	var script := GDScript.new()
	script.source_code = """extends Node

var active_nodes: Array = []

func get_nearest_resource(_from_position: Vector2, resource_type: String):
	for node in active_nodes:
		if node.resource_type == resource_type:
			return node
	return null

func get_all_resources() -> Array:
	return active_nodes.duplicate()
"""
	script.reload()
	var rm = script.new()
	add_child(rm)
	for node in nodes:
		rm.active_nodes.append(node)
	return rm


func _make_mock_resource_node(res_type: String, pos: Vector2) -> Node:
	var script := GDScript.new()
	script.source_code = """extends Node2D

var resource_type: String = "Food"
var remaining_amount: int = 100
"""
	script.reload()
	var node = script.new()
	node.set("resource_type", res_type)
	add_child(node)
	node.global_position = pos
	return node


## Root-cause check: ResourceManager.get_nearest_resource has no distance
## cutoff, and agent._build_world_state() treats "a node exists somewhere"
## as "food_visible". A resource 5000px away (discovery radius is 50px) must
## not count as visible.
func _test_food_visible_ignores_distance() -> void:
	print("[Test] food_visible should require proximity, not mere existence")
	var agent = _make_agent()
	agent.global_position = Vector2(100, 100)
	var far_food = _make_mock_resource_node("Food", Vector2(5000, 5000))
	agent.resource_manager_ref = _make_mock_resource_manager([far_food])
	agent.nest_ref = null

	var state: WorldState = agent._build_world_state()
	_assert(state.food_visible == false, "food_visible is false for a resource 5000px away (got true)")


## Explorer's only goal (Explore) has effect resource_visible=true. If
## food_visible/wood_visible are wrongly true from goal 1, create_plan sees
## the goal as already achieved and the Explorer never gets a plan - it
## stands still.
func _test_explorer_gets_no_goal_when_undiscovered_resource_exists() -> void:
	print("[Test] Explorer should still get the Explore goal when a resource exists but is undiscovered")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")
	agent._goal_selector.set_role_component(agent._role_component)
	agent.global_position = Vector2(100, 100)
	var far_food = _make_mock_resource_node("Food", Vector2(5000, 5000))
	agent.resource_manager_ref = _make_mock_resource_manager([far_food])
	agent.nest_ref = null

	var state: WorldState = agent._build_world_state()
	var goal: Dictionary = agent._goal_selector.select_goal(state)
	_assert(not goal.is_empty(), "Explorer selects a goal (Explore) instead of standing idle (got empty goal)")


## Gatherer should only be able to path to a resource once it (or the
## blackboard) knows the resource exists - not to any node anywhere on the
## map via the unfiltered get_nearest_resource() lookup.
func _test_gatherer_can_collect_undiscovered_resource_directly() -> void:
	print("[Test] Gatherer should NOT be able to collect a resource neither visible nor known via blackboard")
	var agent = _make_agent()
	agent._role_component.load_role("Gatherer")
	agent._goal_selector.set_role_component(agent._role_component)
	agent.global_position = Vector2(100, 100)
	var far_food = _make_mock_resource_node("Food", Vector2(5000, 5000))
	agent.resource_manager_ref = _make_mock_resource_manager([far_food])
	agent.nest_ref = null

	var state: WorldState = agent._build_world_state()
	var goal: Dictionary = agent._goal_selector.select_goal(state)
	_assert(goal.is_empty(), "Gatherer gets no goal for an undiscovered resource (got: %s)" % [goal.get("name", "<none>")])


## Once holding an item, a Gatherer that also has a second resource type
## "visible" should prefer delivering the held item over collecting more -
## priorityModifiers currently score CollectWood (2.0*5=10) above
## DepositResource (1.5*6=9).
func _test_gatherer_deprioritizes_deposit_vs_new_collection() -> void:
	print("[Test] Gatherer holding Food should prefer DepositResource over starting CollectWood")
	var agent = _make_agent()
	agent._role_component.load_role("Gatherer")
	agent._goal_selector.set_role_component(agent._role_component)

	var state := WorldState.build("Food", 100.0, 0.0, false, false, true)
	var goal: Dictionary = agent._goal_selector.select_goal(state)
	_assert(goal.get("name", "") == "DepositResource",
		"Gatherer prioritizes DepositResource while holding an item (got: %s)" % [goal.get("name", "<none>")])
