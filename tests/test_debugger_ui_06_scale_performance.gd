extends Node

var tests_passed: int = 0
var tests_failed: int = 0

const AGENT_COUNT := 60
const ROLES := ["Gatherer", "Guard", "Explorer"]
const FRAME_TIME_BUDGET_MS := 16.0
const SCREENSHOT_PATH := "res://.scratch/debugger-ui/screenshots/debugger_scale_test.png"


func _ready() -> void:
	print("=== Debugger UI Ticket 06 Test Harness (Scale and Performance) ===")
	print("")

	await _test_tree_tracks_all_agents_at_scale()
	await _test_inspector_populates_at_scale()
	await _test_frame_time_under_budget_at_scale()

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


## Agent's own _process() is disabled since these are spawned without
## setup() (no nav map present headlessly); role/goal/plan/stats are set
## directly so get_debug_info() reflects a fully-populated agent, same
## pattern as test_debugger_ui_03/04.
func _make_agent(agent_id: String, role: String) -> Node:
	var agent_scene: PackedScene = preload("res://agents/agent.tscn")
	var agent = agent_scene.instantiate()
	add_child(agent)
	agent.agent_id = agent_id
	agent._role_component.load_role(role)
	agent.set_process(false)
	return agent


func _spawn_agents(om, count: int) -> Array:
	var agents: Array = []
	for i in range(count):
		var role: String = ROLES[i % ROLES.size()]
		var agent_id := "agent_scale_%d" % i
		var agent := _make_agent(agent_id, role)
		agent._goap_cycle.current_goal = "Goal%d" % i
		agent._goap_cycle.current_plan = ["Step1", "Step2", "Step3"]
		agent._goap_cycle._action_index = i % 3
		agent._goap_cycle._action_in_progress = true
		agent.energy = float(i % 100)
		agent.hunger = float((i * 7) % 100)
		om.register_agent(agent_id, role, agent)
		agents.append(agent)
	return agents


func _teardown(om, agents: Array, debugger: Control) -> void:
	for agent in agents:
		om.unregister_agent(agent.agent_id)
		agent.queue_free()
	debugger.queue_free()
	await get_tree().process_frame


func _test_tree_tracks_all_agents_at_scale() -> void:
	print("[Test] Tree row count matches registered agent count at scale (>=50 agents)")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agents := _spawn_agents(om, AGENT_COUNT)

	await get_tree().process_frame

	_assert(agents.size() >= 50, "Spawned at least 50 agents (got %d)" % agents.size())
	_assert(debugger._agent_items.size() == om.get_total_agent_count(),
		"Tree row count matches registered agent count (got %d rows for %d agents)" % [debugger._agent_items.size(), om.get_total_agent_count()])

	await _teardown(om, agents, debugger)


func _test_inspector_populates_at_scale() -> void:
	print("[Test] Selecting an agent mid-run populates the inspector correctly at scale")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agents := _spawn_agents(om, AGENT_COUNT)

	for i in range(5):
		await get_tree().process_frame

	var target_agent: Node = agents[AGENT_COUNT / 2]
	var target_info: Dictionary = target_agent.get_debug_info()
	var item: TreeItem = debugger._agent_items[target_agent.agent_id]
	item.select(0)

	_assert(debugger._selected_agent_id == target_agent.agent_id,
		"Debugger tracks the selected agent id mid-run (got: %s)" % debugger._selected_agent_id)
	_assert(debugger._inspector._role_label.text == target_info.get("role"),
		"Inspector role label matches the selected agent's role at scale (got: %s)" % debugger._inspector._role_label.text)
	_assert(is_equal_approx(debugger._inspector._energy_bar.value, target_info.get("energy")),
		"Inspector energy bar matches the selected agent's energy at scale")
	_assert(is_equal_approx(debugger._inspector._hunger_bar.value, target_info.get("hunger")),
		"Inspector hunger bar matches the selected agent's hunger at scale")
	_assert(debugger._inspector._action_label.text == target_info.get("executing_action"),
		"Inspector action label matches the selected agent's executing action at scale")
	_assert(debugger._inspector._goal_label.text == target_info.get("active_goal"),
		"Inspector goal label matches the selected agent's active goal at scale (got: %s)" % debugger._inspector._goal_label.text)

	var plan_texts: Array = []
	for child in debugger._inspector._plan_list.get_children():
		plan_texts.append(child.text)
	_assert(plan_texts == target_info.get("plan"),
		"Inspector plan section lists the selected agent's plan action names in order at scale (got: %s)" % [plan_texts])

	await _teardown(om, agents, debugger)


func _test_frame_time_under_budget_at_scale() -> void:
	print("[Test] Frame process time stays under the 16 ms budget at scale with 5 Hz polling")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agents := _spawn_agents(om, AGENT_COUNT)

	var item: TreeItem = debugger._agent_items[agents[0].agent_id]
	item.select(0)

	# Performance.TIME_PROCESS was tried first but isn't a usable signal in a
	# headless, script-driven run: it reads back a stale 0 unless real
	# wall-clock time elapses between samples, and once it does update it
	# tracks Godot's own headless idle-throttle pacing (a near-constant ~15ms
	# regardless of load) rather than this panel's actual refresh cost.
	# Timing DebuggerUI._process() directly measures the quantity the 16 ms
	# budget is actually about. Deltas straddle the update_hz boundary so the
	# sampled ticks include the worst case: every row and the inspector
	# refreshing together in the same tick.
	var interval: float = debugger._update_interval
	var deltas: Array = [0.0, interval, interval * 0.1, interval, interval * 0.1, interval]

	var max_frame_time_ms := 0.0
	for delta in deltas:
		var start_us := Time.get_ticks_usec()
		debugger._process(delta)
		max_frame_time_ms = maxf(max_frame_time_ms, (Time.get_ticks_usec() - start_us) / 1000.0)

	print("  measured peak refresh-tick process time at %d agents: %.3f ms" % [AGENT_COUNT, max_frame_time_ms])
	_assert(max_frame_time_ms < FRAME_TIME_BUDGET_MS,
		"Peak frame process time under %.1f ms budget at %d agents (got %.3f ms)" % [FRAME_TIME_BUDGET_MS, AGENT_COUNT, max_frame_time_ms])

	_capture_screenshot()

	await _teardown(om, agents, debugger)


## Visual-reference artifact, not a pixel assertion. `--headless` forces
## Godot's Dummy rendering backend on this platform (no live swapchain), so
## get_texture().get_image() always returns null there - that's an engine/
## platform limitation, not a debugger bug, so it's logged and skipped rather
## than failed. Real pixels require a real rendering driver and an off-screen
## window, e.g.:
##   godot --rendering-driver d3d12 --position -3000,-3000 --scene res://tests/test_debugger_ui_06_scale_performance.tscn
func _capture_screenshot() -> void:
	if DisplayServer.get_name() == "headless":
		print("  SKIP: screenshot capture unavailable under --headless (Dummy renderer produces no pixels on this platform)")
		return

	var image: Image = get_viewport().get_texture().get_image()
	var dir := DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("res://.scratch/debugger-ui/screenshots")
	_assert(image.save_png(SCREENSHOT_PATH) == OK, "Screenshot captured and saved to %s" % SCREENSHOT_PATH)
