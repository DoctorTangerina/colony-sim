extends CharacterBody2D

signal item_changed(new_item: String)
signal action_completed
signal role_changed(agent_id: String, old_role: String, new_role: String)

var agent_id: String
var energy: float = 100.0
var hunger: float = 0.0
var held_item: String = "None"
var current_goal: String = ""
var current_plan: Array = []
var target_resource: Node = null

var nest_ref: Node2D = null
var resource_manager_ref: Node = null

@onready var nav_agent: NavigationAgent2D = $NavAgent
@onready var _navigator: Node = $Navigator
@onready var _nest_zone: Node = $NestZone
@onready var _role_component: Node = $RoleComponent
@onready var _role_acquisition: Node = $RoleAcquisition
@onready var _planner: Node = $GOAPPlanner
@onready var _goal_selector: Node = $GOAPGoalSelector

var _action_index: int = 0
var _action_in_progress: bool = false
var _planning_interval: float = 2.0
var _planning_timer: float = 0.0
var _agent_speed: float = 200.0
var _discovery_radius: float = 50.0
var discovered_resource_type: String = ""
var discovered_resource_pos: Vector2 = Vector2.ZERO
var known_food_positions: Dictionary = {}
var known_wood_positions: Dictionary = {}

var _map_min: Vector2
var _map_max: Vector2


func _ready() -> void:
	if agent_id.is_empty():
		agent_id = str(get_instance_id())
	
	# Validate required child nodes
	if not nav_agent or not _navigator or not _nest_zone or not _role_component or not _role_acquisition or not _planner or not _goal_selector:
		push_error("Agent missing required child nodes: NavAgent, Navigator, NestZone, RoleComponent, RoleAcquisition, GOAPPlanner, GOAPGoalSelector")
		return
	
	_load_sim_config()
	_setup_modules()


func _load_sim_config() -> void:
	var data: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	_agent_speed = data.get("agentSpeed", 200.0)
	_planning_interval = data.get("planningInterval", 2.0)
	_discovery_radius = data.get("discoveryRadius", 50.0)
	if not data.has("mapMinX") or not data.has("mapMinY") or not data.has("mapMaxX") or not data.has("mapMaxY"):
		push_error("agent: simulation.json missing map bounds (mapMinX, mapMinY, mapMaxX, mapMaxY)")
		return
	_map_min = Vector2(data["mapMinX"], data["mapMinY"])
	_map_max = Vector2(data["mapMaxX"], data["mapMaxY"])


func _setup_modules() -> void:
	_navigator.setup(nav_agent, self, _agent_speed)
	_navigator.arrived.connect(_on_arrived_at_target)

	_goal_selector.initialize(_planner)
	_goal_selector.set_role_component(_role_component)

	_role_acquisition.role_changed.connect(_on_role_changed)

	action_completed.connect(_on_action_completed)


func setup(nest: Node2D, resource_manager: Node) -> void:
	nest_ref = nest
	resource_manager_ref = resource_manager
	_nest_zone.setup(nest_ref, self)
	var sim_config: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	var cooldown_duration: float = sim_config.get("roleCooldown", 10.0)
	_role_acquisition.setup(_get_om(), _role_component, _nest_zone, agent_id, cooldown_duration)


func _process(delta: float) -> void:
	_role_acquisition.process(delta)
	_navigator.process(delta)

	_planning_timer -= delta
	if _planning_timer <= 0.0:
		_planning_timer = _planning_interval
		_run_planning_cycle()


func _run_planning_cycle() -> void:
	if _action_in_progress:
		return

	_role_acquisition.check_and_acquire_role()

	var world_state := _build_world_state()
	var goal = _goal_selector.select_goal(world_state)

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


