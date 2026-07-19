extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T8 Test Harness (Replanning on Invalid Plan) ===")
	print("")

	_test_validate_plan_rejects_plan_missing_item()
	_test_agent_replans_when_resource_disappears_mid_plan()
	_test_agent_falls_back_to_return_to_nest_when_no_resources_remain()

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


func _make_mock_resource_manager(food_visible: bool, wood_visible: bool) -> Node:
	var script := GDScript.new()
	script.source_code = """extends Node
var food_visible: bool = false
var wood_visible: bool = false

func get_nearest_resource(_pos: Vector2, resource_type: String) -> Node:
	if resource_type == "Food" and food_visible:
		return $Food
	if resource_type == "Wood" and wood_visible:
		return $Wood
	return null

func get_all_resources() -> Array:
	return []

func resource_exists_at(resource_type: String, _position: Vector2) -> bool:
	if resource_type == "Food":
		return food_visible
	if resource_type == "Wood":
		return wood_visible
	return false
"""
	script.reload()
	var rm = script.new()
	add_child(rm)

	var food_node := Node2D.new()
	food_node.name = "Food"
	food_node.global_position = Vector2(100, 100)
	rm.add_child(food_node)

	var wood_node := Node2D.new()
	wood_node.name = "Wood"
	wood_node.global_position = Vector2(200, 200)
	rm.add_child(wood_node)

	rm.food_visible = food_visible
	rm.wood_visible = wood_visible
	return rm


## The Gatherer's Collect goals now key off the blackboard (known_food_position/
## known_wood_position), not raw visibility - see the exploration-gating fix.
## This mirrors the resource manager's food_visible/wood_visible flags into
## real blackboard entries at the same positions so replanning tests still
## exercise a resource that's actually "known" to the colony.
func _make_mock_nest_with_known_positions(food_known: bool, wood_known: bool) -> Node2D:
	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	var blackboard = nest.get_blackboard()
	if food_known:
		blackboard.add_entry("Food", Vector2(100, 100))
	if wood_known:
		blackboard.add_entry("Wood", Vector2(200, 200))
	return nest


func _test_validate_plan_rejects_plan_missing_item() -> void:
	print("[Test] validate_plan rejects the tail of a plan once its resource precondition breaks")
	var agent = _make_agent()
	var world := WorldState.build("None", 100.0, 0.0, false, false, false)
	var remaining_plan := ["GoTo[Nest]", "DepositResource"]
	_assert(not agent._planner.validate_plan(remaining_plan, world),
		"GoTo[Nest]+DepositResource is invalid once has_item is false")


func _test_agent_replans_when_resource_disappears_mid_plan() -> void:
	print("[Test] Agent replans onto a still-available resource when the planned one disappears mid-plan")
	var agent = _make_agent()
	agent._role_component.load_role("Gatherer")
	agent.resource_manager_ref = _make_mock_resource_manager(false, true)
	agent.nest_ref = _make_mock_nest_with_known_positions(false, true)

	agent._goap_cycle.current_goal = "CollectFood"
	agent._goap_cycle.current_plan = ["PickupFood", "GoTo[Nest]", "DepositResource"]
	agent._goap_cycle._action_index = 0
	agent.held_item = "None"

	agent._goap_cycle.on_action_completed()

	_assert(agent._goap_cycle.current_goal != "CollectFood", "Stale CollectFood goal was abandoned (got: %s)" % agent._goap_cycle.current_goal)
	_assert(agent._goap_cycle.current_goal == "CollectWood", "Agent replanned onto CollectWood (got: %s)" % agent._goap_cycle.current_goal)
	# Pickup is now an instantaneous, Interaction-Range-gated interaction
	# (ADR 5, Ticket 3) - the agent starts away from the Wood node, so the
	# plan must include a GoTo[Wood] leg before PickupWood can run.
	_assert(agent._goap_cycle.current_plan == ["GoTo[Wood]", "PickupWood"], "New plan routes to the still-known Wood resource before picking it up (got: %s)" % [agent._goap_cycle.current_plan])
	_assert(agent._goap_cycle._action_in_progress, "Agent immediately started executing the new plan")


func _test_agent_falls_back_to_return_to_nest_when_no_resources_remain() -> void:
	print("[Test] Agent recovers without stalling when no resource remains for any goal")
	var agent = _make_agent()
	agent._role_component.load_role("Gatherer")
	agent.resource_manager_ref = _make_mock_resource_manager(false, false)

	agent._goap_cycle.current_goal = "CollectFood"
	agent._goap_cycle.current_plan = ["PickupFood", "GoTo[Nest]", "DepositResource"]
	agent._goap_cycle._action_index = 0
	agent.held_item = "None"

	agent._goap_cycle.on_action_completed()

	_assert(agent._goap_cycle.current_goal != "CollectFood", "Stale CollectFood goal was abandoned (got: %s)" % agent._goap_cycle.current_goal)
	_assert(agent._goap_cycle.current_plan.is_empty() and agent._goap_cycle.current_goal == "",
		"Agent goes idle cleanly rather than executing the stale invalid plan (goal: %s, plan: %s)" % [agent._goap_cycle.current_goal, agent._goap_cycle.current_plan])
