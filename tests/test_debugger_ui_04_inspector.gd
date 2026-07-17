extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Debugger UI Ticket 04 Test Harness (Click-to-Inspect Pane) ===")
	print("")

	_test_inspector_builds_only_configured_sections()
	_test_show_agent_info_populates_fields()
	_test_clear_resets_fields()

	await _test_selecting_tree_row_populates_inspector()
	await _test_inspector_refreshes_at_update_hz_while_selected()
	await _test_inspector_clears_when_selected_agent_unregisters()

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


func _make_debugger() -> Control:
	var scene: PackedScene = preload("res://ui/debugger/debugger_ui.tscn")
	var debugger = scene.instantiate()
	add_child(debugger)
	return debugger


## Debug-info assertions read agent/goap_cycle fields directly; the agent's
## own _process() is disabled since these tests never call agent.setup() and
## its GOAP cycle would otherwise try to navigate without a nav map present.
func _make_agent(agent_id: String, role: String) -> Node:
	var agent_scene: PackedScene = preload("res://agents/agent.tscn")
	var agent = agent_scene.instantiate()
	add_child(agent)
	agent.agent_id = agent_id
	agent._role_component.load_role(role)
	agent.set_process(false)
	return agent


func _sample_info() -> Dictionary:
	return {
		"agent_id": "agent_x",
		"role": "Gatherer",
		"active_goal": "CollectFood",
		"executing_action": "MoveTo",
		"energy": 72.5,
		"hunger": 34.0,
		"plan": ["MoveTo", "PickupFood"],
	}


func _test_inspector_builds_only_configured_sections() -> void:
	print("[Test] DebuggerInspector.setup() builds only the sections listed in config")
	var inspector := DebuggerInspector.new()
	add_child(inspector)
	inspector.setup(["role", "action"])

	_assert(inspector._role_label != null, "Role section built when listed")
	_assert(inspector._action_label != null, "Action section built when listed")
	_assert(inspector._goal_label == null, "Goal section not built when absent from config")
	_assert(inspector._energy_bar == null, "Stats section not built when absent from config")

	inspector.queue_free()


func _test_show_agent_info_populates_fields() -> void:
	print("[Test] show_agent_info() populates role/goal/stats/action fields and the role color swatch")
	var inspector := DebuggerInspector.new()
	add_child(inspector)
	inspector.setup(["role", "goal", "stats", "action"])

	inspector.show_agent_info(_sample_info(), Color("#4ec9b0"))

	_assert(inspector._role_label.text == "Gatherer", "Role label shows role name (got: %s)" % inspector._role_label.text)
	_assert(inspector._role_swatch.color == Color("#4ec9b0"), "Role swatch uses the supplied role color")
	_assert(inspector._goal_label.text == "CollectFood", "Goal label shows active goal (got: %s)" % inspector._goal_label.text)
	_assert(is_equal_approx(inspector._energy_bar.value, 72.5), "Energy bar value matches (got: %s)" % inspector._energy_bar.value)
	_assert(is_equal_approx(inspector._hunger_bar.value, 34.0), "Hunger bar value matches (got: %s)" % inspector._hunger_bar.value)
	_assert(inspector._action_label.text == "MoveTo", "Action label shows executing action (got: %s)" % inspector._action_label.text)

	inspector.queue_free()


func _test_clear_resets_fields() -> void:
	print("[Test] clear() resets fields instead of leaving stale data")
	var inspector := DebuggerInspector.new()
	add_child(inspector)
	inspector.setup(["role", "goal", "stats", "action"])
	inspector.show_agent_info(_sample_info(), Color("#4ec9b0"))

	inspector.clear()

	_assert(inspector._role_label.text == "", "Role label cleared")
	_assert(inspector._role_swatch.color == Color.TRANSPARENT, "Role swatch cleared")
	_assert(inspector._goal_label.text == "", "Goal label cleared")
	_assert(inspector._energy_bar.value == 0, "Energy bar cleared")
	_assert(inspector._hunger_bar.value == 0, "Hunger bar cleared")
	_assert(inspector._action_label.text == "", "Action label cleared")

	inspector.queue_free()


