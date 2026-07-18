extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Debugger UI Ticket 05 Test Harness (GOAP Plan Section) ===")
	print("")

	_test_plan_section_only_built_when_configured()
	_test_plan_collapsed_by_default()
	_test_plan_expanded_when_configured()
	_test_show_agent_info_lists_plan_actions_in_order()
	_test_empty_plan_shows_explicit_empty_state()
	_test_clear_resets_plan_to_empty_state()

	await _test_plan_updates_on_replan_at_refresh_rate()

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


func _plan_texts(inspector: DebuggerInspector) -> Array:
	var texts: Array = []
	for child in inspector._plan_list.get_children():
		texts.append(child.text)
	return texts


func _make_debugger() -> Control:
	var scene: PackedScene = preload("res://ui/debugger/debugger_ui.tscn")
	var debugger = scene.instantiate()
	add_child(debugger)
	return debugger


## Disables agent._process() since these tests never call agent.setup() and its
## GOAP cycle would otherwise try to navigate without a nav map present.
func _make_agent(agent_id: String, role: String) -> Node:
	var agent_scene: PackedScene = preload("res://agents/agent.tscn")
	var agent = agent_scene.instantiate()
	add_child(agent)
	agent.agent_id = agent_id
	agent._role_component.load_role(role)
	agent.set_process(false)
	return agent


func _test_plan_section_only_built_when_configured() -> void:
	print("[Test] Plan section is only built when 'plan' is listed in inspector_sections")
	var without := DebuggerInspector.new()
	add_child(without)
	without.setup(["role", "action"])
	_assert(without._plan_fold == null, "Plan section absent when not configured")
	without.queue_free()

	var withit := DebuggerInspector.new()
	add_child(withit)
	withit.setup(["role", "action", "plan"])
	_assert(withit._plan_fold != null, "Plan section built when listed in config")
	withit.queue_free()


func _test_plan_collapsed_by_default() -> void:
	print("[Test] Plan section starts folded when plan_expanded_by_default is false")
	var inspector := DebuggerInspector.new()
	add_child(inspector)
	inspector.setup(["plan"], {}, false)
	_assert(inspector._plan_fold.folded == true, "Plan section folded by default")
	inspector.queue_free()


func _test_plan_expanded_when_configured() -> void:
	print("[Test] Plan section starts expanded when plan_expanded_by_default is true")
	var inspector := DebuggerInspector.new()
	add_child(inspector)
	inspector.setup(["plan"], {}, true)
	_assert(inspector._plan_fold.folded == false, "Plan section expanded when configured")
	inspector.queue_free()


func _test_show_agent_info_lists_plan_actions_in_order() -> void:
	print("[Test] show_agent_info() lists the plan's action names in execution order")
	var inspector := DebuggerInspector.new()
	add_child(inspector)
	inspector.setup(["plan"])

	var info := {
		"agent_id": "agent_x",
		"role": "Gatherer",
		"active_goal": "CollectFood",
		"executing_action": "MoveTo",
		"energy": 50.0,
		"hunger": 10.0,
		"plan": ["MoveTo", "PickupFood", "ReturnToNest"],
	}
	inspector.show_agent_info(info, Color("#4ec9b0"))

	_assert(_plan_texts(inspector) == ["MoveTo", "PickupFood", "ReturnToNest"],
		"Plan list matches action order (got: %s)" % [_plan_texts(inspector)])

	inspector.queue_free()


func _test_empty_plan_shows_explicit_empty_state() -> void:
	print("[Test] An agent with no plan shows an explicit empty state, not a stale list")
	var inspector := DebuggerInspector.new()
	add_child(inspector)
	inspector.setup(["plan"])

	inspector.show_agent_info({"plan": ["MoveTo", "PickupFood"]}, Color("#4ec9b0"))
	_assert(_plan_texts(inspector) == ["MoveTo", "PickupFood"], "Plan populated before clearing to empty")

	inspector.show_agent_info({"plan": []}, Color("#4ec9b0"))
	_assert(_plan_texts(inspector) == ["(no plan)"], "Empty plan shows a placeholder, not a stale list (got: %s)" % [_plan_texts(inspector)])

	inspector.queue_free()


func _test_clear_resets_plan_to_empty_state() -> void:
	print("[Test] clear() resets the plan list to the empty state")
	var inspector := DebuggerInspector.new()
	add_child(inspector)
	inspector.setup(["plan"])
	inspector.show_agent_info({"plan": ["MoveTo", "PickupFood"]}, Color("#4ec9b0"))

	inspector.clear()

	_assert(_plan_texts(inspector) == ["(no plan)"], "Plan list cleared to empty state (got: %s)" % [_plan_texts(inspector)])

	inspector.queue_free()


func _test_plan_updates_on_replan_at_refresh_rate() -> void:
	print("[Test] Plan section updates when the agent's plan changes, at the normal refresh rate")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agent := _make_agent("agent_dbg_plan_1", "Explorer")
	agent._goap_cycle.current_goal = "Explore"
	agent._goap_cycle.current_plan = ["MoveTo", "RandomExplore"]
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = true

	om.register_agent("agent_dbg_plan_1", "Explorer", agent)
	var item: TreeItem = debugger._agent_items["agent_dbg_plan_1"]
	item.select(0)
	debugger._update_timer = 0.0

	_assert(_plan_texts(debugger._inspector) == ["MoveTo", "RandomExplore"], "Plan list starts with the initial plan")

	agent._goap_cycle.current_plan = ["Patrol"]

	debugger._process(0.05)
	_assert(_plan_texts(debugger._inspector) == ["MoveTo", "RandomExplore"], "Plan list has not refreshed before the update interval elapses (got: %s)" % [_plan_texts(debugger._inspector)])

	debugger._process(0.2)
	_assert(_plan_texts(debugger._inspector) == ["Patrol"], "Plan list refreshes to the replanned actions once the interval elapses (got: %s)" % [_plan_texts(debugger._inspector)])

	om.unregister_agent("agent_dbg_plan_1")
	agent.queue_free()
	debugger.queue_free()
	await get_tree().process_frame
