extends Node

## Regression coverage for Ticket 3 of the GOAP rework
## (.scratch/goap-rework/tickets.md): ADR 5's remaining defects - #2
## (ping-pong / item destruction: nothing forbade planning Pickup with full
## hands), #3 (hollow pickup: the walk leg completed the action without
## grabbing), and #6 (DepositResource didn't empty hands in planner space).
## Pickup becomes a true instantaneous interaction, gated on Interaction
## Range (distinct from Discovery Radius), and hands stay honestly
## single-slot at both the planner and execution level.

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T25 Test Harness (Atomic, Honest Pickup - Single-Slot Hands) ===")
	print("")

	_test_pickup_actions_declare_has_item_false_and_at_position_preconditions()
	_test_validate_plan_rejects_pickup_with_full_hands()
	_test_attempt_pickup_never_overwrites_a_held_item()
	_test_attempt_pickup_grabs_within_interaction_range()
	_test_attempt_pickup_does_not_grab_outside_interaction_range()
	_test_at_food_position_independent_of_food_visible()
	_test_deposit_resource_effects_include_has_item_false()
	_test_gatherer_no_longer_ping_pongs_once_loaded()
	_test_gatherer_plans_goto_then_pickup_and_actually_holds_item()

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


func _make_nest() -> Node2D:
	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	return nest


func _make_mock_resource_manager(nodes: Array) -> Node:
	var script := GDScript.new()
	script.source_code = """extends Node

var active_nodes: Array = []

func get_nearest_resource(from_position: Vector2, resource_type: String):
	var nearest = null
	var nearest_dist := INF
	for node in active_nodes:
		if node.resource_type != resource_type or not is_instance_valid(node):
			continue
		var dist := from_position.distance_squared_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest

func get_all_resources() -> Array:
	return active_nodes.duplicate()

func resource_exists_at(resource_type: String, position: Vector2) -> bool:
	for node in active_nodes:
		if node.resource_type == resource_type and node.global_position.distance_to(position) < 50.0:
			return true
	return false
"""
	script.reload()
	var rm = script.new()
	add_child(rm)
	for node in nodes:
		rm.active_nodes.append(node)
	return rm


func _make_resource_node(res_type: String, pos: Vector2, amount: int = 100) -> Node:
	var node = preload("res://resources/resource_node.tscn").instantiate()
	node.resource_type = res_type
	node.remaining_amount = amount
	add_child(node)
	node.global_position = pos
	return node


func _test_pickup_actions_declare_has_item_false_and_at_position_preconditions() -> void:
	print("[Test] PickupFood/PickupWood declare has_item:false and at_<kind>_position:true preconditions")
	var actions: Array = ConfigLoader.load_array("res://configs/actions/actions.json")
	var pickup_food := {}
	var pickup_wood := {}
	for action in actions:
		if action.get("name", "") == "PickupFood":
			pickup_food = action
		if action.get("name", "") == "PickupWood":
			pickup_wood = action

	_assert(pickup_food.get("preconditions", {}) == {"has_item": false, "at_food_position": true},
		"PickupFood preconditions are exactly has_item:false + at_food_position:true (got: %s)" % [pickup_food.get("preconditions", {})])
	_assert(pickup_wood.get("preconditions", {}) == {"has_item": false, "at_wood_position": true},
		"PickupWood preconditions are exactly has_item:false + at_wood_position:true (got: %s)" % [pickup_wood.get("preconditions", {})])


## Defect #2: nothing used to forbid planning a Pickup while already holding
## something, so pick_up_item() silently overwrote the held item. The
## planner must now refuse to validate such a plan, even when the agent is
## otherwise standing right on top of the resource.
func _test_validate_plan_rejects_pickup_with_full_hands() -> void:
	print("[Test] validate_plan rejects PickupFood/PickupWood while hands are already full")
	var PlannerScript = preload("res://agents/planner/goap_planner.gd")
	var planner = PlannerScript.new()
	add_child(planner)

	var full_hands := WorldState.build("Wood", 100.0, 0.0, false, false, false, false, false, false, false, true, true)
	_assert(not planner.validate_plan(["PickupFood"], full_hands),
		"PickupFood is invalid while has_item is true, even standing at_food_position")
	_assert(not planner.validate_plan(["PickupWood"], full_hands),
		"PickupWood is invalid while has_item is true, even standing at_wood_position")

	planner.queue_free()


