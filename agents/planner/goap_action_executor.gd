class_name GoapActionExecutor
extends Node

## Actions not present here fall through to _default_handler, which just
## completes the action. Register an entry only when an action needs bespoke
## behavior - most new actions need none, keeping executor edits off the
## "adding an action" checklist entirely.
static var _registry: Dictionary = {}


static func execute_action(action_name: String, agent: IAgentActions) -> void:
	if action_name.begins_with(GoapActions.GOTO + "["):
		_goto(action_name, agent)
		return
	if action_name.begins_with(GoapActions.GET_RESOURCE + "["):
		_get_resource(action_name, agent)
		return
	_ensure_registry()
	var handler: Callable = _registry.get(action_name, _default_handler)
	handler.call(agent)


static func _ensure_registry() -> void:
	if not _registry.is_empty():
		return
	_registry[GoapActions.EAT] = _eat
	_registry[GoapActions.REST] = _rest
	_registry[GoapActions.PICKUP_FOOD] = _pickup_food
	_registry[GoapActions.PICKUP_WOOD] = _pickup_wood
	_registry[GoapActions.DEPOSIT_RESOURCE] = _deposit_resource
	_registry[GoapActions.RANDOM_EXPLORE] = _explore
	_registry[GoapActions.REPORT_RESOURCE] = _report_resource
	_registry[GoapActions.REPORT_DEPLETION] = _report_depletion
	_registry[GoapActions.IDLE] = _idle


static func _default_handler(agent: IAgentActions) -> void:
	agent.complete_action()


static func _eat(agent: IAgentActions) -> void:
	agent.reset_hunger()
	agent.complete_action()


## Async/held (SPEC.md Ticket 02, first besides GoTo): starts the continuous
## regen trickle rather than completing synchronously. The agent itself calls
## complete_action() once energy tops out at 100 (agent._process_resting).
static func _rest(agent: IAgentActions) -> void:
	agent.start_resting()


## Passive fallback recovery (CONTEXT.md: Idle) - a smaller restore than
## Rest's instant 40.0, matching the old hardcoded Unassigned recovery this
## generalizes (Ticket 6). Never moves the agent.
static func _idle(agent: IAgentActions) -> void:
	agent.restore_energy(10.0)
	agent.complete_action()


static func _pickup_food(agent: IAgentActions) -> void:
	agent.attempt_pickup("Food")
	agent.complete_action()


static func _pickup_wood(agent: IAgentActions) -> void:
	agent.attempt_pickup("Wood")
	agent.complete_action()


static func _deposit_resource(agent: IAgentActions) -> void:
	agent.deposit_at_nest(agent.get_held_item())
	agent.complete_action()


## Dispatches a grounded "GoTo[Kind]" plan step (GotoGrounding). The concrete
## instance is chosen here, once, at execution start - not re-picked mid-walk
## (Session 3's frozen-target decision; Navigator just walks to whatever
## move_to() was last called with).
static func _goto(action_name: String, agent: IAgentActions) -> void:
	var kind := action_name.trim_prefix(GoapActions.GOTO + "[").trim_suffix("]")
	if kind == GotoGrounding.NEST_KIND:
		agent.move_to(agent.get_nest_position())
		return
	var known_positions: Dictionary = agent.get_known_positions()
	if known_positions.has(kind) and known_positions[kind].size() > 0:
		agent.move_to(known_positions[kind][0])
		return
	agent.complete_action()


## Target selection (Explored-Trail-biased, ADR 9) lives behind
## pick_explore_target() - this handler only dispatches the walk, same as
## every other GoTo-shaped action.
static func _explore(agent: IAgentActions) -> void:
	agent.move_to(agent.pick_explore_target())


## Dispatches a grounded "GetResource[Kind]" plan step (GetResourceGrounding;
## SPEC.md Ticket 03), mirroring _goto's shape. Withdrawal against empty Nest
## stock is an honest no-op (agent.attempt_withdraw), surfaced through the
## ordinary Action Failure / verify-by-effect path rather than a bespoke
## success/failure check here.
static func _get_resource(action_name: String, agent: IAgentActions) -> void:
	var kind := action_name.trim_prefix(GoapActions.GET_RESOURCE + "[").trim_suffix("]")
	agent.attempt_withdraw(kind)
	agent.complete_action()


## Left untyped/untouched: writes directly to the Blackboard node rather than
## going through IAgentActions, since ReportResource is the sole write path
## and narrowing it would just relocate the same two has_method() checks.
static func _report_resource(agent) -> void:
	var res_type: String = agent.get("discovered_resource_type")
	var res_pos: Vector2 = agent.get("discovered_resource_pos")

	if res_type.is_empty() or not agent.nest_ref:
		agent.clear_discovered_resource()
		agent.complete_action()
		return

	var blackboard = null
	if agent.nest_ref.has_method("get_blackboard"):
		blackboard = agent.nest_ref.get_blackboard()

	if blackboard and blackboard.has_method("add_entry"):
		blackboard.add_entry(res_type, res_pos)

	agent.clear_discovered_resource()
	agent.complete_action()


## Mirrors _report_resource's Nest-only write path (ADR 6): removes the
## carried failed_resource_type/pos entry from the Blackboard once at_nest,
## rather than the field ever writing to it directly. remove_entries is a
## no-op when nothing matches, so a second agent's report for an
## already-removed entry is a safe no-op, not a special case to guard against.
static func _report_depletion(agent) -> void:
	var res_type: String = agent.get("failed_resource_type")
	var res_pos: Vector2 = agent.get("failed_resource_pos")

	if res_type.is_empty() or not agent.nest_ref:
		agent.clear_failed_report()
		agent.complete_action()
		return

	var blackboard = null
	if agent.nest_ref.has_method("get_blackboard"):
		blackboard = agent.nest_ref.get_blackboard()

	if blackboard and blackboard.has_method("remove_entries"):
		blackboard.remove_entries(res_type, res_pos)

	agent.clear_failed_report()
	agent.complete_action()