func _build_world_state() -> WorldState:
	var at_nest := false
	if nest_ref:
		var dist := global_position.distance_to(nest_ref.global_position)
		at_nest = dist < 50.0

	var food_visible := false
	var wood_visible := false
	var near_unreported := false

	if resource_manager_ref:
		var food_node = resource_manager_ref.get_nearest_resource(global_position, "Food")
		if food_node and is_instance_valid(food_node):
			food_visible = true
		var wood_node = resource_manager_ref.get_nearest_resource(global_position, "Wood")
		if wood_node and is_instance_valid(wood_node):
			wood_visible = true

		var blackboard = null
		if nest_ref and nest_ref.has_method("get_blackboard"):
			blackboard = nest_ref.get_blackboard()

		if blackboard and blackboard.has_method("has_entry_at"):
			for res_node in resource_manager_ref.get_all_resources():
				if is_instance_valid(res_node) and global_position.distance_to(res_node.global_position) < _discovery_radius:
					if not blackboard.has_entry_at(res_node.resource_type, res_node.global_position):
						near_unreported = true
						if discovered_resource_type.is_empty():
							discovered_resource_type = res_node.resource_type
							discovered_resource_pos = res_node.global_position
						break

		if blackboard and blackboard.has_method("get_entries"):
			known_food_positions = {}
			known_wood_positions = {}
			for res_type in ["Food", "Wood"]:
				var entries = blackboard.get_entries(res_type)
				for entry in entries:
					var entry_pos: Vector2 = entry["position"]
					if resource_manager_ref.resource_exists_at(res_type, entry_pos):
						if res_type == "Food":
							known_food_positions[res_type] = known_food_positions.get(res_type, [])
							known_food_positions[res_type].append(entry_pos)
						else:
							known_wood_positions[res_type] = known_wood_positions.get(res_type, [])
							known_wood_positions[res_type].append(entry_pos)

	var has_known_food: bool = not known_food_positions.is_empty()
	var has_known_wood: bool = not known_wood_positions.is_empty()

	return WorldState.build(held_item, energy, hunger, at_nest, food_visible, wood_visible, near_unreported, has_known_food, has_known_wood)


func _execute_current_action() -> void:
	if _action_index >= current_plan.size():
		current_plan = []
		current_goal = ""
		_action_in_progress = false
		return

	var action_name: String = current_plan[_action_index]
	_action_in_progress = true
	GoapActionExecutor.execute_action(action_name, self)


func _on_arrived_at_target() -> void:
	if target_resource and is_instance_valid(target_resource):
		var res: ResourceNode = target_resource as ResourceNode
		if res:
			var extracted := res.extract(1)
			if extracted > 0:
				pick_up_item(res.resource_type)
		target_resource = null
	action_completed.emit()


func _on_action_completed() -> void:
	_action_in_progress = false
	_action_index += 1
	if _action_index < current_plan.size():
		_execute_current_action()
	else:
		current_plan = []
		current_goal = ""


func _on_role_changed(_agent_id: String, _old_role: String, _new_role: String) -> void:
	current_goal = ""
	current_plan = []
	_action_index = 0
	_action_in_progress = false
	role_changed.emit(agent_id, _old_role, _new_role)


func get_agent_position() -> Vector2:
	return global_position


func move_to(target: Vector2) -> void:
	_navigator.move_to(target)


func get_nest_position() -> Vector2:
	if nest_ref:
		return nest_ref.global_position
	return Vector2.ZERO


func deposit_at_nest(item_type: String) -> void:
	if nest_ref and held_item != "None":
		var item: String = held_item
		drop_item()
		if nest_ref.has_method("deposit"):
			nest_ref.deposit(item, 1)


func get_nearest_resource(pos: Vector2, resource_type: String) -> Node:
	if resource_manager_ref:
		return resource_manager_ref.get_nearest_resource(pos, resource_type)
	return null


func set_target_resource(node: Node) -> void:
	target_resource = node


func get_held_item() -> String:
	return held_item


func pick_up_item(item: String) -> void:
	held_item = item
	item_changed.emit(item)


func drop_item() -> void:
	held_item = "None"
	item_changed.emit("None")


func reduce_hunger(amount: float) -> void:
	hunger = maxf(hunger - amount, 0.0)


func restore_energy(amount: float) -> void:
	energy = minf(energy + amount, 100.0)


func complete_action() -> void:
	action_completed.emit()


func clear_discovered_resource() -> void:
	discovered_resource_type = ""
	discovered_resource_pos = Vector2.ZERO


func get_world_bounds() -> Rect2:
	return Rect2(_map_min, _map_max - _map_min)


func get_role_component() -> Node:
	return _role_component


func _get_om():
	return get_node("/root/OrganizationManager")
