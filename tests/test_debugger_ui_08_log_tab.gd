extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Debugger UI Ticket 08 Test Harness (Log Tab: Role Change Log) ===")
	print("")

	_test_log_panel_is_scroll_container()
	_test_panel_never_blank_before_first_refresh()
	_test_show_log_info_formats_rows_newest_first()
	_test_empty_log_shows_empty_state_row()
	_test_show_log_info_rebuilds_only_on_growth()

	await _test_log_tab_present_in_debugger_ui()
	await _test_main_scene_boots_with_log_tab_showing_live_om_state()

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


func _row_texts(panel: DebuggerLogPanel) -> Array:
	var texts: Array = []
	for child in panel._log_list.get_children():
		texts.append(child.text)
	return texts


func _test_log_panel_is_scroll_container() -> void:
	print("[Test] DebuggerLogPanel renders its rows inside a ScrollContainer")
	var panel := DebuggerLogPanel.new()
	add_child(panel)
	panel.setup()

	_assert(panel is ScrollContainer, "DebuggerLogPanel is itself a ScrollContainer")

	panel.queue_free()


func _test_panel_never_blank_before_first_refresh() -> void:
	print("[Test] The Log tab shows an explicit empty-state row immediately after setup(), before any refresh tick")
	var panel := DebuggerLogPanel.new()
	add_child(panel)
	panel.setup()

	_assert(panel._log_list.get_child_count() == 1, "Panel has exactly one placeholder row before the first refresh (got %d)" % panel._log_list.get_child_count())

	panel.queue_free()


func _test_show_log_info_formats_rows_newest_first() -> void:
	print("[Test] show_log_info() formats rows as '[<timestamp,1 decimal>s] <agent_id>: <old_role> → <new_role>', newest first, no reason field")
	var panel := DebuggerLogPanel.new()
	add_child(panel)
	panel.setup()

	var log := [
		{"timestamp": 12.34, "agent_id": "ant_1", "old_role": "Unassigned", "new_role": "Explorer", "reason": "deficit"},
		{"timestamp": 143.3, "agent_id": "ant_7", "old_role": "Explorer", "new_role": "Forager", "reason": "surplus_migration"},
	]
	panel.show_log_info(log)

	_assert(_row_texts(panel) == ["[143.3s] ant_7: Explorer → Forager", "[12.3s] ant_1: Unassigned → Explorer"],
		"Rows are newest-first, timestamp rounded to 1 decimal, no reason field (got: %s)" % [_row_texts(panel)])

	panel.queue_free()


func _test_empty_log_shows_empty_state_row() -> void:
	print("[Test] An empty log shows an explicit empty-state row, not a blank tab")
	var panel := DebuggerLogPanel.new()
	add_child(panel)
	panel.setup()

	panel.show_log_info([])
	var texts := _row_texts(panel)

	_assert(texts.size() == 1 and not String(texts[0]).is_empty(),
		"Empty log renders a single non-blank placeholder row (got: %s)" % [texts])

	panel.queue_free()


func _test_show_log_info_rebuilds_only_on_growth() -> void:
	print("[Test] show_log_info() rebuilds the row list only when the log's length has grown since the last refresh")
	var panel := DebuggerLogPanel.new()
	add_child(panel)
	panel.setup()

	var first_log := [
		{"timestamp": 10.0, "agent_id": "ant_1", "old_role": "Unassigned", "new_role": "Explorer"},
	]
	panel.show_log_info(first_log)
	var row_before: Label = panel._log_list.get_child(0)
	_assert(row_before.text == "[10.0s] ant_1: Unassigned → Explorer", "First refresh renders the initial entry")

	# Same length, different content - a genuine no-op tick, not a coincidence:
	# if a rebuild happened, this new content would show up; it must not.
	var same_length_different_content := [
		{"timestamp": 99.0, "agent_id": "ant_9", "old_role": "Explorer", "new_role": "Guard"},
	]
	panel.show_log_info(same_length_different_content)
	var row_after_noop: Label = panel._log_list.get_child(0)
	_assert(row_after_noop == row_before, "Unchanged-length tick performs no rebuild (same Label instance)")
	_assert(row_after_noop.text == "[10.0s] ant_1: Unassigned → Explorer",
		"Unchanged-length tick leaves the stale (pre-tick) text rather than rebuilding (got: %s)" % row_after_noop.text)

	var grown_log := first_log + [
		{"timestamp": 20.0, "agent_id": "ant_2", "old_role": "Explorer", "new_role": "Forager"},
	]
	panel.show_log_info(grown_log)

	_assert(_row_texts(panel) == ["[20.0s] ant_2: Explorer → Forager", "[10.0s] ant_1: Unassigned → Explorer"],
		"Grown tick rebuilds with newest-first ordering (got: %s)" % [_row_texts(panel)])

	panel.queue_free()


## Verifies the Log tab exists in the running DebuggerUI shell (ticket 1's
## TabContainer) and houses a DebuggerLogPanel, matching how ticket 07
## verified the Organization tab's wiring.
func _test_log_tab_present_in_debugger_ui() -> void:
	print("[Test] DebuggerUI's Log tab houses a DebuggerLogPanel")
	var debugger := _make_debugger()

	var tabs: TabContainer = debugger.get_node("Tabs")
	var log_index := -1
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == "Log":
			log_index = i
			break

	_assert(log_index != -1, "A tab titled 'Log' exists")
	if log_index != -1:
		var log_tab: Control = tabs.get_tab_control(log_index)
		_assert(debugger._log_panel.get_parent() == log_tab, "Log panel lives inside the Log tab")
		_assert(debugger._log_panel is ScrollContainer, "Log panel is a ScrollContainer")

	debugger.queue_free()
	await get_tree().process_frame


## Boots Main.tscn to confirm the Log tab's data flows from the real OM
## snapshot at runtime, not just a mocked dict - mirroring test_debugger_ui_07's
## final full-scene boot test. The refresh tick is forced directly (rather
## than waited for via engine frame timing) for determinism.
func _test_main_scene_boots_with_log_tab_showing_live_om_state() -> void:
	print("[Test] Headless run of Main.tscn shows the live role-change log in the Log tab with no script errors")
	var om = get_node("/root/OrganizationManager")
	var main_scene: PackedScene = preload("res://Main.tscn")
	var main := main_scene.instantiate()
	add_child(main)

	for i in range(15):
		await get_tree().physics_frame

	var debugger: Control = main.get_node("DebuggerUI")
	_assert(debugger != null, "Main.tscn resolves a DebuggerUI child node")
	_assert(debugger._log_panel != null, "DebuggerUI built its Log panel")

	debugger._update_timer = 0.0
	debugger._process(1.0)

	var info: Dictionary = om.get_debug_info()
	var log: Array = info.get("role_change_log", [])
	var texts: Array = _row_texts(debugger._log_panel)

	if log.is_empty():
		_assert(texts.size() == 1, "Empty live log still shows a single empty-state row (got: %s)" % [texts])
	else:
		_assert(texts.size() == log.size(),
			"Log tab row count matches the live OM log length (got %d rows for %d entries)" % [texts.size(), log.size()])

	main.queue_free()
	await get_tree().physics_frame
