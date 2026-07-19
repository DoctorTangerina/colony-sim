extends Node

## Regression coverage for Ticket 2 of the GOAP rework
## (.scratch/goap-rework/tickets.md): the freeze/ping-pong bug's actual fix
## (ADR 5 defect #1) plus retiring the second, hardcoded "at the nest"
## definition (defect #7). GoTo is grounded from the Nest plus
## configs/resources.json (never hand-listed - ADR 8); DepositResource and
## Rest lose their at_nest goal precondition (relevance only, never
## reachability); at_nest becomes the Nest's TriggerZone, sole source of
## truth.

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T24 Test Harness (Grounded GoTo, Relevance-Only Goals) ===")
	print("")

	_test_goto_grounds_nest_from_real_configs()
	_test_goto_destination_kinds_derive_from_resource_registry()
	_test_goto_grounds_all_kinds_now_that_ticket_3_added_their_fields()
	_test_goto_effect_claims_only_its_own_destination()
	_test_no_role_config_lists_goto()
	_test_actions_json_has_no_move_to_or_return_to_nest()
	_test_goals_json_has_no_standalone_return_to_nest()
	await _test_at_nest_is_not_instantaneous_distance_based()
	await _test_gatherer_deposits_via_goto_instead_of_freezing()

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


func _test_goto_grounds_nest_from_real_configs() -> void:
	print("[Test] GOAPPlanner grounds GoTo[Nest] from the real action/resource configs")
	var planner = preload("res://agents/planner/goap_planner.gd").new()
	add_child(planner)

	var goto_nest := {}
	for action in planner.get_actions():
		if action.get("name", "") == "GoTo[Nest]":
			goto_nest = action

	_assert(not goto_nest.is_empty(), "Planner's loaded actions include GoTo[Nest]")
	_assert(goto_nest.get("preconditions", {}) == {}, "GoTo[Nest] has no preconditions (relevance only, always reachable)")
	_assert(goto_nest.get("effects", {}) == {"at_nest": true}, "GoTo[Nest]'s effect is exactly at_nest:true (got: %s)" % [goto_nest.get("effects", {})])

	planner.queue_free()


## GoTo's destination kinds are never hand-listed (ADR 8): the enumeration
## takes an arbitrary resource-kind list and a stub, in-schema field list -
## a brand new "Stone" kind flows straight through with no code change,
## proving nothing here is hardcoded to "Food"/"Wood" specifically.
func _test_goto_destination_kinds_derive_from_resource_registry() -> void:
	print("[Test] GoTo destination kinds derive from an arbitrary resource-kind list, not a hand-maintained one")
	var kinds := GotoGrounding.destination_kinds(["Food", "Wood", "Stone"])
	_assert(kinds == ["Nest", "Food", "Wood", "Stone"], "Nest plus every registry entry, in order (got: %s)" % [kinds])

	var stub_fields := ["at_nest", "at_stone_position"]
	var actions := GotoGrounding.build_actions(["Food", "Wood", "Stone"], stub_fields)
	var names: Array = []
	for action in actions:
		names.append(action["name"])

	_assert("GoTo[Stone]" in names, "A brand new resource kind gets grounded once its WorldState field exists (got: %s)" % [names])
	_assert(not ("GoTo[Food]" in names) and not ("GoTo[Wood]" in names),
		"Kinds without a matching field are not grounded (got: %s)" % [names])


## At Ticket 2, WorldState only carried an "arrived" field for the Nest
## (at_nest) - Food/Wood had no Sensed Fact yet, so grounding skipped them
## rather than fabricate an effect key WorldState would reject (Ticket 1's
## loud-failure hardening). Ticket 3 added at_food_position/at_wood_position,
## so this same, unmodified grounding code now produces all three against the
## real schema with no planner change required - the exact consequence
## Ticket 2's implementation notes called out in advance.
func _test_goto_grounds_all_kinds_now_that_ticket_3_added_their_fields() -> void:
	print("[Test] GoTo grounds Nest, Food, and Wood against today's real WorldState schema")
	var actions := GotoGrounding.build_actions(["Food", "Wood"], WorldState.new().get_field_keys())
	var names: Array = []
	for action in actions:
		names.append(action["name"])
	_assert(names == ["GoTo[Nest]", "GoTo[Food]", "GoTo[Wood]"], "All three destination kinds are grounded (got: %s)" % [names])


func _test_goto_effect_claims_only_its_own_destination() -> void:
	print("[Test] GoTo[Nest]'s effect claims only arrival at the Nest, never leaving anywhere else")
	var actions := GotoGrounding.build_actions([], ["at_nest"])
	_assert(actions.size() == 1, "One grounded action")
	_assert(actions[0]["effects"].size() == 1 and actions[0]["effects"].get("at_nest", false) == true,
		"Effect dict is exactly {at_nest: true}, no other claims (got: %s)" % [actions[0]["effects"]])


func _test_no_role_config_lists_goto() -> void:
	print("[Test] No role config lists GoTo (or a grounded GoTo[...] instance) in allowedActions")
	for role_name in ["gatherer", "explorer", "guard"]:
		var data: Dictionary = ConfigLoader.load_dict("res://configs/roles/%s.json" % role_name)
		var allowed: Array = data.get("allowedActions", [])
		var has_goto := false
		for action_name in allowed:
			if action_name == "GoTo" or String(action_name).begins_with("GoTo["):
				has_goto = true
		_assert(not has_goto, "%s's allowedActions does not list GoTo (got: %s)" % [role_name, allowed])


