extends Node

## Owns the GOAP planning/replanning loop: ticks the planning timer, asks
## GOAPGoalSelector for a goal, GOAPPlanner for a plan, and drives execution
## action-by-action through GoapActionExecutor. World-state assembly stays on
## agent.gd (it reaches into fields unrelated to GoapActionExecutor's
## IAgentActions seam) and is supplied here as a Callable rather than widening
## that interface for a single caller.

var current_goal: String = ""
var current_plan: Array = []

var _agent: IAgentActions = null
var _planner: Node = null
var _goal_selector: Node = null
var _role_acquisition: Node = null
var _build_world_state: Callable
var _planning_interval: float = 2.0
var _switch_margin: float = 0.0
var _planning_timer: float = 0.0
var _action_index: int = 0
var _action_in_progress: bool = false
var _energy_drain_per_action: float = 5.0
var _synchronous_replan_depth: int = 0

## Actions whose completion never costs energy (SPEC.md Ticket 02) - Eat/Rest
## exist to restore energy/hunger, and Idle is the passive-recovery fallback;
## draining any of them would partially undercut what they exist to restore.
const _ENERGY_DRAIN_EXEMPT: Array = [GoapActions.EAT, GoapActions.REST, GoapActions.IDLE]

## Backstop against a same-frame oscillating action pair (see
## on_action_completed's "clean finish, replan immediately" branch) hanging
## the frame - generous enough to never trip on a legitimate deep chain of
## distinct successful actions.
const _MAX_SYNCHRONOUS_REPLAN_DEPTH: int = 50


func setup(
	agent: IAgentActions,
	planner: Node,
	goal_selector: Node,
	role_acquisition: Node,
	build_world_state: Callable,
	planning_interval: float,
	switch_margin: float = 0.0,
	energy_drain_per_action: float = 5.0
) -> void:
	_agent = agent
	_planner = planner
	_goal_selector = goal_selector
	_role_acquisition = role_acquisition
	_build_world_state = build_world_state
	_planning_interval = planning_interval
	_switch_margin = switch_margin
	_energy_drain_per_action = energy_drain_per_action


func process(delta: float) -> void:
	_planning_timer -= delta
	if _planning_timer <= 0.0:
		_planning_timer = _planning_interval
		run_planning_cycle()


## ADR 7: runs every planning tick regardless of what the agent is doing -
## no _action_in_progress no-op guard - since abandoning a GoTo is nearly
## free (Navigator just retargets from the current position on the next
## _execute_current_action() call). Goal Commitment/Switch Margin (passed to
## select_goal as current_goal/_switch_margin) is what keeps this from
## thrashing: a challenger goal only ever reaches the reassignment below by
## actually clearing the margin or by current_goal no longer being
## achievable, so an in-progress GoTo's concrete grounded destination is
## never touched by a tick that merely re-confirms the same goal or fails to
## unseat it - the existing goal_name == current_goal early-return below
## covers both cases identically to before Ticket 9.
func run_planning_cycle() -> void:
	_role_acquisition.check_and_acquire_role()

	var world_state: WorldState = _build_world_state.call()
	var goal: Dictionary = _goal_selector.select_goal(world_state, current_goal, _switch_margin)

	if goal.is_empty():
		current_goal = ""
		current_plan = []
		return

	var goal_name: String = goal["name"]
	if goal_name == current_goal and current_plan.size() > 0 and _action_index < current_plan.size():
		return

	# A genuine goal switch (not a mere reconfirmation, filtered out above)
	# that leaves a committed Rest must cut the regen trickle before the new
	# plan dispatches (SPEC.md Ticket 02) - the other interrupt site is
	# on_role_changed() below, for a role change firing mid-Rest.
	if current_goal == GoapActions.REST:
		_agent.stop_resting()

	# goal["plan"] is the same plan GOAPGoalSelector already produced (and
	# proved valid) while checking this goal's achievability this tick, on
	# this same world_state - reusing it here (defect #8) instead of asking
	# GOAPPlanner to search again is not an approximation, since nothing
	# mutates world_state and nothing awaits between that check and here.
	current_goal = goal_name
	current_plan = goal.get("plan", [])
	_action_index = 0

	if current_plan.size() > 0:
		_execute_current_action()
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

	# Flat upkeep cost (SPEC.md Ticket 02), applied before the verify-by-effect
	# check below regardless of its outcome - this is the one place that
	# already knows the completed action's name.
	if not completed_action.is_empty() and not completed_action in _ENERGY_DRAIN_EXEMPT:
		_agent.drain_energy(_energy_drain_per_action)

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

	# ADR 12: Action Verified (CONTEXT.md) - purely additive observability,
	# announced only after the effect-satisfaction check above already
	# passed. Generic on purpose: this doesn't know or care what a listener
	# (e.g. MetricsLogger) considers "productive."
	if not completed_action.is_empty():
		_agent.notify_action_verified(completed_action)

	_action_index += 1

	# ADR 7: a plan that finishes cleanly replans immediately rather than
	# idling until the next planningInterval tick - same treatment as the
	# "remaining plan invalid" branch below, which already does this. Usually
	# bounded on its own: each hop only follows a *successful* state change,
	# and a goal requiring travel (GoTo has no synchronous completion) or Idle
	# (whose completion is always an Action Failure by construction - Ticket
	# 6) breaks the chain within a few hops in the worst case. That's not a
	# guarantee, though - two actions that are exact inverses (e.g. a
	# same-frame withdraw-then-deposit pair) can oscillate through this path
	# forever with no travel leg to stop at, which is exactly what happened
	# before GetResource[Kind] was gated on high_hunger (see
	# GetResourceGrounding). _synchronous_replan_depth is the backstop for
	# the next config combination nobody anticipated: past the cap, drop back
	# to the ordinary throttled cadence instead of hanging the frame.
	if _action_index >= current_plan.size():
		current_plan = []
		current_goal = ""
		_synchronous_replan_depth += 1
		if _synchronous_replan_depth > _MAX_SYNCHRONOUS_REPLAN_DEPTH:
			push_error("GoapCycle: %s exceeded %s synchronous replans in a row (last action %s) - likely an oscillating action pair; deferring to next planning tick" % [_agent.get("agent_id"), _MAX_SYNCHRONOUS_REPLAN_DEPTH, completed_action])
			_synchronous_replan_depth = 0
			return
		run_planning_cycle()
		_synchronous_replan_depth = 0
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
	#
	# GetFood is the one exception to clearing current_goal too: goal_selector's
	# sticky commitment (_sticky_get_food) only ever gets a chance to fire when
	# current_goal_name arrives non-empty, so wiping it here on an honest
	# "pantry was empty" miss would silently drop the retry - the same
	# giving-up-on-survival gap the sticky commitment exists to close.
	current_plan = []
	if current_goal != "GetFood":
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
	if current_goal == GoapActions.REST:
		_agent.stop_resting()
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
