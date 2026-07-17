extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Resource Spawn Navmesh Race Test Harness ===")
	print("")

	await _test_position_query_before_physics_sync_is_zero()
	await _test_get_random_position_returns_zero_before_nav_sync()
	await _test_wait_for_navigation_map_ready_fixes_spawn_position()

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


func _make_nav_region() -> NavigationRegion2D:
	var region := NavigationRegion2D.new()
	var poly := NavigationPolygon.new()
	poly.vertices = PackedVector2Array([Vector2(1142, 638), Vector2(10, 638), Vector2(10, 10), Vector2(1142, 10)])
	poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = poly
	add_child(region)
	return region


func _test_position_query_before_physics_sync_is_zero() -> void:
	print("[Test] map_get_closest_point returns (0,0) before any physics frame syncs the new region")
	var region := _make_nav_region()
	var nav_map: RID = get_tree().root.get_world_2d().navigation_map
	var probe := Vector2(576, 324)  # well inside the polygon
	var snapped := NavigationServer2D.map_get_closest_point(nav_map, probe)
	_assert(snapped == Vector2.ZERO,
		"Querying the map on the same frame the region was added yields the (0,0) sentinel (got %s)" % snapped)
	region.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_get_random_position_returns_zero_before_nav_sync() -> void:
	print("[Test] ResourceManager._get_random_position() returns exactly (0,0) when called before nav sync")
	var region := _make_nav_region()
	var ResourceManagerScript = preload("res://resources/resource_manager.gd")
	var rm = ResourceManagerScript.new()
	add_child(rm)
	rm._load_config()
	var pos: Vector2 = rm._get_random_position()
	_assert(pos == Vector2.ZERO,
		"_get_random_position() called immediately after the nav region is added returns (0,0) (got %s) - this is the reported bug" % pos)
	rm.queue_free()
	region.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_wait_for_navigation_map_ready_fixes_spawn_position() -> void:
	print("[Test] Regression: awaiting ResourceManager._wait_for_navigation_map_ready() before spawning yields a real point")
	var region := _make_nav_region()
	var ResourceManagerScript = preload("res://resources/resource_manager.gd")
	var rm = ResourceManagerScript.new()
	add_child(rm)
	rm._load_config()
	await rm._wait_for_navigation_map_ready()
	var pos: Vector2 = rm._get_random_position()
	_assert(pos != Vector2.ZERO,
		"_get_random_position() returns a real navmesh point after _wait_for_navigation_map_ready() (got %s)" % pos)
	rm.queue_free()
	region.queue_free()
