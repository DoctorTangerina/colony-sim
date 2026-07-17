extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T10 Test Harness (Nest Trigger Zone Config) ===")
	print("")

	_test_nest_json_has_trigger_zone_radius()
	_test_nest_loads_radius_from_config()
	await _test_bodies_enter_zone_by_trigger_radius_not_body_radius()
	await _test_agent_nest_zone_reports_almost_touching()

	print("")
	print("=== Results: %d passed, %d failed ===" % [tests_passed, tests_failed])
	get_tree().quit(0 if tests_failed == 0 else 1)


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		tests_passed += 1
		print("  PASS: %s" % test_name)
	else:
		tests_failed += 1
		print("  FAIL: %s" % test_name)


func _make_nest() -> Node2D:
	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	return nest


func _make_agent() -> Node:
	var agent = preload("res://agents/agent.tscn").instantiate()
	add_child(agent)
	return agent


func _make_test_body(radius: float, position: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	body.add_child(shape)
	add_child(body)
	body.global_position = position
	return body


func _test_nest_json_has_trigger_zone_radius() -> void:
	print("[Test] configs/nest.json declares triggerZoneRadius")
	var data: Dictionary = ConfigLoader.load_dict("res://configs/nest.json")
	_assert(data.has("triggerZoneRadius"), "nest.json has triggerZoneRadius")


func _test_nest_loads_radius_from_config() -> void:
	print("[Test] Nest loads its TriggerZone radius from nest.json via ConfigLoader")
	var data: Dictionary = ConfigLoader.load_dict("res://configs/nest.json")
	var expected_radius: float = data["triggerZoneRadius"]

	var nest = _make_nest()
	var zone: Area2D = nest.get_trigger_zone()
	var shape: CollisionShape2D = zone.get_node("CollisionShape2D")
	var circle := shape.shape as CircleShape2D

	_assert(circle.radius == expected_radius,
		"TriggerZone CircleShape2D.radius matches nest.json's triggerZoneRadius (got %s, expected %s)" % [circle.radius, expected_radius])


func _test_bodies_enter_zone_by_trigger_radius_not_body_radius() -> void:
	print("[Test] A body nearly touching the nest (but outside its own collision shape) still enters the trigger zone")
	var data: Dictionary = ConfigLoader.load_dict("res://configs/nest.json")
	var trigger_radius: float = data["triggerZoneRadius"]

	var nest = _make_nest()
	nest.global_position = Vector2.ZERO
	var nest_shape: CollisionShape2D = nest.get_node("CollisionShape2D")
	var nest_body_radius: float = (nest_shape.shape as CircleShape2D).radius

	# Sits well past the nest's own collision shape (not "touching" the body)
	# but still inside the deliberately-oversized trigger zone.
	var near_distance: float = nest_body_radius + (trigger_radius - nest_body_radius) * 0.5
	var near_body := _make_test_body(8.0, Vector2(near_distance, 0))

	# Clearly outside the trigger zone entirely.
	var far_body := _make_test_body(8.0, Vector2(trigger_radius + 200.0, 0))

	await get_tree().physics_frame
	await get_tree().physics_frame

	var zone: Area2D = nest.get_trigger_zone()
	var overlapping := zone.get_overlapping_bodies()

	_assert(near_distance > nest_body_radius, "Sanity check: near body does not overlap the nest's own collision shape")
	_assert(near_body in overlapping, "A body inside the trigger radius, but not touching the nest body, enters the zone")
	_assert(not (far_body in overlapping), "A body outside the trigger radius does not enter the zone")


func _test_agent_nest_zone_reports_almost_touching() -> void:
	print("[Test] A real Agent's NestZone module reports in-zone when almost touching, out-of-zone when far")
	var data: Dictionary = ConfigLoader.load_dict("res://configs/nest.json")
	var trigger_radius: float = data["triggerZoneRadius"]

	var nest = _make_nest()
	nest.global_position = Vector2.ZERO
	var nest_shape: CollisionShape2D = nest.get_node("CollisionShape2D")
	var nest_body_radius: float = (nest_shape.shape as CircleShape2D).radius

	var agent = _make_agent()
	agent.setup(nest, null)

	# Almost touching: outside the nest's own physical collision shape, but
	# inside the oversized trigger zone - exactly the gap the zone exists to cover.
	var near_distance: float = nest_body_radius + (trigger_radius - nest_body_radius) * 0.5
	agent.global_position = Vector2(near_distance, 0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(agent._nest_zone.is_in_nest_zone(),
		"Agent's NestZone.is_in_nest_zone() is true when almost touching (distance=%s, trigger_radius=%s)" % [near_distance, trigger_radius])

	agent.global_position = Vector2(trigger_radius + 200.0, 0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(not agent._nest_zone.is_in_nest_zone(),
		"Agent's NestZone.is_in_nest_zone() is false once the agent leaves the trigger radius")
