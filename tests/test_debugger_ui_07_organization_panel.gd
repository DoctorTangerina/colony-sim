extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Debugger UI Ticket 07 Test Harness (Organization Tab: Storage + Role Market) ===")
	print("")

	_test_org_panel_builds_only_configured_sections()
	_test_storage_and_role_market_expanded_by_default()
	_test_show_org_info_populates_storage_labels()
	_test_role_market_row_format_with_and_without_pending()
	_test_role_market_includes_unassigned()
	_test_show_org_info_rebuilds_role_market_rows_on_change()
	_test_show_org_info_degrades_to_zero_empty_without_error()

	await _test_organization_tab_present_in_debugger_ui()
	await _test_main_scene_boots_with_organization_tab_showing_live_om_state()

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


func _role_market_texts(panel: DebuggerOrgPanel) -> Array:
	var texts: Array = []
	for child in panel._role_market_list.get_children():
		texts.append(child.text)
	return texts


func _test_org_panel_builds_only_configured_sections() -> void:
	print("[Test] DebuggerOrgPanel.setup() builds only the sections listed in config")
	var storage_only := DebuggerOrgPanel.new()
	add_child(storage_only)
	storage_only.setup(["storage"])
	_assert(storage_only._storage_fold != null, "Storage section built when listed")
	_assert(storage_only._role_market_fold == null, "Role Market section not built when absent from config")
	storage_only.queue_free()

	var market_only := DebuggerOrgPanel.new()
	add_child(market_only)
	market_only.setup(["role_market"])
	_assert(market_only._role_market_fold != null, "Role Market section built when listed")
	_assert(market_only._storage_fold == null, "Storage section not built when absent from config")
	market_only.queue_free()


func _test_storage_and_role_market_expanded_by_default() -> void:
	print("[Test] Storage and Role Market folds start expanded, not config-driven")
	var panel := DebuggerOrgPanel.new()
	add_child(panel)
	panel.setup(["storage", "role_market"])

	_assert(panel._storage_fold.folded == false, "Storage fold starts expanded (got folded=%s)" % panel._storage_fold.folded)
	_assert(panel._role_market_fold.folded == false, "Role Market fold starts expanded (got folded=%s)" % panel._role_market_fold.folded)

	panel.queue_free()


func _test_show_org_info_populates_storage_labels() -> void:
	print("[Test] show_org_info() populates Food/Wood storage labels")
	var panel := DebuggerOrgPanel.new()
	add_child(panel)
	panel.setup(["storage"])

	panel.show_org_info({"storage": {"Food": 12, "Wood": 7}})

	_assert(panel._food_label.text == "Food: 12", "Food label shows storage value (got: %s)" % panel._food_label.text)
	_assert(panel._wood_label.text == "Wood: 7", "Wood label shows storage value (got: %s)" % panel._wood_label.text)

	panel.queue_free()


func _test_role_market_row_format_with_and_without_pending() -> void:
	print("[Test] Role Market rows format as '<Role>: <holders>/<target>', appending '(+N pending)' only when pending > 0")
	var panel := DebuggerOrgPanel.new()
	add_child(panel)
	panel.setup(["role_market"])

	var info := {
		"role_counts": {"Explorer": 3, "Gatherer": 2},
		"cached_targets": {"Explorer": 4, "Gatherer": 2},
		"pending_requests": {"Explorer": 1, "Gatherer": 0},
	}
	panel.show_org_info(info)

	_assert(_role_market_texts(panel) == ["Explorer: 3/4 (+1 pending)", "Gatherer: 2/2"],
		"Role Market rows match expected format (got: %s)" % [_role_market_texts(panel)])

	panel.queue_free()


func _test_role_market_includes_unassigned() -> void:
	print("[Test] Role Market includes a row for Unassigned like any other role")
	var panel := DebuggerOrgPanel.new()
	add_child(panel)
	panel.setup(["role_market"])

	var info := {
		"role_counts": {"Gatherer": 2, "Unassigned": 3},
		"cached_targets": {"Gatherer": 2, "Unassigned": 1},
		"pending_requests": {"Gatherer": 0, "Unassigned": 0},
	}
	panel.show_org_info(info)

	_assert(_role_market_texts(panel) == ["Gatherer: 2/2", "Unassigned: 3/1"],
		"Role Market includes an Unassigned row (got: %s)" % [_role_market_texts(panel)])

	panel.queue_free()


