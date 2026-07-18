extends Node

## Regression coverage for two related changes: agents no longer physically
## block each other (CharacterBody2D collision_mask == 0), and resource nodes
## / the Nest register as NavigationObstacle2D so a moving agent's avoidance
## routes around them instead of relying on physical collision (which used to
## leave the agent stuck against the node, papered over by the 5s move
## timeout in navigator.gd).
##
## Every real Agent instance runs its own GOAP cycle the moment it's added to
## the tree, and every avoidance-enabled node shares one navigation map per
## World2D - so each subtest frees its nodes (and waits a couple of physics
## frames for the server to catch up) before the next one runs, or a leftover
## agent/obstacle from an earlier check would keep steering on the shared map
## and contaminate the later ones.

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Navigation Obstacles + Agent Passthrough Test Harness ===")
	print("")

	await _test_agent_collision_mask_ignores_everything()
	await _test_two_agents_pass_through_each_other()
	await _test_resource_node_has_avoidance_obstacle()
	await _test_nest_has_avoidance_obstacle()
	await _test_agent_navagent_avoids_obstacles_not_other_agents()
	await _test_agent_routes_around_resource_node_obstacle()

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


func _make_agent() -> Node:
	var agent = preload("res://agents/agent.tscn").instantiate()
	add_child(agent)
	return agent


func _free_and_settle(nodes: Array) -> void:
	for node in nodes:
		node.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_agent_collision_mask_ignores_everything() -> void:
	print("[Test] Agent CharacterBody2D has collision_mask 0 so move_and_slide never blocks on any body")
	var agent = _make_agent()
	_assert(agent.collision_mask == 0, "Agent collision_mask is 0 (got %d)" % agent.collision_mask)
	_assert(agent.collision_layer == 1,
		"Agent collision_layer stays 1 so the Nest TriggerZone Area2D still detects it (got %d)" % agent.collision_layer)
	await _free_and_settle([agent])


func _test_two_agents_pass_through_each_other() -> void:
	print("[Test] Two overlapping agents produce zero slide collisions when one moves through the other")
	var agent_a = _make_agent()
	var agent_b = _make_agent()
	agent_b.global_position = Vector2(200, 200)
	agent_a.global_position = Vector2(190, 200)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var any_collisions := false
	for _i in range(30):
		agent_a.velocity = Vector2(200, 0)
		agent_a.move_and_slide()
		if agent_a.get_slide_collision_count() > 0:
			any_collisions = true

	_assert(not any_collisions,
		"Agent moving directly through another agent's position never reports a slide collision")
	_assert(agent_a.global_position.x > 210.0,
		"Agent actually advanced fully through and past the other agent's position instead of being stopped (x=%s)" % agent_a.global_position.x)
	await _free_and_settle([agent_a, agent_b])


func _test_resource_node_has_avoidance_obstacle() -> void:
	print("[Test] ResourceNode exposes a NavigationObstacle2D configured for avoidance")
	var node = preload("res://resources/resource_node.tscn").instantiate()
	add_child(node)
	var obstacle: NavigationObstacle2D = node.get_node_or_null("NavObstacle")
	_assert(obstacle != null, "ResourceNode has a NavObstacle child")
	if obstacle:
		_assert(obstacle.avoidance_enabled, "ResourceNode's obstacle has avoidance_enabled")
		_assert(obstacle.radius == 16.0, "ResourceNode's obstacle radius matches its collision shape (got %s)" % obstacle.radius)
		_assert(obstacle.avoidance_layers == 1, "ResourceNode's obstacle broadcasts on avoidance layer 1 (got %s)" % obstacle.avoidance_layers)
	await _free_and_settle([node])


