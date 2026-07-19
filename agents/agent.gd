extends IAgentActions

signal item_changed(new_item: String)
signal action_completed
signal role_changed(agent_id: String, old_role: String, new_role: String)
signal agent_died(agent_id: String, last_role: String)

var agent_id: String
var energy: float = 100.0
var hunger: float = 0.0
var held_item: String = "None"

var nest_ref: Node2D = null
var resource_manager_ref: Node = null

@onready var nav_agent: NavigationAgent2D = $NavAgent
@onready var _navigator: Node = $Navigator
@onready var _nest_zone: Node = $NestZone
@onready var _role_component: Node = $RoleComponent
@onready var _role_acquisition: Node = $RoleAcquisition
@onready var _planner: Node = $GOAPPlanner
@onready var _goal_selector: Node = $GOAPGoalSelector
@onready var _goap_cycle: Node = $GoapCycle

var _is_dead: bool = false

var _planning_interval: float = 2.0
var _switch_margin: float = 0.0
var _agent_speed: float = 200.0
var _discovery_radius: float = 50.0
var _interaction_radius: float = 50.0
var _hunger_increase_per_second: float = 1.0
var _death_hunger: float = 100.0
var discovered_resource_type: String = ""
var discovered_resource_pos: Vector2 = Vector2.ZERO
var failed_resource_type: String = ""
var failed_resource_pos: Vector2 = Vector2.ZERO
var _known_positions: Dictionary = {}

var _map_min: Vector2
var _map_max: Vector2
var _near_unreported_resource: bool = false


func _ready() -> void:
	if agent_id.is_empty():
		agent_id = str(get_instance_id())

	# Validate required child nodes
	if not nav_agent or not _navigator or not _nest_zone or not _role_component or not _role_acquisition or not _planner or not _goal_selector or not _goap_cycle:
		push_error("Agent missing required child nodes: NavAgent, Navigator, NestZone, RoleComponent, RoleAcquisition, GOAPPlanner, GOAPGoalSelector, GoapCycle")
		return

	_load_sim_config()
	_setup_modules()


func _load_sim_config() -> void:
	var data: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	_agent_speed = data.get("agentSpeed", 200.0)
	_planning_interval = data.get("planningInterval", 2.0)
	_switch_margin = data.get("switchMargin", 2.0)
	_discovery_radius = data.get("discoveryRadius", 50.0)
	_interaction_radius = data.get("interactionRadius", 50.0)
	_hunger_increase_per_second = data.get("hungerIncreasePerSecond", 1.0)
	_death_hunger = data.get("deathHunger", 100.0)
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

	_goap_cycle.setup(self, _planner, _goal_selector, _role_acquisition, _build_world_state, _planning_interval, _switch_margin)
	action_completed.connect(_goap_cycle.on_action_completed)


func setup(nest: Node2D, resource_manager: Node) -> void:
	nest_ref = nest
	resource_manager_ref = resource_manager
	_nest_zone.setup(nest_ref, self)
	var sim_config: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	var cooldown_duration: float = sim_config.get("roleCooldown", 10.0)
	_role_acquisition.setup(_get_om(), _role_component, _nest_zone, agent_id, cooldown_duration)
	_role_acquisition.register_initial_role(self)


func _process(delta: float) -> void:
	if _is_dead:
		return

	_update_hunger(delta)
	_check_death()
	if _is_dead:
		return

	_scan_for_discovery()
	_mark_explored_trail()
	_navigator.process(delta)
	_goap_cycle.process(delta)


## Standing pressure (SPEC.md Ticket 01): rises every frame regardless of the
## agent's current action, goal, or Rest state - uncoupled from GOAP entirely.
func _update_hunger(delta: float) -> void:
	hunger = minf(hunger + _hunger_increase_per_second * delta, 100.0)


## Guards against re-emitting agent_died once hunger has topped out. Energy
## no longer factors into death (SPEC.md Ticket 01) - hitting 0 energy only
## ever forces Rest (Ticket 02), never kills.
func _check_death() -> void:
	if _is_dead or hunger < _death_hunger:
		return
	_is_dead = true
	_navigator.stop()
	agent_died.emit(agent_id, _role_component.get_role_name())


func _build_world_state() -> WorldState:
	# The Nest's TriggerZone is the single "at the nest" definition
	# (CONTEXT.md: Nest) - _nest_zone is only null for bare-script test
	# agents that skip the scene's _ready()/setup() entirely.
	var at_nest: bool = _nest_zone.is_in_nest_zone() if _nest_zone else false

	var food_visible := false
	var wood_visible := false
	var at_food_position := false
	var at_wood_position := false

	if resource_manager_ref:
		var food_node = resource_manager_ref.get_nearest_resource(global_position, "Food")
		if food_node and is_instance_valid(food_node):
			var food_dist: float = global_position.distance_to(food_node.global_position)
			food_visible = food_dist < _discovery_radius
			at_food_position = food_dist < _interaction_radius
		var wood_node = resource_manager_ref.get_nearest_resource(global_position, "Wood")
		if wood_node and is_instance_valid(wood_node):
			var wood_dist: float = global_position.distance_to(wood_node.global_position)
			wood_visible = wood_dist < _discovery_radius
			at_wood_position = wood_dist < _interaction_radius

		var blackboard = null
		if nest_ref and nest_ref.has_method("get_blackboard"):
			blackboard = nest_ref.get_blackboard()

		if blackboard and blackboard.has_method("get_entries"):
			_known_positions = BlackboardSync.sync_known_positions(blackboard, resource_manager_ref)

	_scan_for_discovery()

	var has_known_food: bool = _known_positions.has("Food")
	var has_known_wood: bool = _known_positions.has("Wood")
	var has_unreported_discovery: bool = not discovered_resource_type.is_empty()
	var has_failed_report: bool = not failed_resource_type.is_empty()

	return WorldState.build(held_item, energy, hunger, at_nest, food_visible, wood_visible,
		_near_unreported_resource, has_known_food, has_known_wood, has_unreported_discovery,
		at_food_position, at_wood_position, has_failed_report)


