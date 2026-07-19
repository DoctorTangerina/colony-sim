extends Node

var resource_definitions: Dictionary = {}
var active_nodes: Array[ResourceNode] = []

const RESOURCE_SCENE: PackedScene = preload("res://resources/resource_node.tscn")

var _map_min: Vector2
var _map_max: Vector2

func _ready() -> void:
	_load_config()
	_load_definitions()
	await _wait_for_navigation_map_ready()
	_spawn_initial_nodes()

func _wait_for_navigation_map_ready() -> void:
	var nav_map: RID = get_tree().root.get_world_2d().navigation_map
	var probe := (_map_min + _map_max) * 0.5
	for _attempt in range(100):
		var changed_map: RID = await NavigationServer2D.map_changed
		if changed_map != nav_map:
			continue
		if NavigationServer2D.map_get_closest_point(nav_map, probe) != Vector2.ZERO:
			return
	push_error("resource_manager: navigation map never became queryable; resources may spawn at (0,0)")

func _load_config() -> void:
	var data: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	if not data.has("mapMinX") or not data.has("mapMinY") or not data.has("mapMaxX") or not data.has("mapMaxY"):
		push_error("resource_manager: simulation.json missing map bounds (mapMinX, mapMinY, mapMaxX, mapMaxY)")
		return
	_map_min = Vector2(data["mapMinX"], data["mapMinY"])
	_map_max = Vector2(data["mapMaxX"], data["mapMaxY"])

func _load_definitions() -> void:
	var entries: Array = ConfigLoader.load_array("res://configs/resources.json")
	for entry in entries:
		resource_definitions[entry["type"]] = entry
	_apply_respawn_time_override()


## ADR 12: the sweep's "scarcity" lever - overrides respawnTime for every
## resource type uniformly (Food and Wood move together, per the experiment
## design) when --respawn-time is passed. maxAmount is deliberately left
## alone; a run with no CLI args leaves resource_definitions exactly as
## loaded from JSON.
func _apply_respawn_time_override() -> void:
	var respawn_override: float = ExperimentCLI.get_float("respawn-time", -1.0)
	if respawn_override < 0.0:
		return
	for type_name in resource_definitions:
		resource_definitions[type_name]["respawnTime"] = respawn_override


func _spawn_initial_nodes() -> void:
	for type_name in resource_definitions:
		_spawn_node(type_name)

func _get_random_position() -> Vector2:
	var nav_map: RID = get_tree().root.get_world_2d().navigation_map
	for _attempt in range(10):
		var pos := Vector2(
			randf_range(_map_min.x, _map_max.x),
			randf_range(_map_min.y, _map_max.y)
		)
		var snapped := NavigationServer2D.map_get_closest_point(nav_map, pos)
		if snapped.distance_to(pos) < 50.0:
			return snapped
	var center := (_map_min + _map_max) * 0.5
	return NavigationServer2D.map_get_closest_point(nav_map, center)

func _spawn_node(resource_type: String) -> ResourceNode:
	var def: Dictionary = resource_definitions.get(resource_type, {})
	var node: ResourceNode = RESOURCE_SCENE.instantiate()
	node.resource_type = resource_type
	node.remaining_amount = def.get("maxAmount", 100)
	node.global_position = _get_random_position()
	node.depleted.connect(_on_resource_depleted)
	add_child(node)
	active_nodes.append(node)
	return node

func _on_resource_depleted(node: ResourceNode) -> void:
	active_nodes.erase(node)
	respawn(node.resource_type)

func respawn(resource_type: String) -> void:
	var def: Dictionary = resource_definitions.get(resource_type, {})
	var wait_time: float = def.get("respawnTime", 20.0)
	await get_tree().create_timer(wait_time).timeout
	_spawn_node(resource_type)
	_guarantee_minimums()

func _guarantee_minimums() -> void:
	for type_name in resource_definitions:
		var count := 0
		for node in active_nodes:
			if node.resource_type == type_name and is_instance_valid(node):
				count += 1
		if count == 0:
			_spawn_node(type_name)

func get_nearest_resource(from_position: Vector2, resource_type: String) -> ResourceNode:
	var nearest: ResourceNode = null
	var nearest_dist := INF
	for node in active_nodes:
		if node.resource_type != resource_type or not is_instance_valid(node):
			continue
		var dist := from_position.distance_squared_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest


func get_all_resources() -> Array[ResourceNode]:
	return active_nodes.duplicate()


func resource_exists_at(resource_type: String, position: Vector2) -> bool:
	for node in active_nodes:
		if node.resource_type != resource_type or not is_instance_valid(node):
			continue
		if position.distance_to(node.global_position) < 50.0:
			return true
	return false
