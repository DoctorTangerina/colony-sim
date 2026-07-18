extends Node

signal arrived

const MOVE_TIMEOUT: float = 5.0

var _nav_agent: NavigationAgent2D = null
var _body: CharacterBody2D = null
var _speed: float = 200.0
var _moving: bool = false
var _move_deadline_msec: int = 0
var _nav_ready: bool = false


func setup(nav_agent: NavigationAgent2D, body: CharacterBody2D, speed: float) -> void:
	_nav_agent = nav_agent
	_body = body
	_speed = speed

	var nav_map := _body.get_world_2d().navigation_map
	NavigationServer2D.map_changed.connect(func(_map: RID) -> void: _nav_ready = true)
	if NavigationServer2D.map_get_iteration_id(nav_map) > 0:
		_nav_ready = true

	_nav_agent.velocity_computed.connect(_on_velocity_computed)


func move_to(target: Vector2) -> void:
	var nav_map := _body.get_world_2d().navigation_map
	var closest := NavigationServer2D.map_get_closest_point(nav_map, target)
	_nav_agent.target_position = closest
	_moving = true
	_move_deadline_msec = Time.get_ticks_msec() + int(MOVE_TIMEOUT * 1000.0)


func is_moving() -> bool:
	return _moving


func stop() -> void:
	_moving = false
	_body.velocity = Vector2.ZERO


func process(_delta: float) -> void:
	if not _nav_ready:
		return
	if not _moving:
		return

	if Time.get_ticks_msec() >= _move_deadline_msec:
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
	var desired_velocity := direction * _speed

	if _nav_agent.avoidance_enabled:
		# Routes through the RVO avoidance system - the actual move happens in
		# _on_velocity_computed once the server replies with a safe_velocity,
		# not here. Obstacle nodes (NavigationObstacle2D) push the reply away
		# from themselves; agents ignore each other via avoidance_mask.
		_nav_agent.velocity = desired_velocity
	else:
		_body.velocity = desired_velocity
		_body.move_and_slide()


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if not _moving:
		return
	_body.velocity = safe_velocity
	_body.move_and_slide()
