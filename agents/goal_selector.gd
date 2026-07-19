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


func select_goal(world_state: WorldState) -> Dictionary:
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


func get_available_goals(world_state: WorldState) -> Array[Dictionary]:
	return _get_achievable_goals(world_state)


## Keeps the plan computed while checking achievability (attached under a
## "plan" key on a duplicate of the goal dict, additive so goal.get("name",
## ...)-style access elsewhere stays unmodified) instead of discarding it -
## GoapCycle.run_planning_cycle() reuses it directly rather than recomputing
## an identical search a tick later (defect #8). Valid only because
## world_state isn't mutated and nothing awaits between this call and that
## reuse within the same planning tick.
func _get_achievable_goals(world_state: WorldState) -> Array[Dictionary]:
	var allowed_goals: Array = []
	if _role_component and _role_component.has_method("get_allowed_goals"):
		allowed_goals = _role_component.get_allowed_goals()

	var allowed_actions: Array = []
	if _role_component and _role_component.has_method("get_allowed_actions"):
		allowed_actions = _role_component.get_allowed_actions()

	var result: Array[Dictionary] = []
	for goal in _goals:
		var goal_name: String = goal["name"]
		if not UniversalCapabilities.is_universal_goal(goal_name) and not goal_name in allowed_goals:
			continue
		var preconds: Dictionary = goal.get("preconditions", {})
		if GoapUtils.state_satisfies(world_state, preconds):
			var plan = _planner.create_plan(goal_name, world_state, allowed_actions)
			if not plan.is_empty():
				var goal_with_plan: Dictionary = goal.duplicate()
				goal_with_plan["plan"] = plan
				result.append(goal_with_plan)
	return result


func _score_goal(goal: Dictionary, _world_state: WorldState) -> float:
	var base_desirability: float = goal.get("desirability", 1.0)
	var modifier := 1.0
	if _role_component and _role_component.has_method("get_priority_modifier"):
		modifier = _role_component.get_priority_modifier(goal["name"])

	return base_desirability * modifier