func _test_attempt_pickup_never_overwrites_a_held_item() -> void:
	print("[Test] attempt_pickup never overwrites an already-held item")
	var agent = _make_agent()
	agent.held_item = "Wood"
	agent.global_position = Vector2(500, 500)
	var food_node = _make_resource_node("Food", Vector2(500, 500))
	agent.resource_manager_ref = _make_mock_resource_manager([food_node])

	agent.attempt_pickup("Food")

	_assert(agent.held_item == "Wood", "held_item stays Wood - Pickup never silently overwrites a held item (got: %s)" % agent.held_item)
	_assert(food_node.remaining_amount == 100, "The Food node's stock is untouched when hands are already full (got: %s)" % food_node.remaining_amount)


## Defect #3: the old Pickup's walk leg completed the action without ever
## grabbing anything. attempt_pickup is the sole grab path now, and must
## genuinely extract from and hold the resource when in range.
func _test_attempt_pickup_grabs_within_interaction_range() -> void:
	print("[Test] attempt_pickup grabs a resource within Interaction Range and drains the node by 1")
	var agent = _make_agent()
	agent.held_item = "None"
	agent.global_position = Vector2(500, 500)
	var wood_node = _make_resource_node("Wood", Vector2(510, 500))
	agent.resource_manager_ref = _make_mock_resource_manager([wood_node])

	agent.attempt_pickup("Wood")

	_assert(agent.held_item == "Wood", "held_item reflects the grab (got: %s)" % agent.held_item)
	_assert(wood_node.remaining_amount == 99, "Node's stock decreased by exactly 1 (got: %s)" % wood_node.remaining_amount)


func _test_attempt_pickup_does_not_grab_outside_interaction_range() -> void:
	print("[Test] attempt_pickup does not grab a resource outside Interaction Range")
	var agent = _make_agent()
	agent.held_item = "None"
	agent.global_position = Vector2(0, 0)
	var food_node = _make_resource_node("Food", Vector2(200, 0))
	agent.resource_manager_ref = _make_mock_resource_manager([food_node])

	agent.attempt_pickup("Food")

	_assert(agent.held_item == "None", "held_item stays None when nothing is within Interaction Range (got: %s)" % agent.held_item)
	_assert(food_node.remaining_amount == 100, "Node's stock is untouched (got: %s)" % food_node.remaining_amount)


## Interaction Range (reaching) and Discovery Radius (seeing) are separate
## config values (CONTEXT.md) - a wider Discovery Radius must not leak into
## at_food_position, proving the two Sensed Facts are independently gated.
func _test_at_food_position_independent_of_food_visible() -> void:
	print("[Test] at_food_position (Interaction Range) and food_visible (Discovery Radius) are independently gated")
	var agent = _make_agent()
	agent._interaction_radius = 20.0
	agent._discovery_radius = 80.0
	agent.global_position = Vector2(0, 0)
	var food_node = _make_resource_node("Food", Vector2(50, 0))
	agent.resource_manager_ref = _make_mock_resource_manager([food_node])

	var state: WorldState = agent._build_world_state()
	_assert(state.food_visible, "food_visible is true within the (wider) Discovery Radius (got: %s)" % state.food_visible)
	_assert(not state.at_food_position, "at_food_position is false outside the (narrower) Interaction Range even though food_visible is true (got: %s)" % state.at_food_position)


