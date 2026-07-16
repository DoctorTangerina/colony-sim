extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP OM Autoload Test Harness (Ticket 03) ===")
	print("")

	_test_get_om_returns_live_autoload()
	_test_role_acquisition_wired_to_live_om()

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
	var agent_scene: PackedScene = preload("res://agents/agent.tscn")
	var agent = agent_scene.instantiate()
	add_child(agent)
	return agent


func _make_nest() -> Node2D:
	var nest = preload("res://organization/Nest.tscn").instantiate()
	add_child(nest)
	return nest


func _test_get_om_returns_live_autoload() -> void:
	print("[Test] Agent._get_om() resolves the live OrganizationManager autoload")
	var agent = _make_agent()
	var om = agent._get_om()
	var expected_om = get_node("/root/OrganizationManager")

	_assert(om != null, "_get_om() returns a non-null node")
	_assert(om == expected_om, "_get_om() returns the same instance as /root/OrganizationManager")
	_assert(om.has_method("get_all_requests"), "_get_om() result exposes OM's public API")


func _test_role_acquisition_wired_to_live_om() -> void:
	print("[Test] Agent.setup() wires RoleAcquisition to the live OM autoload")
	var agent = _make_agent()
	var nest = _make_nest()
	agent.setup(nest, null)

	var expected_om = get_node("/root/OrganizationManager")
	_assert(agent._role_acquisition._om_ref == expected_om, "RoleAcquisition._om_ref is the live OrganizationManager autoload")
