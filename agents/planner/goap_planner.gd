extends Node

var _actions: Array[Dictionary] = []
var _goals: Array[Dictionary] = []
var _max_depth: int = 20


func _ready() -> void:
	_load_configs()


func set_actions(actions: Array[Dictionary]) -> void:
	_actions = actions


func set_goals(goals: Array[Dictionary]) -> void:
	_goals = goals


func get_actions() -> Array[Dictionary]:
	return _actions


func get_goals() -> Array[Dictionary]:
	return _goals


func get_goal_by_name(goal_name: String) -> Dictionary:
	for goal in _goals:
		if goal["name"] == goal_name:
			return goal
	return {}


func create_plan(goal_name: String, world_state: Dictionary, allowed_actions: Array = []) -> Array:
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


func cancel_plan() -> void:
	pass


func validate_plan(plan: Array, world_state: Dictionary) -> bool:
	if plan.is_empty():
		return false
	var state := world_state.duplicate()
	for action_name in plan:
		var action := _get_action_by_name(action_name)
		if action.is_empty():
			return false
		if not GoapUtils.state_satisfies(state, action.get("preconditions", {})):
			return false
		state = GoapUtils.merge_states(state, action.get("effects", {}))
	return true


func _forward_search(start_state: Dictionary, goal_state: Dictionary, all_actions: Array[Dictionary]) -> Array:
	var open: Array = []
	var visited: Dictionary = {}

	var start_node := {
		"state": start_state.duplicate(),
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
			var new_state: Dictionary = GoapUtils.merge_states(current["state"], effects)
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


func _get_applicable_actions(world_state: Dictionary, allowed_actions: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action in _actions:
		if not allowed_actions.is_empty():
			if not action["name"] in allowed_actions:
				continue
		var preconds: Dictionary = action.get("preconditions", {})
		if GoapUtils.state_satisfies(world_state, preconds):
			result.append(action)
	return result


func _get_action_by_name(action_name: String) -> Dictionary:
	for action in _actions:
		if action["name"] == action_name:
			return action
	return {}


func _state_to_key(state: Dictionary) -> String:
	var keys := state.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s=%s" % [key, state[key]])
	return "|".join(parts)


func _load_configs() -> void:
	var actions: Array = ConfigLoader.load_array("res://configs/actions/actions.json")
	_actions.clear()
	for item in actions:
		_actions.append(item as Dictionary)

	var goals: Array = ConfigLoader.load_array("res://configs/goals/goals.json")
	_goals.clear()
	for item in goals:
		_goals.append(item as Dictionary)