func _test_show_org_info_rebuilds_role_market_rows_on_change() -> void:
	print("[Test] show_org_info() rebuilds Role Market rows to reflect new data on each call")
	var panel := DebuggerOrgPanel.new()
	add_child(panel)
	panel.setup(["role_market"])

	panel.show_org_info({
		"role_counts": {"Explorer": 1},
		"cached_targets": {"Explorer": 4},
		"pending_requests": {"Explorer": 3},
	})
	_assert(_role_market_texts(panel) == ["Explorer: 1/4 (+3 pending)"], "Initial row reflects first snapshot")

	panel.show_org_info({
		"role_counts": {"Explorer": 4},
		"cached_targets": {"Explorer": 4},
		"pending_requests": {"Explorer": 0},
	})
	_assert(_role_market_texts(panel) == ["Explorer: 4/4"],
		"Row updates to reflect the newer snapshot, no stale pending clause (got: %s)" % [_role_market_texts(panel)])

	panel.queue_free()


func _test_show_org_info_degrades_to_zero_empty_without_error() -> void:
	print("[Test] show_org_info() shows zero storage and no Role Market rows for the not-yet-wired OM snapshot, without erroring")
	var panel := DebuggerOrgPanel.new()
	add_child(panel)
	panel.setup(["storage", "role_market"])

	var info := {
		"storage": {"Food": 0, "Wood": 0},
		"role_counts": {},
		"cached_targets": {},
		"pending_requests": {},
	}
	panel.show_org_info(info)

	_assert(panel._food_label.text == "Food: 0", "Food label reads zero, not an error (got: %s)" % panel._food_label.text)
	_assert(panel._wood_label.text == "Wood: 0", "Wood label reads zero, not an error (got: %s)" % panel._wood_label.text)
	_assert(_role_market_texts(panel) == [], "Role Market shows no rows rather than erroring (got: %s)" % [_role_market_texts(panel)])

	panel.queue_free()


## Verifies the Organization tab exists in the running DebuggerUI shell (ticket
## 1's TabContainer) and houses a DebuggerOrgPanel, config-gated the same way
## as the Agent tab's inspector_sections.
func _test_organization_tab_present_in_debugger_ui() -> void:
	print("[Test] DebuggerUI's Organization tab houses a DebuggerOrgPanel built from org_sections")
	var config: Dictionary = ConfigLoader.load_dict("res://configs/ui/debugger.json")
	var debugger := _make_debugger()

	var tabs: TabContainer = debugger.get_node("Tabs")
	var org_index := -1
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == "Organization":
			org_index = i
			break

	_assert(org_index != -1, "A tab titled 'Organization' exists")
	if org_index != -1:
		var org_tab: Control = tabs.get_tab_control(org_index)
		_assert(debugger._org_panel.get_parent() == org_tab, "Org panel lives inside the Organization tab")
		_assert(debugger._org_panel._storage_fold != null, "Storage fold built (listed in org_sections)")
		_assert(debugger._org_panel._role_market_fold != null, "Role Market fold built (listed in org_sections)")
		_assert(config.get("org_sections", []) == ["storage", "role_market"],
			"org_sections config lists storage and role_market (got: %s)" % [config.get("org_sections", [])])

	debugger.queue_free()
	await get_tree().process_frame


## Boots Main.tscn (which wires the OM to a live Nest via Simulation) to
## confirm the Organization tab's data flows from the real OM snapshot at
## runtime, not just a mocked dict - mirroring test_debugger_ui_03's final
## full-scene boot test. The refresh tick is forced directly (rather than
## waited for via engine frame timing) for determinism, matching how ticket
## 03/05's timing tests drive _process() directly.
func _test_main_scene_boots_with_organization_tab_showing_live_om_state() -> void:
	print("[Test] Headless run of Main.tscn shows live storage in the Organization tab with no script errors")
	var om = get_node("/root/OrganizationManager")
	var main_scene: PackedScene = preload("res://Main.tscn")
	var main := main_scene.instantiate()
	add_child(main)

	for i in range(15):
		await get_tree().physics_frame

	var debugger: Control = main.get_node("DebuggerUI")
	_assert(debugger != null, "Main.tscn resolves a DebuggerUI child node")
	_assert(debugger._org_panel != null, "DebuggerUI built its Organization panel")

	debugger._update_timer = 0.0
	debugger._process(1.0)

	var info: Dictionary = om.get_debug_info()
	var storage: Dictionary = info.get("storage", {})
	_assert(debugger._org_panel._food_label.text == "Food: %s" % storage.get("Food", 0),
		"Org panel's Food label matches the live OM snapshot (got: %s)" % debugger._org_panel._food_label.text)
	_assert(debugger._org_panel._wood_label.text == "Wood: %s" % storage.get("Wood", 0),
		"Org panel's Wood label matches the live OM snapshot (got: %s)" % debugger._org_panel._wood_label.text)

	main.queue_free()
	await get_tree().physics_frame
