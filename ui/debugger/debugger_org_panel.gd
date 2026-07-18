class_name DebuggerOrgPanel
extends VBoxContainer

const SECTION_TITLES := {
	"storage": "Storage",
	"role_market": "Role Market",
}

var _sections: Array = []
var _text_color: Color = Color("#e0e0e0")
var _panel_color: Color = Color("#2d2d2d")
var _accent_color: Color = Color("#4ec9b0")

var _storage_fold: FoldableContainer
var _food_label: Label
var _wood_label: Label

var _role_market_fold: FoldableContainer
var _role_market_list: VBoxContainer


## Builds the section list from config; call once at startup. `colors` is the
## debugger config's colors block, reused so this panel matches the Agent
## tab's dark styling. Storage and Role Market both start expanded - hardcoded
## per the org-overlay spec (no evidence anyone needs to tune it per run), not
## config-driven like `sections` itself.
func setup(sections: Array, colors: Dictionary = {}) -> void:
	_sections = sections
	_text_color = Color(colors.get("text", "#e0e0e0"))
	_panel_color = Color(colors.get("panel", "#2d2d2d"))
	_accent_color = Color(colors.get("accent", "#4ec9b0"))

	_storage_fold = null
	_food_label = null
	_wood_label = null
	_role_market_fold = null
	_role_market_list = null
	for child in get_children():
		child.free()

	for key in _sections:
		match key:
			"storage":
				add_child(_build_storage_section())
			"role_market":
				add_child(_build_role_market_section())


func _make_fold(key: String) -> FoldableContainer:
	var fold := FoldableContainer.new()
	fold.title = SECTION_TITLES.get(key, String(key).capitalize())
	fold.folded = false
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


func _build_storage_section() -> FoldableContainer:
	_storage_fold = _make_fold("storage")
	var box := VBoxContainer.new()
	_food_label = _label()
	_wood_label = _label()
	box.add_child(_food_label)
	box.add_child(_wood_label)
	_storage_fold.add_child(box)
	return _storage_fold


func _build_role_market_section() -> FoldableContainer:
	_role_market_fold = _make_fold("role_market")
	_role_market_list = VBoxContainer.new()
	_role_market_fold.add_child(_role_market_list)
	return _role_market_fold


## Populates Storage and Role Market from OrganizationManager.get_debug_info()'s
## snapshot. The role list rebuilds every refresh - unlike the Log tab's
## unbounded history, the role set is small and fixed-size per run, so there's
## no rebuild-avoidance need here.
func show_org_info(info: Dictionary) -> void:
	if _food_label:
		var storage: Dictionary = info.get("storage", {})
		_food_label.text = "Food: %s" % storage.get("Food", 0)
		_wood_label.text = "Wood: %s" % storage.get("Wood", 0)
	if _role_market_list:
		_set_role_market_rows(info)


func _set_role_market_rows(info: Dictionary) -> void:
	for child in _role_market_list.get_children():
		child.free()

	var role_counts: Dictionary = info.get("role_counts", {})
	var cached_targets: Dictionary = info.get("cached_targets", {})
	var pending_requests: Dictionary = info.get("pending_requests", {})

	for role_name in role_counts.keys():
		var holders: int = role_counts.get(role_name, 0)
		var target: int = cached_targets.get(role_name, 0)
		var pending: int = pending_requests.get(role_name, 0)
		var text := "%s: %d/%d" % [role_name, holders, target]
		if pending > 0:
			text += " (+%d pending)" % pending
		_role_market_list.add_child(_label(text))
