extends Node

var resource_definitions: Dictionary = {}
var active_nodes: Array[ResourceNode] = []

const RESOURCE_SCENE: PackedScene = preload("res://resources/resource_node.tscn")

var _map_min := Vector2(32, 32)
var _map_max := Vector2(1120, 616)

func _ready() -> void:
	_load_config()
	_load_definitions()
	await get_tree().create_timer(0.1).timeout
	_spawn_initial_nodes()

func _load_config() -> void:
	var data: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	_map_min = Vector2(data.get("mapMinX", 32), data.get("mapMinY", 32))
	_map_max = Vector2(data.get("mapMaxX", 1120), data.get("mapMaxY", 616))

func _load_definitions() -> void:
	var entries: Array = ConfigLoader.load_array("res://configs/resources.json")
	for entry in entries:
		resource_definitions[entry["type"]] = entry

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
