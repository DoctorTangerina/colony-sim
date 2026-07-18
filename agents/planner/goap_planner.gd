extends Node

var _actions: Array = []
var _goals: Array = []
var _max_depth: int = 20


func _ready() -> void:
	_load_configs()


func set_actions(actions: Array) -> void:
	_actions = actions


func set_goals(goals: Array) -> void:
	_goals = goals


func get_actions() -> Array:
	return _actions


func get_goals() -> Array:
	return _goals


func get_goal_by_name(goal_name: String) -> Dictionary:
	for goal in _goals:
		if goal["name"] == goal_name:
			return goal
	return {}


func create_plan(goal_name: String, world_state: WorldState, allowed_actions: Array = []) -> Array:
	var goal := get_goal_by_name(goal_name)
	if goal.is_empty():
		return []

	var goal_preconditions: Dictionary = goal.get("preconditions", {})
	if not GoapUtils.state_satisfies(world_state, goal_preconditions):
		return []

	var goal_effects: Dictionary = goal.get("effects", {})
	if goal_effects.is_empty():
		return []

	if GoapUtils.state_satisfies(world_state, goal_effects):
		return []

	var applicable := _get_applicable_actions(world_state, allowed_actions)
	if applicable.is_empty():
		return []

	var result := _forward_search(world_state, goal_effects, applicable)
	return result


## GOAPPlanner is stateless per plan: create_plan()/validate_plan() take a
## world_state and return/check a plan without caching one on the planner -
## GoapCycle owns "the current plan" (Ticket 20). There is nothing here to
## reset; this method exists so the planner's documented API
## (create_plan/cancel_plan/validate_plan) is safe to call unconditionally
## on every role change.
func cancel_plan() -> void:
	pass


func validate_plan(plan: Array, world_state: WorldState) -> bool:
	if plan.is_empty():
		return false
	var state := world_state.clone()
	for action_name in plan:
		var action := _get_action_by_name(action_name)
		if action.is_empty():
			return false
		if not GoapUtils.state_satisfies(state, action.get("preconditions", {})):
			return false
		state = GoapUtils.merge_states(state, action.get("effects", {}))
	return true


func _forward_search(start_state: WorldState, goal_state: Dictionary, all_actions: Array) -> Array:
	var open: Array = []
	var visited: Dictionary = {}

	var start_node := {
		"state": start_state.clone(),
		"plan": [],
		"cost": 0.0
	}
	open.append(start_node)

	while not open.size() == 0:
		open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["cost"] < b["cost"])
		var current: Dictionary = open.pop_front()

		if GoapUtils.state_satisfies(current["state"], goal_state):
			return current["plan"]

		var state_key := _state_to_key(current["state"])
		if visited.has(state_key):
			continue
		visited[state_key] = true

		if current["plan"].size() >= _max_depth:
			continue

		for action in all_actions:
			var preconds: Dictionary = action.get("preconditions", {})
			if not GoapUtils.state_satisfies(current["state"], preconds):
				continue

			var effects: Dictionary = action.get("effects", {})
			var new_state: WorldState = GoapUtils.merge_states(current["state"], effects)
			var new_state_key := _state_to_key(new_state)
			if visited.has(new_state_key):
				continue

			var causes_contradiction := false
			for key in goal_state:
				if goal_state[key] == true and effects.has(key) and effects[key] == false:
					if not preconds.has(key):
						causes_contradiction = true
						break
			if causes_contradiction:
				continue

			var new_plan: Array = current["plan"].duplicate()
			new_plan.append(action["name"])
			var new_cost: float = current["cost"] + action.get("cost", 1.0)
			open.append({"state": new_state, "plan": new_plan, "cost": new_cost})

	return []


## Filters by role permission only - NOT by whether the action's precondition
## already holds in world_state. _forward_search re-checks preconditions at
## every node it expands, which is where that gating belongs: a precondition
## can become true mid-plan (e.g. ReportResource's at_nest, true only after
## GoTo[Nest] runs), so pre-filtering against the start state would drop
## such actions from the pool before the search ever gets a chance to chain
## into them.
##
## Universal Capabilities (UniversalCapabilities) bypass allowed_actions
## entirely, regardless of whether that list is empty or populated - a role
## missing GoTo could satisfy zero location-based preconditions, ever, so it
## must be reachable even when a role's own list doesn't (and, per ADR 8,
## never should) name it. This is layered independently of allowed_actions'
## own empty-means-unrestricted fallback below, which stays untouched here
## (Ticket 1's landmine note; fixing that half is Ticket 8's job).
func _get_applicable_actions(_world_state: WorldState, allowed_actions: Array) -> Array:
	var result: Array = []
	for action in _actions:
		var name: String = action["name"]
		if UniversalCapabilities.is_universal_action(name):
			result.append(action)
			continue
		if not allowed_actions.is_empty():
			if not name in allowed_actions:
				continue
		result.append(action)
	return result


func _get_action_by_name(action_name: String) -> Dictionary:
	for action in _actions:
		if action["name"] == action_name:
			return action
	return {}


func _state_to_key(state: WorldState) -> String:
	var keys := state.get_field_keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s=%s" % [key, state.get_field(key)])
	return "|".join(parts)


func _load_configs() -> void:
	var actions: Array = ConfigLoader.load_array("res://configs/actions/actions.json")
	_actions.clear()
	for item in actions:
		_actions.append(item as Dictionary)

	for goto_action in GotoGrounding.build_actions(_load_resource_kinds(), WorldState.new().get_field_keys()):
		_actions.append(goto_action)

	var goals: Array = ConfigLoader.load_array("res://configs/goals/goals.json")
	_goals.clear()
	for item in goals:
		_goals.append(item as Dictionary)


## GoTo's destination kinds are never hand-listed (ADR 8): the Nest plus
## every kind already declared in the resource registry, so adding a
## resource kind there alone is enough to make GoTo path to it (once
## WorldState grows the matching Sensed Fact - see GotoGrounding).
func _load_resource_kinds() -> Array:
	var entries: Array = ConfigLoader.load_array("res://configs/resources.json")
	var kinds: Array = []
	for entry in entries:
		if entry.has("type"):
			kinds.append(entry["type"])
	return kinds
