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


## Goal Commitment / Switch Margin (ADR 7, CONTEXT.md): under full reactivity
## every achievable goal is re-scored every planning tick, even mid-walk, so
## a bare "always take the best scorer" would thrash between closely-scored
## or intermittently-achievable goals. current_goal_name is the goal the
## caller is already committed to; a challenger only pre-empts it by scoring
## more than switch_margin above it. If current_goal_name is empty or no
## longer among this tick's achievable candidates (its own precondition/
## effects state moved on), there is nothing to commit to and the top
## scorer wins outright, same as the no-margin default (switch_margin's
## default of 0.0 combined with an empty current_goal_name reproduces the
## pre-ADR-7 behavior exactly, so existing no-arg callers are unaffected).
func select_goal(world_state: WorldState, current_goal_name: String = "", switch_margin: float = 0.0) -> Dictionary:
	var candidates := _get_achievable_goals(world_state)
	if candidates.is_empty():
		return {}

	var best: Dictionary = candidates[0]
	var best_score: float = -1.0
	var current_entry: Dictionary = {}
	var current_score: float = -1.0
	for goal in candidates:
		var score := _score_goal(goal, world_state)
		if score > best_score:
			best_score = score
			best = goal
		if goal["name"] == current_goal_name:
			current_entry = goal
			current_score = score

	if current_entry.is_empty() and not current_goal_name.is_empty():
		current_entry = _relevant_but_already_satisfied(current_goal_name, world_state)
		if not current_entry.is_empty():
			current_score = _score_goal(current_entry, world_state)

	if current_goal_name.is_empty() or current_entry.is_empty() or best["name"] == current_goal_name:
		return best

	if best_score > current_score + switch_margin:
		return best

	return current_entry


func get_available_goals(world_state: WorldState) -> Array[Dictionary]:
	return _get_achievable_goals(world_state)


## Goal Commitment (CONTEXT.md) needs the currently-active goal to stay in
## the Switch Margin comparison even once its own declared effect has come to
## hold on its own - true for Rest specifically (SPEC.md Ticket 02), whose
## effect (energy_critical: false) clears via continuous regen mid-execution,
## independent of and before the async Rest action itself finishes.
## _get_achievable_goals excludes it there (create_plan's ordinary already-
## satisfied shortcut, correct for every synchronous goal/action pair, where
## an effect can only become true once its own action actually runs) - this
## only restores it to the comparison, using relevance (preconditions still
## hold, same role/universal gating as any candidate) rather than fresh
## achievability, since no new plan is needed: GoapCycle's own
## goal_name == current_goal early-return keeps running the existing one.
func _relevant_but_already_satisfied(goal_name: String, world_state: WorldState) -> Dictionary:
	var goal: Dictionary = _planner.get_goal_by_name(goal_name)
	if goal.is_empty():
		return {}
	if not _goal_is_permitted(goal_name):
		return {}
	if not GoapUtils.state_satisfies(world_state, goal.get("preconditions", {})):
		return {}
	return goal


func _goal_is_permitted(goal_name: String) -> bool:
	if UniversalCapabilities.is_universal_goal(goal_name):
		return true
	var allowed_goals: Array = []
	if _role_component and _role_component.has_method("get_allowed_goals"):
		allowed_goals = _role_component.get_allowed_goals()
	return goal_name in allowed_goals


## Keeps the plan computed while checking achievability (attached under a
## "plan" key on a duplicate of the goal dict, additive so goal.get("name",
## ...)-style access elsewhere stays unmodified) instead of discarding it -
## GoapCycle.run_planning_cycle() reuses it directly rather than recomputing
## an identical search a tick later (defect #8). Valid only because
## world_state isn't mutated and nothing awaits between this call and that
## reuse within the same planning tick.
func _get_achievable_goals(world_state: WorldState) -> Array[Dictionary]:
	var allowed_actions: Array = []
	if _role_component and _role_component.has_method("get_allowed_actions"):
		allowed_actions = _role_component.get_allowed_actions()

	var result: Array[Dictionary] = []
	for goal in _goals:
		var goal_name: String = goal["name"]
		if not _goal_is_permitted(goal_name):
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