## Scans for a nearby resource the Blackboard doesn't know about yet and
## captures it into discovered_resource_type/pos, which persists on the agent
## (independent of current proximity) until ReportResource delivers it at the
## nest. Called every frame from _process - not just at GOAP planning ticks -
## because those ticks are seconds apart and an agent walking a straight line
## can cross a resource's discovery radius entirely between two of them.
func _scan_for_discovery() -> void:
	_near_unreported_resource = false
	if not resource_manager_ref or not nest_ref:
		return
	var blackboard = null
	if nest_ref.has_method("get_blackboard"):
		blackboard = nest_ref.get_blackboard()
	if not blackboard or not blackboard.has_method("has_entry_at"):
		return

	for res_node in resource_manager_ref.get_all_resources():
		if is_instance_valid(res_node) and global_position.distance_to(res_node.global_position) < _discovery_radius:
			if not blackboard.has_entry_at(res_node.resource_type, res_node.global_position):
				_near_unreported_resource = true
				if discovered_resource_type.is_empty():
					discovered_resource_type = res_node.resource_type
					discovered_resource_pos = res_node.global_position
				break


## Passive, continuous, role-blind (CONTEXT.md: Explored Trail; ADR 9) -
## every agent's incidental movement marks coverage, not just Explorers',
## which is what lets non-scouting roles' ordinary travel give Explorers free
## coverage of already-visited ground.
func _mark_explored_trail() -> void:
	if not nest_ref or not nest_ref.has_method("get_explored_trail"):
		return
	var trail = nest_ref.get_explored_trail()
	if trail and trail.has_method("mark_visited"):
		trail.mark_visited(global_position)


func _on_arrived_at_target() -> void:
	action_completed.emit()


func _on_role_changed(_agent_id: String, _old_role: String, _new_role: String) -> void:
	_goap_cycle.on_role_changed()
	role_changed.emit(agent_id, _old_role, _new_role)


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


## Instantaneous interaction, gated on Interaction Range (ADR 5): GoTo already
## owns the travel leg (Ticket 2), so this never moves the agent - it grabs
## only if a node of resource_type is already within arm's reach, and is a
## no-op (still completes) otherwise, matching every other Pickup dishonesty
## case that Action Failure detection (Ticket 4) will catch. Hands are single-
## slot (CONTEXT.md: Held Item) - refuses to overwrite an already-held item.
func attempt_pickup(resource_type: String) -> void:
	if held_item != "None":
		return
	var node: Node = get_nearest_resource(global_position, resource_type)
	if not node or not is_instance_valid(node):
		return
	if global_position.distance_to(node.global_position) >= _interaction_radius:
		return
	if not node.has_method("extract"):
		return
	var extracted: int = node.extract(1)
	if extracted > 0:
		pick_up_item(resource_type)


func get_known_positions() -> Dictionary:
	return _known_positions.duplicate()


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


func reset_hunger() -> void:
	hunger = 0.0


func restore_energy(amount: float) -> void:
	energy = minf(energy + amount, 100.0)


func complete_action() -> void:
	action_completed.emit()


func clear_discovered_resource() -> void:
	discovered_resource_type = ""
	discovered_resource_pos = Vector2.ZERO


## ADR 6: called by GoapCycle once it detects (via verify-by-effect) that a
## Pickup action's declared effect didn't hold - direct evidence the agent's
## own current position is a stale Blackboard entry for resource_type. Single
## carry slot, independent of discovered_resource_type/pos: a report already
## pending is kept until ReportDepletion clears it, rather than overwritten
## by a second failure.
func record_failed_report(resource_type: String, position: Vector2) -> void:
	if not failed_resource_type.is_empty():
		return
	failed_resource_type = resource_type
	failed_resource_pos = position


func clear_failed_report() -> void:
	failed_resource_type = ""
	failed_resource_pos = Vector2.ZERO


func get_world_bounds() -> Rect2:
	return Rect2(_map_min, _map_max - _map_min)


## Delegates to the Nest's shared Explored Trail (ADR 9) so exploration
## converges on covering the whole map instead of the same random hot spots
## forever. Falls back to a plain uniform-random point (the old behavior)
## when there's no Nest/trail to consult - e.g. bare-script test agents that
## skip setup() entirely, same fallback shape as _build_world_state's
## _nest_zone guard.
func pick_explore_target() -> Vector2:
	var bounds := get_world_bounds()
	if nest_ref and nest_ref.has_method("get_explored_trail"):
		var trail = nest_ref.get_explored_trail()
		if trail and trail.has_method("pick_target"):
			return trail.pick_target(bounds)
	return Vector2(
		randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
		randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
	)


func get_role_component() -> Node:
	return _role_component


func get_debug_info() -> Dictionary:
	return {
		"agent_id": agent_id,
		"role": _role_component.get_role_name(),
		"active_goal": _goap_cycle.current_goal,
		"executing_action": _goap_cycle.get_executing_action(),
		"energy": energy,
		"hunger": hunger,
		"plan": _goap_cycle.current_plan.duplicate(),
	}


func _get_om():
	return get_node("/root/OrganizationManager")
