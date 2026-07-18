class_name DebuggerInspector
extends VBoxContainer

const SECTION_TITLES := {
	"role": "Role Info",
	"goal": "Active Goal",
	"stats": "Agent Stats",
	"action": "Executing Action",
	"plan": "Plan",
}

var _sections: Array = []
var _text_color: Color = Color("#e0e0e0")
var _panel_color: Color = Color("#2d2d2d")
var _accent_color: Color = Color("#4ec9b0")

var _role_swatch: ColorRect
var _role_label: Label
var _goal_label: Label
var _energy_bar: ProgressBar
var _energy_label: Label
var _hunger_bar: ProgressBar
var _hunger_label: Label
var _action_label: Label

var _plan_fold: FoldableContainer
var _plan_list: VBoxContainer
var _plan_expanded_by_default: bool = false


## Builds the section list from config; call once at startup. `colors` is the
## debugger config's colors block, reused so the inspector matches the tree's
## dark styling instead of Godot's default theme. `plan_expanded_by_default`
## controls the Plan section's initial folded state.
func setup(sections: Array, colors: Dictionary = {}, plan_expanded_by_default: bool = false) -> void:
	_sections = sections
	_text_color = Color(colors.get("text", "#e0e0e0"))
	_panel_color = Color(colors.get("panel", "#2d2d2d"))
	_accent_color = Color(colors.get("accent", "#4ec9b0"))
	_plan_expanded_by_default = plan_expanded_by_default

	_role_swatch = null
	_role_label = null
	_goal_label = null
	_energy_bar = null
	_energy_label = null
	_hunger_bar = null
	_hunger_label = null
	_action_label = null
	_plan_fold = null
	_plan_list = null
	for child in get_children():
		child.free()

	for key in _sections:
		match key:
			"role":
				add_child(_build_role_section())
			"goal":
				add_child(_build_goal_section())
			"stats":
				add_child(_build_stats_section())
			"action":
				add_child(_build_action_section())
			"plan":
				add_child(_build_plan_section())

	clear()


func _make_fold(key: String) -> FoldableContainer:
	var fold := FoldableContainer.new()
	fold.title = SECTION_TITLES.get(key, String(key).capitalize())
	fold.add_theme_color_override("font_color", _accent_color)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _panel_color
	fold.add_theme_stylebox_override("panel", panel_style)
	return fold


func _label(text: String = "") -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", _text_color)
	return lbl


func _build_role_section() -> FoldableContainer:
	var fold := _make_fold("role")
	var row := HBoxContainer.new()
	_role_swatch = ColorRect.new()
	_role_swatch.custom_minimum_size = Vector2(16, 16)
	_role_label = _label()
	row.add_child(_role_swatch)
	row.add_child(_role_label)
	fold.add_child(row)
	return fold


func _build_goal_section() -> FoldableContainer:
	var fold := _make_fold("goal")
	_goal_label = _label()
	fold.add_child(_goal_label)
	return fold


func _build_stats_section() -> FoldableContainer:
	var fold := _make_fold("stats")
	var box := VBoxContainer.new()

	_energy_label = _label()
	_energy_bar = ProgressBar.new()
	_energy_bar.min_value = 0
	_energy_bar.max_value = 100
	box.add_child(_energy_label)
	box.add_child(_energy_bar)

	_hunger_label = _label()
	_hunger_bar = ProgressBar.new()
	_hunger_bar.min_value = 0
	_hunger_bar.max_value = 100
	box.add_child(_hunger_label)
	box.add_child(_hunger_bar)

	fold.add_child(box)
	return fold


func _build_action_section() -> FoldableContainer:
	var fold := _make_fold("action")
	_action_label = _label()
	fold.add_child(_action_label)
	return fold


func _build_plan_section() -> FoldableContainer:
	_plan_fold = _make_fold("plan")
	_plan_fold.folded = not _plan_expanded_by_default
	_plan_list = VBoxContainer.new()
	_plan_fold.add_child(_plan_list)
	return _plan_fold


## Populates the built sections for the selected agent. role_color comes from
## the caller (DebuggerUI already resolves configs/roles/*.json colors for the
## tree) since Agent.get_debug_info() carries the role name only, not its color.
func show_agent_info(info: Dictionary, role_color: Color) -> void:
	if _role_label:
		_role_label.text = str(info.get("role", ""))
		_role_swatch.color = role_color
	if _goal_label:
		_goal_label.text = str(info.get("active_goal", ""))
	if _energy_bar:
		var energy: float = info.get("energy", 0.0)
		_energy_bar.value = energy
		_energy_label.text = "Energy: %.1f" % energy
	if _hunger_bar:
		var hunger: float = info.get("hunger", 0.0)
		_hunger_bar.value = hunger
		_hunger_label.text = "Hunger: %.1f" % hunger
	if _action_label:
		_action_label.text = str(info.get("executing_action", ""))
	if _plan_list:
		_set_plan(info.get("plan", []))


## Rebuilds the plan list from scratch each refresh - plans are short (a
## handful of actions) so this is cheaper than diffing against the old list.
## An empty plan shows an explicit placeholder rather than an empty section,
## since a section with no visible content reads as "not refreshed yet".
func _set_plan(plan: Array) -> void:
	for child in _plan_list.get_children():
		child.free()
	if plan.is_empty():
		_plan_list.add_child(_label("(no plan)"))
		return
	for action_name in plan:
		_plan_list.add_child(_label(str(action_name)))


## Called when no agent is selected, or the selected agent unregisters - resets
## fields to empty rather than leaving stale values on screen.
func clear() -> void:
	if _role_label:
		_role_label.text = ""
		_role_swatch.color = Color.TRANSPARENT
	if _goal_label:
		_goal_label.text = ""
	if _energy_bar:
		_energy_bar.value = 0
		_energy_label.text = ""
	if _hunger_bar:
		_hunger_bar.value = 0
		_hunger_label.text = ""
	if _action_label:
		_action_label.text = ""
	if _plan_list:
		_set_plan([])
