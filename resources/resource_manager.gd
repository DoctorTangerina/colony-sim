extends Node

var resource_definitions: Dictionary = {}
var active_nodes: Array[ResourceNode] = []

const RESOURCE_SCENE: PackedScene = preload("res://resources/resource_node.tscn")
const MAP_MIN := Vector2(32, 32)
const MAP_MAX := Vector2(1120, 616)

func _ready() -> void:
	_load_definitions()
	await get_tree().create_timer(0.1).timeout
	_spawn_initial_nodes()

func _load_definitions() -> void:
	var file := FileAccess.open("res://configs/resources.json", FileAccess.READ)
	if file == null:
		push_error("ResourceManager: Could not open configs/resources.json")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("ResourceManager: JSON parse error: " + json.get_error_message())
		return
	for entry in json.data:
		resource_definitions[entry["type"]] = entry

func _spawn_initial_nodes() -> void:
	for type_name in resource_definitions:
		_spawn_node(type_name)

func _get_random_position() -> Vector2:
	var pos := Vector2(
		randf_range(MAP_MIN.x, MAP_MAX.x),
		randf_range(MAP_MIN.y, MAP_MAX.y)
	)
	var nav_map: RID = get_tree().root.get_world_2d().navigation_map
	return NavigationServer2D.map_get_closest_point(nav_map, pos)

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
