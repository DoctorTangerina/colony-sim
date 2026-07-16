class_name GoapActionExecutor
extends Node


static func execute_action(action_name: String, agent: IAgentActions) -> void:
	match action_name:
		GoapActions.EAT:
			agent.reduce_hunger(40.0)
			agent.complete_action()
		GoapActions.REST:
			agent.restore_energy(40.0)
			agent.complete_action()
		GoapActions.RETURN_TO_NEST:
			agent.move_to(agent.get_nest_position())
		GoapActions.MOVE_TO:
			_move_to_best_target(agent)
		GoapActions.PICKUP_FOOD:
			_pickup_resource("Food", agent)
		GoapActions.PICKUP_WOOD:
			_pickup_resource("Wood", agent)
		GoapActions.DEPOSIT_RESOURCE:
			agent.deposit_at_nest(agent.get_held_item())
			agent.complete_action()
		GoapActions.RANDOM_EXPLORE:
			_explore(agent)
		GoapActions.PATROL_NEST:
			_patrol(agent)
		GoapActions.LAY_RETURN_PHEROMONE, GoapActions.LAY_RESOURCE_PHEROMONE, GoapActions.FOLLOW_PHEROMONE:
			agent.complete_action()
		GoapActions.REPORT_RESOURCE:
			_report_resource(agent)
		GoapActions.ATTACK_TARGET:
			agent.complete_action()
		_:
			agent.complete_action()


static func _pickup_resource(resource_type: String, agent: IAgentActions) -> void:
	var node: Node = agent.get_nearest_resource(agent.get_agent_position(), resource_type)
	if node and is_instance_valid(node):
		agent.set_target_resource(node)
		agent.move_to(node.global_position)
		return
	var known_positions: Dictionary = agent.get_known_positions()
	if known_positions.has(resource_type) and known_positions[resource_type].size() > 0:
		agent.move_to(known_positions[resource_type][0])
		return
	agent.complete_action()


static func _move_to_best_target(agent: IAgentActions) -> void:
	var known_positions: Dictionary = agent.get_known_positions()

	if known_positions.has("Food") and known_positions["Food"].size() > 0:
		agent.move_to(known_positions["Food"][0])
		return
	if known_positions.has("Wood") and known_positions["Wood"].size() > 0:
		agent.move_to(known_positions["Wood"][0])
		return
	agent.move_to(agent.get_nest_position())


static func _explore(agent: IAgentActions) -> void:
	var bounds: Rect2 = agent.get_world_bounds()
	var random_pos := Vector2(
		randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
		randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
	)
	agent.move_to(random_pos)


static func _patrol(agent: IAgentActions) -> void:
	var nest_pos: Vector2 = agent.get_nest_position()
	if nest_pos != Vector2.ZERO:
		var offset := Vector2(randf_range(-80.0, 80.0), randf_range(-80.0, 80.0))
		agent.move_to(nest_pos + offset)
	else:
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
