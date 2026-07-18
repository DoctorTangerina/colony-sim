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


static func _default_handler(agent: IAgentActions) -> void:
	agent.complete_action()


static func _eat(agent: IAgentActions) -> void:
	agent.reduce_hunger(40.0)
	agent.complete_action()


static func _rest(agent: IAgentActions) -> void:
	agent.restore_energy(40.0)
	agent.complete_action()


static func _pickup_food(agent: IAgentActions) -> void:
	_pickup_resource("Food", agent)


static func _pickup_wood(agent: IAgentActions) -> void:
	_pickup_resource("Wood", agent)


static func _deposit_resource(agent: IAgentActions) -> void:
	agent.deposit_at_nest(agent.get_held_item())
	agent.complete_action()


static func _pickup_resource(resource_type: String, agent: IAgentActions) -> void:
	var agent_pos: Vector2 = agent.get_agent_position()
	var node: Node = agent.get_nearest_resource(agent_pos, resource_type)
	if node and is_instance_valid(node) and agent_pos.distance_to(node.global_position) < agent.get_discovery_radius():
		agent.set_target_resource(node)
		agent.move_to(node.global_position)
		return
	var known_positions: Dictionary = agent.get_known_positions()
	if known_positions.has(resource_type) and known_positions[resource_type].size() > 0:
		agent.move_to(known_positions[resource_type][0])
		return
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


static func _explore(agent: IAgentActions) -> void:
	var bounds: Rect2 = agent.get_world_bounds()
	var random_pos := Vector2(
		randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
		randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
	)
	agent.move_to(random_pos)


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
