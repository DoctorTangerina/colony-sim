extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Debugger UI Ticket 03 Test Harness (Docked Panel + Live Agent Tree) ===")
	print("")

	await _test_panel_width_from_config()
	await _test_agent_tab_present_in_tab_container()
	await _test_tree_columns_from_config()
	await _test_rows_added_on_registration_with_role_color()
	await _test_rows_removed_on_unregistration()
	await _test_rows_refresh_at_update_hz_not_per_frame()
	await _test_backfills_agents_registered_before_panel_boots()
	await _test_main_scene_boots_with_debugger_tracking_live_agents()

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


func _test_panel_width_from_config() -> void:
	print("[Test] Panel width comes from configs/ui/debugger.json's panel_width key")
	var config: Dictionary = ConfigLoader.load_dict("res://configs/ui/debugger.json")
	var debugger := _make_debugger()

	_assert(debugger.offset_left == -float(config.get("panel_width", 450)), "offset_left matches -panel_width (got: %s)" % debugger.offset_left)

	debugger.queue_free()
	await get_tree().process_frame


## DebuggerUI wraps a TabContainer per ticket 1 (debugger-ui-org-overlay); the
## Agent tab is the first tab and houses the same Tree + Inspector that used
## to sit directly on the panel. Later tickets (Organization/Log/Settings)
## add more tabs alongside it, so this asserts the wrapping shape and the
## Agent tab's fixed first position without pinning the total tab count.
func _test_agent_tab_present_in_tab_container() -> void:
	print("[Test] DebuggerUI wraps a TabContainer with an 'Agent' tab holding the Tree and Inspector")
	var debugger := _make_debugger()

	var tabs: TabContainer = debugger.get_node("Tabs")
	_assert(tabs != null, "DebuggerUI has a TabContainer child")
	_assert(tabs.get_tab_count() >= 1, "At least one tab present (got %d)" % tabs.get_tab_count())
	_assert(tabs.get_tab_title(0) == "Agent", "The first tab is titled 'Agent' (got: %s)" % tabs.get_tab_title(0))

	var agent_tab: Control = tabs.get_tab_control(0)
	_assert(agent_tab.name == "Agent", "Agent tab control is named 'Agent'")
	_assert(debugger._tree.get_parent() == agent_tab, "Tree lives inside the Agent tab")
	_assert(debugger._inspector.get_parent() == agent_tab, "Inspector lives inside the Agent tab")

	debugger.queue_free()
	await get_tree().process_frame


func _test_tree_columns_from_config() -> void:
	print("[Test] Tree columns come from the tree_columns config")
	var config: Dictionary = ConfigLoader.load_dict("res://configs/ui/debugger.json")
	var debugger := _make_debugger()

	var tree: Tree = debugger._tree
	_assert(tree.columns == config.get("tree_columns", []).size(), "Tree column count matches config (got: %s)" % tree.columns)

	debugger.queue_free()
	await get_tree().process_frame


func _test_rows_added_on_registration_with_role_color() -> void:
	print("[Test] A row appears on agent_registered with id/role/action columns and the role's configured color")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agent := _make_agent("agent_dbg_1", "Gatherer")
	agent._goap_cycle.current_goal = "CollectFood"
	agent._goap_cycle.current_plan = ["MoveTo", "PickupFood"]
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = true

	om.register_agent("agent_dbg_1", "Gatherer", agent)

	_assert(debugger._agent_items.has("agent_dbg_1"), "Row added for the registered agent")

	var item: TreeItem = debugger._agent_items["agent_dbg_1"]
	var id_col: int = debugger._columns.find("agent_id")
	var role_col: int = debugger._columns.find("role")
	var action_col: int = debugger._columns.find("action")

	_assert(item.get_text(id_col) == "agent_dbg_1", "Agent ID column shows the agent id (got: %s)" % item.get_text(id_col))
	_assert(item.get_text(role_col) == "Gatherer", "Role column shows the role name (got: %s)" % item.get_text(role_col))
	_assert(item.get_text(action_col) == "MoveTo", "Action column shows the executing action (got: %s)" % item.get_text(action_col))
	_assert(item.get_custom_color(role_col) == Color("#4ec9b0"), "Role cell is tinted with the Gatherer role's configured color (got: %s)" % item.get_custom_color(role_col))

	om.unregister_agent("agent_dbg_1")
	agent.queue_free()
	debugger.queue_free()
	await get_tree().process_frame