## Defect #6: DepositResource's effects used to clear has_food/has_wood but
## not has_item, so hands looked honestly empty in has_food/has_wood terms
## but still "full" in has_item terms at the planner level.
func _test_deposit_resource_effects_include_has_item_false() -> void:
	print("[Test] DepositResource's declared effects include has_item:false")
	var actions: Array = ConfigLoader.load_array("res://configs/actions/actions.json")
	var deposit := {}
	for action in actions:
		if action.get("name", "") == "DepositResource":
			deposit = action
	_assert(deposit.get("effects", {}).get("has_item", null) == false,
		"DepositResource's effects include has_item:false (got: %s)" % [deposit.get("effects", {})])


## Defect #2's actual symptom: a Gatherer holding one resource kind, with a
## different kind's position also known, must consistently prefer
## DepositResource over starting a new Collect goal - never oscillate.
func _test_gatherer_no_longer_ping_pongs_once_loaded() -> void:
	print("[Test] A loaded Gatherer with another resource kind known never oscillates back into a Collect goal")
	var agent = _make_agent()
	agent._role_component.load_role("Gatherer")

	var state := WorldState.build("Wood", 100.0, 0.0, false, false, false, false, true, false)
	for i in range(5):
		var goal: Dictionary = agent._goal_selector.select_goal(state)
		_assert(goal.get("name", "") == "DepositResource",
			"Iteration %d selects DepositResource, never CollectFood, while hands are full (got: %s)" % [i, goal.get("name", "<none>")])


## End-to-end: a Gatherer with a known Food position, away from it, plans
## GoTo[Food] -> PickupFood, "arrives" (Navigator.arrived, simulated the same
## way test_goap_t24 does), and genuinely ends up holding Food - no hollow
## pickup, no silent no-op.
func _test_gatherer_plans_goto_then_pickup_and_actually_holds_item() -> void:
	print("[Test] A Gatherer plans GoTo[Food] -> PickupFood and genuinely ends up holding Food")
	var nest := _make_nest()
	nest.global_position = Vector2(0, 0)

	var agent := _make_agent()
	agent.setup(nest, null)
	agent._role_component.load_role("Gatherer")
	agent.held_item = "None"
	agent.global_position = Vector2(600, 600)

	var food_node := _make_resource_node("Food", Vector2(900, 900))
	agent.resource_manager_ref = _make_mock_resource_manager([food_node])
	var blackboard = nest.get_blackboard()
	blackboard.add_entry("Food", Vector2(900, 900))

	agent._goap_cycle.run_planning_cycle()

	_assert(agent._goap_cycle.current_goal == "CollectFood",
		"Gatherer selects CollectFood (got: %s)" % agent._goap_cycle.current_goal)
	_assert(agent._goap_cycle.current_plan.has("GoTo[Food]"),
		"Plan includes a GoTo[Food] leg (got: %s)" % [agent._goap_cycle.current_plan])
	_assert(agent._goap_cycle.current_plan.find("GoTo[Food]") < agent._goap_cycle.current_plan.find("PickupFood"),
		"GoTo[Food] precedes PickupFood (got: %s)" % [agent._goap_cycle.current_plan])

	# Simulate the walk resolving: physically place the agent within
	# Interaction Range of the food node (bypassing real pathfinding,
	# mirroring test_goap_t24's own pattern), then fire the same arrival
	# callback Navigator.arrived would. PickupFood is instantaneous, so it
	# resolves synchronously in the same cascade as GoTo[Food]'s completion.
	agent.global_position = food_node.global_position
	agent._on_arrived_at_target()

	_assert(agent.held_item == "Food", "Held item reflects the grab - no hollow pickup (got: %s)" % agent.held_item)
	_assert(food_node.remaining_amount == 99, "Food node's stock decreased by exactly 1 (got: %s)" % food_node.remaining_amount)
	_assert(agent._goap_cycle.current_plan.is_empty() and agent._goap_cycle.current_goal == "",
		"Plan completed cleanly after Pickup (goal: %s, plan: %s)" % [agent._goap_cycle.current_goal, agent._goap_cycle.current_plan])
