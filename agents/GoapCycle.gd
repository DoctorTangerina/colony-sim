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


func on_action_completed() -> void:
	_role_acquisition.check_and_acquire_role()

	_action_in_progress = false
	_action_index += 1

	if _action_index >= current_plan.size():
		current_plan = []
		current_goal = ""
		return

	var remaining_plan: Array = current_plan.slice(_action_index)
	if not _planner.validate_plan(remaining_plan, _build_world_state.call()):
		current_plan = []
		current_goal = ""
		run_planning_cycle()
		return

	_execute_current_action()


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
