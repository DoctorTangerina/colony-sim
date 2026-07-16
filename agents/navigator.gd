extends Node

signal arrived

const MOVE_TIMEOUT: float = 5.0

var _nav_agent: NavigationAgent2D = null
var _body: CharacterBody2D = null
var _speed: float = 200.0
var _moving: bool = false
var _move_timer: float = 0.0
var _nav_ready: bool = false


func setup(nav_agent: NavigationAgent2D, body: CharacterBody2D, speed: float) -> void:
	_nav_agent = nav_agent
	_body = body
	_speed = speed

	var nav_map := _body.get_world_2d().navigation_map
	NavigationServer2D.map_changed.connect(func(_map: RID) -> void: _nav_ready = true)
	if NavigationServer2D.map_get_iteration_id(nav_map) > 0:
		_nav_ready = true


func move_to(target: Vector2) -> void:
	var nav_map := _body.get_world_2d().navigation_map
	var closest := NavigationServer2D.map_get_closest_point(nav_map, target)
	_nav_agent.target_position = closest
	_moving = true
	_move_timer = MOVE_TIMEOUT


func is_moving() -> bool:
	return _moving


func process(delta: float) -> void:
	if not _nav_ready:
		return
	if not _moving:
		return

	_move_timer -= delta
	if _move_timer <= 0.0:
		_body.velocity = Vector2.ZERO
		_moving = false
		arrived.emit()
		return

	if _nav_agent.is_navigation_finished():
		_body.velocity = Vector2.ZERO
		_moving = false
		arrived.emit()
		return

	var next_pos := _nav_agent.get_next_path_position()
	var direction := (next_pos - _body.global_position).normalized()
	_body.velocity = direction * _speed
	_body.move_and_slide()
