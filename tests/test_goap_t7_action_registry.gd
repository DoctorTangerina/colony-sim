extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== GOAP T7 Test Harness (Action Registry Executor) ===")
	print("")

	_test_eat_reduces_hunger_and_completes()
	_test_rest_restores_energy_and_completes()
	_test_return_to_nest_moves_to_nest_position()
	_test_deposit_resource_deposits_and_completes()
	_test_pickup_wood_moves_to_nearest_wood()
	_test_random_explore_moves_within_bounds()
	_test_unregistered_action_falls_back_to_default()
	_test_registered_actions_do_not_use_default_handler()

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


func _make_mock_agent(extra_source: String = "") -> Node:
	var script := GDScript.new()
	script.source_code = """extends IAgentActions

var nest_ref = null
var _completed: bool = false
var _hunger_reduced_by: float = -1.0
var _energy_restored_by: float = -1.0
var _move_called: bool = false
var _move_target: Vector2 = Vector2.ZERO
var _deposited_item: String = ""
var held_item: String = "None"

func complete_action() -> void:
	_completed = true

func reduce_hunger(amount: float) -> void:
	_hunger_reduced_by = amount

func restore_energy(amount: float) -> void:
	_energy_restored_by = amount

func move_to(target: Vector2) -> void:
	_move_called = true
	_move_target = target

func get_nest_position() -> Vector2:
	if nest_ref:
		return Vector2(576, 324)
	return Vector2.ZERO

func get_held_item() -> String:
	return held_item

func deposit_at_nest(item_type: String) -> void:
	_deposited_item = item_type

func get_world_bounds() -> Rect2:
	return Rect2(Vector2(32, 32), Vector2(1088, 584))

%s
""" % extra_source
	script.reload()
	var agent = script.new()
	add_child(agent)
	return agent


func _test_eat_reduces_hunger_and_completes() -> void:
	print("[Test] Eat reduces hunger by 40 and completes")
	var agent = _make_mock_agent()
	GoapActionExecutor.execute_action("Eat", agent)
	_assert(agent._hunger_reduced_by == 40.0, "reduce_hunger called with 40.0")
	_assert(agent._completed, "complete_action called")


func _test_rest_restores_energy_and_completes() -> void:
	print("[Test] Rest restores energy by 40 and completes")
	var agent = _make_mock_agent()
	GoapActionExecutor.execute_action("Rest", agent)
	_assert(agent._energy_restored_by == 40.0, "restore_energy called with 40.0")
	_assert(agent._completed, "complete_action called")


func _test_return_to_nest_moves_to_nest_position() -> void:
	print("[Test] ReturnToNest moves to the nest position")
	var agent = _make_mock_agent()
	agent.nest_ref = Node2D.new()
	GoapActionExecutor.execute_action("ReturnToNest", agent)
	_assert(agent._move_called, "move_to was called")
	_assert(agent._move_target.distance_to(Vector2(576, 324)) < 1.0, "Moved to nest position")


func _test_deposit_resource_deposits_and_completes() -> void:
	print("[Test] DepositResource deposits held item and completes")
	var agent = _make_mock_agent()
	agent.held_item = "Food"
	GoapActionExecutor.execute_action("DepositResource", agent)
	_assert(agent._deposited_item == "Food", "deposit_at_nest called with held item")
	_assert(agent._completed, "complete_action called")


func _test_pickup_wood_moves_to_nearest_wood() -> void:
	print("[Test] PickupWood moves to nearest Wood via known-position fallback")
	var agent = _make_mock_agent("""
var _known_positions: Dictionary = {"Wood": [Vector2(700, 800)]}

func get_agent_position() -> Vector2:
	return Vector2(50, 50)

func get_nearest_resource(_pos: Vector2, _resource_type: String) -> Node:
	return null

func get_known_positions() -> Dictionary:
	return _known_positions

func set_target_resource(_node: Node) -> void:
	pass
""")
	GoapActionExecutor.execute_action("PickupWood", agent)
	_assert(agent._move_called, "move_to was called")
	_assert(agent._move_target.distance_to(Vector2(700, 800)) < 1.0, "Moved to known Wood position")


func _test_random_explore_moves_within_bounds() -> void:
	print("[Test] RandomExplore moves within world bounds")
	var agent = _make_mock_agent()
	GoapActionExecutor.execute_action("RandomExplore", agent)
	var bounds: Rect2 = agent.get_world_bounds()
	_assert(agent._move_called, "move_to was called")
	_assert(bounds.has_point(agent._move_target), "Move target is within world bounds")


func _test_unregistered_action_falls_back_to_default() -> void:
	print("[Test] An action absent from the registry completes via the default handler")
	var agent = _make_mock_agent()
	GoapActionExecutor.execute_action("SomeBrandNewActionNotInAnyRegistry", agent)
	_assert(agent._completed, "A wholly new, never-registered action name still completes via default handler")
	_assert(not agent._move_called, "Unregistered action does not move")


func _test_registered_actions_do_not_use_default_handler() -> void:
	print("[Test] Registered actions bypass the default handler (only move, no premature complete)")
	var agent = _make_mock_agent()
	GoapActionExecutor.execute_action("RandomExplore", agent)
	_assert(not agent._completed, "RandomExplore does not call complete_action directly (Navigator completes it on arrival)")