func _test_nest_has_avoidance_obstacle() -> void:
	print("[Test] Nest exposes a NavigationObstacle2D configured for avoidance")
	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	var obstacle: NavigationObstacle2D = nest.get_node_or_null("NavObstacle")
	_assert(obstacle != null, "Nest has a NavObstacle child")
	if obstacle:
		_assert(obstacle.avoidance_enabled, "Nest's obstacle has avoidance_enabled")
		_assert(obstacle.radius == 20.0, "Nest's obstacle radius matches its collision shape (got %s)" % obstacle.radius)
		_assert(obstacle.avoidance_layers == 1, "Nest's obstacle broadcasts on avoidance layer 1 (got %s)" % obstacle.avoidance_layers)
	await _free_and_settle([nest])


func _test_agent_navagent_avoids_obstacles_not_other_agents() -> void:
	print("[Test] Agent's NavAgent reacts to the obstacle avoidance layer but not to other agents")
	var agent = _make_agent()
	var nav_agent: NavigationAgent2D = agent.get_node("NavAgent")
	_assert(nav_agent.avoidance_enabled, "NavAgent has avoidance_enabled")
	_assert(nav_agent.avoidance_mask == 1, "NavAgent only reacts to avoidance layer 1 (obstacles) (got %s)" % nav_agent.avoidance_mask)
	_assert(nav_agent.avoidance_layers == 2, "NavAgent broadcasts on avoidance layer 2 (agents), not layer 1 (got %s)" % nav_agent.avoidance_layers)
	_assert(nav_agent.target_desired_distance >= 24.0,
		"target_desired_distance clears a resource node's obstacle radius (16) + agent radius (8) (got %s)" % nav_agent.target_desired_distance)
	_assert(nav_agent.target_desired_distance >= 28.0,
		"target_desired_distance clears the Nest's obstacle radius (20) + agent radius (8) (got %s)" % nav_agent.target_desired_distance)
	await _free_and_settle([agent])


func _make_nav_region() -> NavigationRegion2D:
	var region := NavigationRegion2D.new()
	var poly := NavigationPolygon.new()
	poly.vertices = PackedVector2Array([Vector2(0, 0), Vector2(500, 0), Vector2(500, 300), Vector2(0, 300)])
	poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = poly
	add_child(region)
	return region


func _wait_for_nav_ready(nav_map: RID, probe: Vector2) -> void:
	for _attempt in range(100):
		var changed_map: RID = await NavigationServer2D.map_changed
		if changed_map != nav_map:
			continue
		if NavigationServer2D.map_get_closest_point(nav_map, probe) != Vector2.ZERO:
			return


## Root-cause regression: before nodes were wired up as NavigationObstacle2D,
## an agent's straight-line path went directly through a resource node's
## collision shape, relying on the 5s move-timeout to eventually "arrive"
## after getting physically stuck. Now the path must curve around the node's
## avoidance radius and still reach the far side.
func _test_agent_routes_around_resource_node_obstacle() -> void:
	print("[Test] Agent walking toward a target beyond a resource node routes around it instead of crossing through it")
	var region := _make_nav_region()

	var start := Vector2(50, 150)
	var obstacle_pos := Vector2(250, 150)
	var target := Vector2(450, 150)

	var node = preload("res://resources/resource_node.tscn").instantiate()
	region.add_child(node)
	node.global_position = obstacle_pos

	var agent = preload("res://agents/agent.tscn").instantiate()
	region.add_child(agent)
	agent.global_position = start

	await _wait_for_nav_ready(agent.get_world_2d().navigation_map, start)

	agent._navigator.move_to(target)

	var min_distance_to_obstacle: float = INF
	var frames := 0
	while agent._navigator.is_moving() and frames < 400:
		await get_tree().physics_frame
		frames += 1
		var dist: float = agent.global_position.distance_to(obstacle_pos)
		if dist < min_distance_to_obstacle:
			min_distance_to_obstacle = dist

	_assert(frames < 400, "Agent finished moving before the safety frame cap (got %d frames)" % frames)
	_assert(min_distance_to_obstacle >= 15.0,
		"Agent never crossed inside the resource node's avoidance radius (got min distance %s)" % min_distance_to_obstacle)
	_assert(agent.global_position.distance_to(target) < 40.0,
		"Agent still reaches the far side of the obstacle (final distance to target: %s)" % agent.global_position.distance_to(target))
