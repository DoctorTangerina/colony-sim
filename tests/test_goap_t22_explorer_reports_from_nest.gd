extends Node

## Regression coverage for the "explorer walks past a resource and never
## notices" bug plus the report-from-nest gating fix: discovery must be
## scanned every frame (not only at planning-cycle ticks, which an agent in
## transit can easily slip between), and a discovered resource must stay a
## private fact on the Explorer (has_unreported_discovery) until it physically
## returns to the nest and executes ReportResource - only then does the
## coordinate reach the Blackboard where Gatherers can see it.

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T22 Test Harness (Explorer Reports From Nest) ===")
	print("")

	_test_explorer_discovers_resource_it_walks_past()
	_test_explorer_does_not_discover_resource_never_approached()
	_test_report_resource_requires_at_nest_now()
	_test_explorer_plans_return_to_nest_before_reporting()
	_test_blackboard_stays_empty_until_explorer_reports_at_nest()

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


func _make_real_nest() -> Node2D:
	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	return nest


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


## Root-cause check: discovery was only ever scanned inside _build_world_state,
## which GoapCycle calls just once per planning tick (default 2s) or on action
## completion - never every frame. An Explorer travelling in a straight line
## can clip a resource's discovery radius for well under a second, entirely
## between two of those checks, and never register it. Freeze the planning
## timer so no plan cycle fires during the walk - only per-frame scanning
## (agent._process) can catch the resource here.
func _test_explorer_discovers_resource_it_walks_past() -> void:
	print("[Test] Explorer discovers a resource it walks past mid-transit, not just on a lucky planning tick")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")
	agent._goal_selector.set_role_component(agent._role_component)
	agent.global_position = Vector2(0, 300)
	agent.nest_ref = _make_real_nest()
	var passed_food = _make_mock_resource_node("Food", Vector2(300, 300))
	agent.resource_manager_ref = _make_mock_resource_manager([passed_food])
	agent._goap_cycle._planning_timer = 999.0

	var steps := 20
	for i in range(steps):
		agent.global_position = agent.global_position.lerp(Vector2(600, 300), float(i + 1) / steps)
		agent._process(0.025)

	_assert(agent.discovered_resource_type == "Food",
		"discovered_resource_type set to Food after walking past it (got: '%s')" % agent.discovered_resource_type)
	_assert(agent.discovered_resource_pos.distance_to(Vector2(300, 300)) < 1.0,
		"discovered_resource_pos matches the passed node (got: %s)" % [agent.discovered_resource_pos])


## Sanity counterpart: a resource the agent's path never comes near should
## still not be discovered, proving the fix scans proximity rather than
## marking everything visited as discovered.
func _test_explorer_does_not_discover_resource_never_approached() -> void:
	print("[Test] Explorer does NOT discover a resource its path never comes near")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")
	agent._goal_selector.set_role_component(agent._role_component)
	agent.global_position = Vector2(0, 300)
	agent.nest_ref = _make_real_nest()
	var far_food = _make_mock_resource_node("Food", Vector2(300, 3000))
	agent.resource_manager_ref = _make_mock_resource_manager([far_food])
	agent._goap_cycle._planning_timer = 999.0

	var steps := 20
	for i in range(steps):
		agent.global_position = agent.global_position.lerp(Vector2(600, 300), float(i + 1) / steps)
		agent._process(0.025)

	_assert(agent.discovered_resource_type == "",
		"discovered_resource_type stays empty for a resource never approached (got: '%s')" % agent.discovered_resource_type)


## ReportResource used to fire off of momentary proximity (near_unreported_resource)
## from anywhere on the map. It now requires the Explorer to actually be at the
## nest - proximity alone (still away from the nest) must not satisfy it.
func _test_report_resource_requires_at_nest_now() -> void:
	print("[Test] ReportResource precondition requires at_nest, not mere proximity to the resource")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")
	agent._goal_selector.set_role_component(agent._role_component)

	var away_from_nest := WorldState.build("None", 100.0, 0.0, false, true, false, true, false, false, true)
	_assert(not agent._planner.validate_plan(["ReportResource"], away_from_nest),
		"ReportResource is invalid away from the nest even while carrying a discovery")

	var at_nest := WorldState.build("None", 100.0, 0.0, true, false, false, false, false, false, true)
	_assert(agent._planner.validate_plan(["ReportResource"], at_nest),
		"ReportResource is valid once at the nest with an unreported discovery")


## An Explorer that discovered a resource away from the nest must route back
## through the universal, grounded GoTo[Nest] before ReportResource can run -
## this is the actual "go inform the colony" behavior the ticket asks for.
func _test_explorer_plans_return_to_nest_before_reporting() -> void:
	print("[Test] Explorer's plan sends it back to the nest before reporting a discovery")
	var agent = _make_agent()
	agent._role_component.load_role("Explorer")
	agent._goal_selector.set_role_component(agent._role_component)

	var state := WorldState.build("None", 100.0, 0.0, false, true, false, true, false, false, true)
	var goal: Dictionary = agent._goal_selector.select_goal(state)
	_assert(goal.get("name", "") == "Explore", "Explore goal remains selectable away from nest (got: %s)" % [goal.get("name", "<none>")])

	var plan: Array = agent._planner.create_plan("Explore", state, agent._role_component.get_allowed_actions())
	_assert(plan.has("GoTo[Nest]"), "Plan routes the Explorer back to the nest (got: %s)" % [plan])
	_assert(plan.has("ReportResource"), "Plan still includes ReportResource (got: %s)" % [plan])
	_assert(plan.find("GoTo[Nest]") < plan.find("ReportResource"),
		"GoTo[Nest] happens before ReportResource (got: %s)" % [plan])


## End-to-end: the Blackboard (and therefore Gatherers reading known positions
## off it) must not learn about a discovery until the Explorer's ReportResource
## action actually executes at the nest.
func _test_blackboard_stays_empty_until_explorer_reports_at_nest() -> void:
	print("[Test] Blackboard gains the entry only once ReportResource executes at the nest")
	var agent = _make_agent()
	agent.nest_ref = _make_real_nest()
	var blackboard = agent.nest_ref.get_blackboard()

	agent.set("discovered_resource_type", "Food")
	agent.set("discovered_resource_pos", Vector2(250, 350))

	_assert(blackboard.get_entry_count() == 0, "Blackboard has no entries before ReportResource executes")

	GoapActionExecutor.execute_action("ReportResource", agent)

	_assert(blackboard.get_entry_count() == 1, "Blackboard gains the entry once ReportResource executes")