## Simulates the mouse click by selecting the TreeItem directly (Tree emits
## item_selected synchronously from TreeItem.select()) - selection is the only
## trigger the panel wires, matching the mouse/touch-only requirement.
func _test_selecting_tree_row_populates_inspector() -> void:
	print("[Test] Selecting a tree row populates the inspector for that agent")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agent := _make_agent("agent_dbg_ins_1", "Gatherer")
	agent._goap_cycle.current_goal = "CollectFood"
	agent._goap_cycle.current_plan = ["MoveTo", "PickupFood"]
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = true
	agent.energy = 55.0
	agent.hunger = 12.0

	om.register_agent("agent_dbg_ins_1", "Gatherer", agent)
	var item: TreeItem = debugger._agent_items["agent_dbg_ins_1"]
	item.select(0)

	_assert(debugger._selected_agent_id == "agent_dbg_ins_1", "Debugger tracks the selected agent id")
	_assert(debugger._inspector._role_label.text == "Gatherer", "Inspector role label shows the selected agent's role")
	_assert(debugger._inspector._role_swatch.color == Color("#4ec9b0"), "Inspector role swatch uses the Gatherer role color")
	_assert(debugger._inspector._goal_label.text == "CollectFood", "Inspector goal label shows the active goal")
	_assert(debugger._inspector._action_label.text == "MoveTo", "Inspector action label shows the executing action")
	_assert(is_equal_approx(debugger._inspector._energy_bar.value, 55.0), "Inspector energy bar matches agent energy")
	_assert(is_equal_approx(debugger._inspector._hunger_bar.value, 12.0), "Inspector hunger bar matches agent hunger")

	om.unregister_agent("agent_dbg_ins_1")
	agent.queue_free()
	debugger.queue_free()
	await get_tree().process_frame


func _test_inspector_refreshes_at_update_hz_while_selected() -> void:
	print("[Test] Inspector values refresh at update_hz while the agent stays selected, not per-frame")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agent := _make_agent("agent_dbg_ins_2", "Explorer")
	agent._goap_cycle.current_goal = "Explore"
	agent._goap_cycle.current_plan = ["MoveTo", "RandomExplore"]
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = true

	om.register_agent("agent_dbg_ins_2", "Explorer", agent)
	var item: TreeItem = debugger._agent_items["agent_dbg_ins_2"]
	item.select(0)
	debugger._update_timer = 0.0

	_assert(debugger._inspector._action_label.text == "MoveTo", "Inspector starts showing the initial executing action")

	agent._goap_cycle._action_index = 1

	debugger._process(0.05)
	_assert(debugger._inspector._action_label.text == "MoveTo", "Inspector has not refreshed before the update interval elapses (got: %s)" % debugger._inspector._action_label.text)

	debugger._process(0.2)
	_assert(debugger._inspector._action_label.text == "RandomExplore", "Inspector refreshes once accumulated time crosses the update interval (got: %s)" % debugger._inspector._action_label.text)

	om.unregister_agent("agent_dbg_ins_2")
	agent.queue_free()
	debugger.queue_free()
	await get_tree().process_frame


func _test_inspector_clears_when_selected_agent_unregisters() -> void:
	print("[Test] Inspector clears instead of showing stale data when the selected agent unregisters")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agent := _make_agent("agent_dbg_ins_3", "Guard")
	agent._goap_cycle.current_goal = "Patrol"
	agent._goap_cycle.current_plan = ["MoveTo"]
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = true

	om.register_agent("agent_dbg_ins_3", "Guard", agent)
	var item: TreeItem = debugger._agent_items["agent_dbg_ins_3"]
	item.select(0)

	_assert(debugger._inspector._role_label.text == "Guard", "Inspector populated before unregistration")

	om.unregister_agent("agent_dbg_ins_3")

	_assert(debugger._selected_agent_id == "", "Debugger drops the selected agent id after unregistration")
	_assert(debugger._inspector._role_label.text == "", "Inspector role label cleared after the selected agent unregisters")
	_assert(debugger._inspector._action_label.text == "", "Inspector action label cleared after the selected agent unregisters")

	agent.queue_free()
	debugger.queue_free()
	await get_tree().process_frame
