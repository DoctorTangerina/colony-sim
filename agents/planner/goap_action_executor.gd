class_name GoapActionExecutor
extends Node


static func execute_action(action_name: String, agent) -> void:
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


static func _pickup_resource(resource_type: String, agent) -> void:
	var node: Node = agent.get_nearest_resource(agent.get_agent_position(), resource_type)
	if node and is_instance_valid(node):
		agent.set_target_resource(node)
		agent.move_to(node.global_position)
		return
	var known_key: String = "known_%s_positions" % resource_type.to_lower()
	var known_positions = agent.get(known_key)
	if known_positions is Dictionary and known_positions.has(resource_type) and known_positions[resource_type].size() > 0:
		var target_pos: Vector2 = known_positions[resource_type][0]
		var rm = agent.get("resource_manager_ref")
		if rm and rm.has_method("resource_exists_at") and rm.resource_exists_at(resource_type, target_pos):
			var mock_node = GDScript.new()
			mock_node.source_code = """extends Node
var resource_type: String = ""
var global_position: Vector2 = Vector2.ZERO
var remaining_amount: int = 100
func extract(amount: int) -> int:
	var actual = mini(amount, remaining_amount)
	remaining_amount -= actual
	return actual
"""
			mock_node.reload()
			var resource_node = mock_node.new()
			resource_node.set("resource_type", resource_type)
			resource_node.set("global_position", target_pos)
			agent.set_target_resource(resource_node)
			agent.move_to(target_pos)
			return
	agent.complete_action()


static func _move_to_best_target(agent) -> void:
	var known_food = agent.get("known_food_positions")
	var known_wood = agent.get("known_wood_positions")

	if known_food is Dictionary and known_food.has("Food") and known_food["Food"].size() > 0:
		agent.move_to(known_food["Food"][0])
		return
	if known_wood is Dictionary and known_wood.has("Wood") and known_wood["Wood"].size() > 0:
		agent.move_to(known_wood["Wood"][0])
		return
	agent.move_to(agent.get_nest_position())


static func _explore(agent) -> void:
	var bounds: Rect2 = agent.get_world_bounds()
	var random_pos := Vector2(
		randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
		randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
	)
	agent.move_to(random_pos)


static func _patrol(agent) -> void:
	var nest_pos: Vector2 = agent.get_nest_position()
	if nest_pos != Vector2.ZERO:
		var offset := Vector2(randf_range(-80.0, 80.0), randf_range(-80.0, 80.0))
		agent.move_to(nest_pos + offset)
	else:
		agent.complete_action()


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