func _test_actions_json_has_no_move_to_or_return_to_nest() -> void:
	print("[Test] configs/actions/actions.json has no MoveTo/ReturnToNest entries")
	var actions: Array = ConfigLoader.load_array("res://configs/actions/actions.json")
	var names: Array = []
	for action in actions:
		names.append(action.get("name", ""))
	_assert(not ("MoveTo" in names), "No MoveTo action entry (got: %s)" % [names])
	_assert(not ("ReturnToNest" in names), "No ReturnToNest action entry (got: %s)" % [names])


func _test_goals_json_has_no_standalone_return_to_nest() -> void:
	print("[Test] configs/goals/goals.json has no standalone ReturnToNest goal")
	var goals: Array = ConfigLoader.load_array("res://configs/goals/goals.json")
	var names: Array = []
	for goal in goals:
		names.append(goal.get("name", ""))
	_assert(not ("ReturnToNest" in names), "No ReturnToNest goal entry (got: %s)" % [names])


## Defect #7: proves at_nest is genuinely TriggerZone/Area2D-signal driven,
## not a live distance recompute - the old hardcoded check would have
## reported true the instant the agent's position moved into range, with no
## physics frame required. nest.json's triggerZoneRadius happens to also be
## 50.0 today, so only this timing gap - not the numeric threshold - can
## distinguish the two implementations.
func _test_at_nest_is_not_instantaneous_distance_based() -> void:
	print("[Test] at_nest reflects the Nest TriggerZone signal, not an instantaneous distance check")
	var nest := _make_nest()
	nest.global_position = Vector2.ZERO
	var agent := _make_agent()
	agent.setup(nest, null)

	agent.global_position = Vector2(10, 0)
	var immediate_state: WorldState = agent._build_world_state()
	_assert(not immediate_state.at_nest,
		"at_nest is false immediately after teleporting into range, before any physics frame lets the zone signal fire")

	await get_tree().physics_frame
	await get_tree().physics_frame

	var settled_state: WorldState = agent._build_world_state()
	_assert(settled_state.at_nest, "at_nest becomes true once the TriggerZone has actually detected the agent")


## The end-to-end freeze scenario from ISSUE.md's defect #1: a loaded
## Gatherer, away from the Nest, used to have zero selectable goals
## (DepositResource's old goal precondition required at_nest already being
## true) and stood frozen holding its item forever. It must now plan
## GoTo[Nest] -> DepositResource, walk itself into range, and complete the
## deposit. Held item is Wood, not Food, for the same reason as the t1
## unit test above: Eat also clears has_food at a tied cost and would let
## the agent "resolve" DepositResource by eating instead of depositing.
func _test_gatherer_deposits_via_goto_instead_of_freezing() -> void:
	print("[Test] A loaded Gatherer away from the Nest resolves via GoTo[Nest] -> DepositResource instead of freezing")
	var nest := _make_nest()
	nest.global_position = Vector2.ZERO

	var agent := _make_agent()
	agent.setup(nest, null)
	agent._role_component.load_role("Gatherer")
	agent.held_item = "Wood"
	agent.global_position = Vector2(600, 600)

	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(not agent._nest_zone.is_in_nest_zone(), "Sanity: agent starts outside the nest trigger zone")

	agent._goap_cycle.run_planning_cycle()

	_assert(agent._goap_cycle.current_goal == "DepositResource",
		"Gatherer selects DepositResource instead of freezing with no goal (got: %s)" % agent._goap_cycle.current_goal)
	_assert(agent._goap_cycle.current_plan.has("GoTo[Nest]"),
		"Plan includes a GoTo[Nest] leg (got: %s)" % [agent._goap_cycle.current_plan])
	_assert(agent._goap_cycle.current_plan.find("GoTo[Nest]") < agent._goap_cycle.current_plan.find("DepositResource"),
		"GoTo[Nest] precedes DepositResource (got: %s)" % [agent._goap_cycle.current_plan])
	_assert(agent._goap_cycle._action_in_progress, "Agent started executing GoTo[Nest] instead of standing still")

	# Simulate the walk resolving: physically enter the trigger zone (bypassing
	# real pathfinding, mirroring test_goap_t10's own physics-frame pattern),
	# then fire the same arrival callback Navigator.arrived would.
	agent.global_position = nest.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(agent._nest_zone.is_in_nest_zone(), "Sanity: agent is now inside the nest trigger zone")

	agent._on_arrived_at_target()

	_assert(agent.held_item == "None", "Held item was deposited, not stuck forever (got: %s)" % agent.held_item)
	_assert(nest.get_storage("Wood") == 1, "Nest storage increased by the deposited item (got: %s)" % nest.get_storage("Wood"))
	_assert(agent._goap_cycle.current_plan.is_empty() and agent._goap_cycle.current_goal == "",
		"Plan completed cleanly, agent is not stuck mid-plan (goal: %s, plan: %s)" % [agent._goap_cycle.current_goal, agent._goap_cycle.current_plan])
