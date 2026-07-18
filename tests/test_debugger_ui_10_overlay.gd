extends Node

var tests_passed: int = 0
var tests_failed: int = 0


func _ready() -> void:
	print("=== Debugger UI Ticket 10 Test Harness (Overlay: CanvasLayer, Toggle, Translucency) ===")
	print("")

	_test_toggle_debugger_action_bound_to_f1()
	_test_toggle_visibility_flips_visible_flag()
	_test_background_alpha_translucent_foreground_opaque()
	_test_f1_key_event_toggles_panel_via_unhandled_input()

	await _test_main_scene_wraps_debugger_ui_in_canvas_layer()

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


func _test_toggle_debugger_action_bound_to_f1() -> void:
	print("[Test] toggle_debugger InputMap action exists, bound to F1")
	_assert(InputMap.has_action("toggle_debugger"), "InputMap has a 'toggle_debugger' action")

	var bound_to_f1 := false
	for event in InputMap.action_get_events("toggle_debugger"):
		if event is InputEventKey and (event.physical_keycode == KEY_F1 or event.keycode == KEY_F1):
			bound_to_f1 = true
	_assert(bound_to_f1, "toggle_debugger is bound to an F1 key event")


func _test_toggle_visibility_flips_visible_flag() -> void:
	print("[Test] toggle_visibility() flips the panel's visible flag, callable directly")
	var debugger := _make_debugger()

	_assert(debugger.visible == true, "Panel starts visible")
	debugger.toggle_visibility()
	_assert(debugger.visible == false, "First call hides the panel")
	debugger.toggle_visibility()
	_assert(debugger.visible == true, "Second call shows the panel again")

	debugger.queue_free()


func _test_background_alpha_translucent_foreground_opaque() -> void:
	print("[Test] Outer background renders at alpha 0.85; foreground content stays alpha 1.0")
	var debugger := _make_debugger()

	var background: ColorRect = debugger.get_node("Background")
	_assert(is_equal_approx(background.color.a, 0.85), "Background alpha is 0.85 (got: %s)" % background.color.a)

	var tree_panel_style: StyleBox = debugger._tree.get_theme_stylebox("panel")
	_assert(is_equal_approx(tree_panel_style.bg_color.a, 1.0), "Agent tree panel stylebox stays alpha 1.0 (got: %s)" % tree_panel_style.bg_color.a)

	debugger.queue_free()


func _test_f1_key_event_toggles_panel_via_unhandled_input() -> void:
	print("[Test] An F1 InputEventKey routed through _unhandled_input() toggles the panel")
	var debugger := _make_debugger()

	var event := InputEventKey.new()
	event.physical_keycode = KEY_F1
	event.pressed = true
	_assert(event.is_action_pressed("toggle_debugger"), "F1 key event resolves to the toggle_debugger action")

	_assert(debugger.visible == true, "Panel starts visible")
	debugger._unhandled_input(event)
	_assert(debugger.visible == false, "Panel hides after the F1 event is handled")

	debugger.queue_free()


## Mirrors test_debugger_ui_03's full-scene boot pattern; this is the one
## assertion the standalone DebuggerUI harness above cannot cover, since the
## CanvasLayer wiring lives in Main.tscn, not debugger_ui.tscn (ADR 4).
func _test_main_scene_wraps_debugger_ui_in_canvas_layer() -> void:
	print("[Test] Headless run of Main.tscn wraps DebuggerUI in a CanvasLayer")
	var main_scene: PackedScene = preload("res://Main.tscn")
	var main := main_scene.instantiate()
	add_child(main)

	for i in range(15):
		await get_tree().physics_frame

	var debugger: Control = main.get_node("DebuggerLayer/DebuggerUI")
	_assert(debugger != null, "Main.tscn resolves a DebuggerUI node")
	_assert(debugger.get_parent() is CanvasLayer, "DebuggerUI's parent is a CanvasLayer")

	main.queue_free()
	await get_tree().physics_frame
