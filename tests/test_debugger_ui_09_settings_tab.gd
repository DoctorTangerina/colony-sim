extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Debugger UI Ticket 09 Test Harness (Settings Tab: Role Market Knobs) ===")
	print("")

	_test_panel_never_blank_before_first_refresh()
	_test_show_settings_info_displays_values()
	_test_show_settings_info_reflects_runtime_change()
	_test_settings_panel_has_no_editable_controls()

	await _test_settings_tab_present_in_debugger_ui()
	await _test_main_scene_boots_with_settings_tab_showing_live_om_state()

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


func _test_panel_never_blank_before_first_refresh() -> void:
	print("[Test] The Settings tab shows default-value rows immediately after setup(), before any refresh tick")
	var panel := DebuggerSettingsPanel.new()
	add_child(panel)
	panel.setup()

	_assert(panel._dynamic_roles_label.text == "Dynamic Roles Enabled: false", "Dynamic Roles row has a default value before first refresh")
	_assert(panel._role_cooldown_label.text == "Role Cooldown: 0.0s", "Role Cooldown row has a default value before first refresh")
	_assert(panel._min_unassigned_label.text == "Min Unassigned Threshold: 0", "Min Unassigned Threshold row has a default value before first refresh")

	panel.queue_free()


func _test_show_settings_info_displays_values() -> void:
	print("[Test] show_settings_info() displays dynamic_roles_enabled, role_cooldown, and min_unassigned_threshold read-only")
	var panel := DebuggerSettingsPanel.new()
	add_child(panel)
	panel.setup()

	panel.show_settings_info({
		"dynamic_roles_enabled": true,
		"role_cooldown": 10.0,
		"min_unassigned_threshold": 5,
	})

	_assert(panel._dynamic_roles_label.text == "Dynamic Roles Enabled: true", "Dynamic Roles label matches input (got: %s)" % panel._dynamic_roles_label.text)
	_assert(panel._role_cooldown_label.text == "Role Cooldown: 10.0s", "Role Cooldown label matches input (got: %s)" % panel._role_cooldown_label.text)
	_assert(panel._min_unassigned_label.text == "Min Unassigned Threshold: 5", "Min Unassigned Threshold label matches input (got: %s)" % panel._min_unassigned_label.text)

	panel.queue_free()


func _test_show_settings_info_reflects_runtime_change() -> void:
	print("[Test] show_settings_info() reflects a runtime settings change on the next call, without recreating the panel")
	var panel := DebuggerSettingsPanel.new()
	add_child(panel)
	panel.setup()

	panel.show_settings_info({"dynamic_roles_enabled": true, "role_cooldown": 10.0, "min_unassigned_threshold": 5})
	panel.show_settings_info({"dynamic_roles_enabled": false, "role_cooldown": 15.5, "min_unassigned_threshold": 3})

	_assert(panel._dynamic_roles_label.text == "Dynamic Roles Enabled: false", "Dynamic Roles label picks up the runtime change (got: %s)" % panel._dynamic_roles_label.text)
	_assert(panel._role_cooldown_label.text == "Role Cooldown: 15.5s", "Role Cooldown label picks up the runtime change (got: %s)" % panel._role_cooldown_label.text)
	_assert(panel._min_unassigned_label.text == "Min Unassigned Threshold: 3", "Min Unassigned Threshold label picks up the runtime change (got: %s)" % panel._min_unassigned_label.text)

	panel.queue_free()


func _test_settings_panel_has_no_editable_controls() -> void:
	print("[Test] The Settings panel renders plain Labels only - no controls to change the values from the panel")
	var panel := DebuggerSettingsPanel.new()
	add_child(panel)
	panel.setup()

	var all_labels := true
	for child in panel.get_children():
		if not (child is Label):
			all_labels = false

	_assert(all_labels, "Every row in the Settings panel is a read-only Label")

	panel.queue_free()


## Verifies the Settings tab exists in the running DebuggerUI shell (ticket
## 1's TabContainer) and houses a DebuggerSettingsPanel, matching how ticket
## 07/08 verified the Organization/Log tabs' wiring.
func _test_settings_tab_present_in_debugger_ui() -> void:
	print("[Test] DebuggerUI's Settings tab houses a DebuggerSettingsPanel")
	var debugger := _make_debugger()

	var tabs: TabContainer = debugger.get_node("Tabs")
	var settings_index := -1
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == "Settings":
			settings_index = i
			break

	_assert(settings_index != -1, "A tab titled 'Settings' exists")
	if settings_index != -1:
		var settings_tab: Control = tabs.get_tab_control(settings_index)
		_assert(debugger._settings_panel.get_parent() == settings_tab, "Settings panel lives inside the Settings tab")

	debugger.queue_free()
	await get_tree().process_frame


## Boots Main.tscn to confirm the Settings tab's data flows from the real OM
## snapshot at runtime, not just a mocked dict, and reflects a runtime change
## via set_dynamic_roles() without restarting - mirroring test_debugger_ui_07/08's
## final full-scene boot tests. The refresh tick is forced directly (rather
## than waited for via engine frame timing) for determinism.
func _test_main_scene_boots_with_settings_tab_showing_live_om_state() -> void:
	print("[Test] Headless run of Main.tscn shows the live role market settings in the Settings tab, updating after a runtime change, with no script errors")
	var om = get_node("/root/OrganizationManager")
	var main_scene: PackedScene = preload("res://Main.tscn")
	var main := main_scene.instantiate()
	add_child(main)

	for i in range(15):
		await get_tree().physics_frame

	var debugger: Control = main.get_node("DebuggerLayer/DebuggerUI")
	_assert(debugger != null, "Main.tscn resolves a DebuggerUI child node")
	_assert(debugger._settings_panel != null, "DebuggerUI built its Settings panel")

	debugger._update_timer = 0.0
	debugger._process(1.0)

	var info: Dictionary = om.get_debug_info()
	_assert(debugger._settings_panel._dynamic_roles_label.text == "Dynamic Roles Enabled: %s" % info.get("dynamic_roles_enabled", false),
		"Settings panel's Dynamic Roles label matches the live OM snapshot (got: %s)" % debugger._settings_panel._dynamic_roles_label.text)

	# Flip the setting at runtime and force another refresh tick - the tab
	# must reflect the change without restarting, per user story 7.
	var toggled: bool = not info.get("dynamic_roles_enabled", false)
	om.set_dynamic_roles(toggled)
	debugger._update_timer = 0.0
	debugger._process(1.0)

	_assert(debugger._settings_panel._dynamic_roles_label.text == "Dynamic Roles Enabled: %s" % toggled,
		"Settings panel reflects a runtime set_dynamic_roles() change (got: %s)" % debugger._settings_panel._dynamic_roles_label.text)

	main.queue_free()
	await get_tree().physics_frame
