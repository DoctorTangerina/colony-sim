extends Node2D

var navigation_map: RID

func _ready() -> void:
	navigation_map = get_world_2d().navigation_map
