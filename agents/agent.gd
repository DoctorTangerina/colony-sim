extends CharacterBody2D

signal arrived_at_target
signal item_changed(new_item: String)

var agent_id: String
var energy: float = 100.0
var hunger: float = 0.0
var held_item: String = "None"
var current_role: String = ""
var current_goal: String = ""
var current_plan: Array = []

var target_position: Vector2
var moving: bool = false

@onready var nav_agent: NavigationAgent2D = $NavAgent


func _ready() -> void:
	if agent_id.is_empty():
		agent_id = str(get_instance_id())


func _process(delta: float) -> void:
	if not moving:
		return

	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		moving = false
		arrived_at_target.emit()
		return

	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	velocity = direction * 200.0
	move_and_slide()


func move_to(target: Vector2) -> void:
	var closest := NavigationServer2D.map_get_closest_point(
		nav_agent.get_navigation_map(), target
	)
	target_position = closest
	nav_agent.target_position = closest
	moving = true


func hold_item(item: String) -> void:
	held_item = item
	item_changed.emit(item)


func drop_item() -> void:
	held_item = "None"
	item_changed.emit("None")
