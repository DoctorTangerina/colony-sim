extends Node

var _goals: Array = []
var _planner = null
var _role_component: Node = null


func _ready() -> void:
	pass


func initialize(planner) -> void:
	_planner = planner
	_goals = planner.get_goals()


func set_role_component(component: Node) -> void:
	_role_component = component


func get_role_component() -> Node:
	return _role_component


func select_goal(world_state: Dictionary) -> Dictionary:
	var candidates := _get_achievable_goals(world_state)
	if candidates.is_empty():
		return {}

	var best: Dictionary = candidates[0]
	var best_score: float = -1.0
	for goal in candidates:
		var score := _score_goal(goal, world_state)
		if score > best_score:
			best_score = score
			best = goal
	return best


func get_available_goals(world_state: Dictionary) -> Array[Dictionary]:
	return _get_achievable_goals(world_state)


func _get_achievable_goals(world_state: Dictionary) -> Array[Dictionary]:
	var allowed_goals: Array = []
	if _role_component and _role_component.has_method("get_allowed_goals"):
		allowed_goals = _role_component.get_allowed_goals()

	var result: Array[Dictionary] = []
	for goal in _goals:
		if not allowed_goals.is_empty():
			if not goal["name"] in allowed_goals:
				continue
		elif _role_component and _role_component.has_method("get_role_name"):
			if _role_component.get_role_name() == "Unassigned":
				continue
		var preconds: Dictionary = goal.get("preconditions", {})
		if GoapUtils.state_satisfies(world_state, preconds):
			var allowed_actions: Array = []
			if _role_component and _role_component.has_method("get_allowed_actions"):
				allowed_actions = _role_component.get_allowed_actions()
			var plan = _planner.create_plan(goal["name"], world_state, allowed_actions)
			if not plan.is_empty():
				result.append(goal)
	return result


func _score_goal(goal: Dictionary, _world_state: Dictionary) -> float:
	var base_desirability: float = goal.get("desirability", 1.0)
	var modifier := 1.0
	if _role_component and _role_component.has_method("get_priority_modifier"):
		modifier = _role_component.get_priority_modifier(goal["name"])

	return base_desirability * modifier