func _test_rows_removed_on_unregistration() -> void:
	print("[Test] A row disappears when its agent unregisters")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agent := _make_agent("agent_dbg_2", "Explorer")

	om.register_agent("agent_dbg_2", "Explorer", agent)
	_assert(debugger._agent_items.has("agent_dbg_2"), "Row exists after registration")

	om.unregister_agent("agent_dbg_2")
	_assert(not debugger._agent_items.has("agent_dbg_2"), "Row removed after unregistration")

	agent.queue_free()
	debugger.queue_free()
	await get_tree().process_frame


func _test_rows_refresh_at_update_hz_not_per_frame() -> void:
	print("[Test] Row values refresh at update_hz, not every frame")
	var om = get_node("/root/OrganizationManager")
	var debugger := _make_debugger()
	var agent := _make_agent("agent_dbg_3", "Explorer")
	agent._goap_cycle.current_goal = "Explore"
	agent._goap_cycle.current_plan = ["MoveTo", "RandomExplore"]
	agent._goap_cycle._action_index = 0
	agent._goap_cycle._action_in_progress = true

	om.register_agent("agent_dbg_3", "Explorer", agent)
	debugger._update_timer = 0.0

	var item: TreeItem = debugger._agent_items["agent_dbg_3"]
	var action_col: int = debugger._columns.find("action")
	_assert(item.get_text(action_col) == "MoveTo", "Row starts showing the initial executing action")

	agent._goap_cycle._action_index = 1

	debugger._process(0.05)
	_assert(item.get_text(action_col) == "MoveTo", "Row has not refreshed before the update interval elapses (got: %s)" % item.get_text(action_col))

	debugger._process(0.2)
	_assert(item.get_text(action_col) == "RandomExplore", "Row refreshes once accumulated time crosses the update interval (got: %s)" % item.get_text(action_col))

	om.unregister_agent("agent_dbg_3")
	agent.queue_free()
	debugger.queue_free()
	await get_tree().process_frame


## Scene tree ready-order between DebuggerUI and the sim isn't guaranteed (a
## sibling reorder in the editor can flip it), so an agent may already be
## registered with the OM by the time the panel boots. The panel must
## backfill it rather than only reacting to future agent_registered signals.
func _test_backfills_agents_registered_before_panel_boots() -> void:
	print("[Test] Agents already registered before the panel boots still appear as rows")
	var om = get_node("/root/OrganizationManager")
	var agent := _make_agent("agent_dbg_4", "Guard")
	om.register_agent("agent_dbg_4", "Guard", agent)

	var debugger := _make_debugger()

	_assert(debugger._agent_items.has("agent_dbg_4"), "Row backfilled for an agent registered before the panel existed")

	var item: TreeItem = debugger._agent_items["agent_dbg_4"]
	var role_col: int = debugger._columns.find("role")
	_assert(item.get_text(role_col) == "Guard", "Backfilled row shows the correct role (got: %s)" % item.get_text(role_col))
	_assert(item.get_custom_color(role_col) == Color("#f44747"), "Backfilled row is tinted with the Guard role's configured color (got: %s)" % item.get_custom_color(role_col))

	om.unregister_agent("agent_dbg_4")
	agent.queue_free()
	debugger.queue_free()
	await get_tree().process_frame


func _test_main_scene_boots_with_debugger_tracking_live_agents() -> void:
	print("[Test] Headless run of Main.tscn wires DebuggerUI to the live agent registry with no script errors")
	var om = get_node("/root/OrganizationManager")
	var main_scene: PackedScene = preload("res://Main.tscn")
	var main := main_scene.instantiate()
	add_child(main)

	for i in range(15):
		await get_tree().physics_frame

	var debugger: Control = main.get_node("DebuggerUI")
	_assert(debugger != null, "Main.tscn resolves a DebuggerUI child node")
	_assert(debugger._agent_items.size() == om.get_total_agent_count() and om.get_total_agent_count() > 0,
		"Debugger tree tracks every live agent from Simulation.tscn (got %d rows for %d registered agents)" % [debugger._agent_items.size(), om.get_total_agent_count()])

	main.queue_free()
	await get_tree().physics_frame
