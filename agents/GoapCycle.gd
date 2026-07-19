extends Node

## Owns the GOAP planning/replanning loop: ticks the planning timer, asks
## GOAPGoalSelector for a goal, GOAPPlanner for a plan, and drives execution
## action-by-action through GoapActionExecutor. World-state assembly stays on
## agent.gd (it reaches into fields unrelated to GoapActionExecutor's
## IAgentActions seam) and is supplied here as a Callable rather than widening
## that interface for a single caller.

## Passive idle recovery for Unassigned agents, distinct from the Rest
## action's instant +40.0 restore.
const ENERGY_RECOVERY_RATE: float = 5.0

var current_goal: String = ""
var current_plan: Array = []

var _agent: IAgentActions = null
var _planner: Node = null
var _goal_selector: Node = null
var _role_component: Node = null
var _role_acquisition: Node = null
var _navigator: Node = null
var _build_world_state: Callable
var _planning_interval: float = 2.0
var _planning_timer: float = 0.0
var _action_index: int = 0
var _action_in_progress: bool = false


func setup(
	agent: IAgentActions,
	planner: Node,
	goal_selector: Node,
	role_component: Node,
	role_acquisition: Node,
	navigator: Node,
	build_world_state: Callable,
	planning_interval: float
) -> void:
	_agent = agent
	_planner = planner
	_goal_selector = goal_selector
	_role_component = role_component
	_role_acquisition = role_acquisition
	_navigator = navigator
	_build_world_state = build_world_state
	_planning_interval = planning_interval


func process(delta: float) -> void:
	_planning_timer -= delta
	if _planning_timer <= 0.0:
		_planning_timer = _planning_interval
		run_planning_cycle()


func run_planning_cycle() -> void:
	if _action_in_progress:
		return

	_role_acquisition.check_and_acquire_role()

	if _role_component.get_role_name() == "Unassigned":
		_navigator.stop()
		_agent.restore_energy(_planning_interval * ENERGY_RECOVERY_RATE)
		current_goal = ""
		current_plan = []
		return

	var world_state: WorldState = _build_world_state.call()
	var goal: Dictionary = _goal_selector.select_goal(world_state)

	if goal.is_empty():
		current_goal = ""
		current_plan = []
		return

	var goal_name: String = goal["name"]
	if goal_name == current_goal and current_plan.size() > 0 and _action_index < current_plan.size():
		return

	current_goal = goal_name
	current_plan = _planner.create_plan(goal_name, world_state)
	_action_index = 0

	if current_plan.size() > 0:
		if _planner.validate_plan(current_plan, world_state):
			_execute_current_action()
		else:
			current_plan = _planner.create_plan(goal_name, world_state)
			if current_plan.size() > 0 and _planner.validate_plan(current_plan, world_state):
				_execute_current_action()
			else:
				current_goal = ""
				current_plan = []
	else:
		current_goal = ""
		current_plan = []


## Public accessor so callers (e.g. the debugger UI) can read the action
## actually executing without reaching into _action_in_progress/_action_index.
func get_executing_action() -> String:
	if _action_in_progress and _action_index < current_plan.size():
		return current_plan[_action_index]
	return ""


func on_action_completed() -> void:
	var completed_action: String = current_plan[_action_index] if _action_index < current_plan.size() else ""
	_action_in_progress = false

	_role_acquisition.check_and_acquire_role()

	# check_and_acquire_role() can synchronously trigger a role change (if a
	# request was available), which drops the in-flight plan via
	# on_role_changed() before we get here. That plan is already gone and the
	# role it belonged to no longer applies, so there's nothing of
	# completed_action's left to verify or replan for.
	if current_plan.is_empty():
		return

	var world_state: WorldState = _build_world_state.call()

	if not _verify_completed_action(completed_action, world_state):
		_handle_action_failure(completed_action)
		return

	_action_index += 1

	if _action_index >= current_plan.size():
		current_plan = []
		current_goal = ""
		return

	var remaining_plan: Array = current_plan.slice(_action_index)
	if not _planner.validate_plan(remaining_plan, world_state):
		current_plan = []
		current_goal = ""
		run_planning_cycle()
		return

	_execute_current_action()


## ADR 6: after any action reports itself done, its own declared effect must
## genuinely hold in freshly-rebuilt world state - the same state_satisfies
## check the Planner already uses for plan validity. Detection is uniform
## across every action; no action handler carries its own success/failure
## logic, and this also retires Navigator's timeout-vs-arrival ambiguity for
## GoTo as a non-issue - whichever happened, this checks the actual
## resulting state either way.
func _verify_completed_action(action_name: String, world_state: WorldState) -> bool:
	if action_name.is_empty():
		return true
	var action: Dictionary = _planner.get_action_by_name(action_name)
	if action.is_empty():
		return true
	return world_state.satisfies(action.get("effects", {}))


## ADR 6: only a Pickup failure is direct evidence the resource is gone (the
## agent was physically at the position; extraction yielded nothing), so only
## a failed Pickup files a Depletion Report. Every other Action Failure -
## GoTo included, whether from a genuine navigation timeout or from arriving
## to find the target already gone - is weaker evidence and just falls
## through to the same ordinary replanning an invalid remaining plan already
## triggers above.
func _handle_action_failure(action_name: String) -> void:
	var resource_type := _pickup_resource_type(action_name)
	if not resource_type.is_empty():
		_agent.record_failed_report(resource_type, _agent.global_position)

	# Deliberately does NOT call run_planning_cycle() here: every action in
	# this system can complete instantly (Eat, Rest, Pickup*, Deposit,
	# Report*) via a signal chain with no frame boundary of its own, so a
	# re-selected plan whose single action fails its effect check every time
	# (e.g. a still-unresolved goal/action modeling issue keeps producing the
	# same bad plan) would recurse through this exact call chain with
	# nothing to stop it. Clearing the plan/goal and leaving _planning_timer
	# untouched defers the retry to process()'s next ordinary tick - the same
	# cadence every other "nothing to do right now" case in this cycle
	# already uses, and a real frame boundary a synchronous call is not.
	current_plan = []
	current_goal = ""


func _pickup_resource_type(action_name: String) -> String:
	if action_name == GoapActions.PICKUP_FOOD:
		return "Food"
	if action_name == GoapActions.PICKUP_WOOD:
		return "Wood"
	return ""


## Called from agent.gd's role_changed handler - drops the in-flight plan
## immediately so a stale action never executes under the new role.
func on_role_changed() -> void:
	current_goal = ""
	current_plan = []
	_action_index = 0
	_action_in_progress = false
	_planner.cancel_plan()


func _execute_current_action() -> void:
	if _action_index >= current_plan.size():
		current_plan = []
		current_goal = ""
		_action_in_progress = false
		return

	var action_name: String = current_plan[_action_index]
	_action_in_progress = true
	GoapActionExecutor.execute_action(action_name, _agent)
