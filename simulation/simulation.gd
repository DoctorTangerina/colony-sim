extends Node2D

var navigation_map: RID

func _ready() -> void:
	navigation_map = get_world_2d().navigation_map
	var rm = $ResourceManager
	var nest = $Nest

	_connect_resources(rm)
	_connect_agents(nest, rm)
	_connect_om(nest)


func _connect_resources(rm: Node) -> void:
	for child in get_children():
		if child is ResourceNode:
			child.depleted.connect(rm._on_resource_depleted)


func _connect_agents(nest: Node2D, rm: Node) -> void:
	_find_and_setup_agents(self, nest, rm)


func _find_and_setup_agents(node: Node, nest: Node2D, rm: Node) -> void:
	for child in node.get_children():
		if child is CharacterBody2D and child.has_method("setup"):
			child.setup(nest, rm)
		if child.get_child_count() > 0:
			_find_and_setup_agents(child, nest, rm)


func _connect_om(nest: Node2D) -> void:
	var om = get_node_or_null("/root/OrganizationManager")
	if om and om.has_method("setup"):
		om.setup(nest)
