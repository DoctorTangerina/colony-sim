class_name DebuggerSettingsPanel
extends VBoxContainer

var _text_color: Color = Color("#e0e0e0")

var _dynamic_roles_label: Label
var _role_cooldown_label: Label
var _min_unassigned_label: Label


## Builds the read-only settings rows; call once at startup. `colors` is the
## debugger config's colors block, reused so this panel matches the rest of
## the panel's dark styling. No fold wrapper - the Settings tab itself is the
## section boundary, per the org-overlay spec. Renders default-value rows
## immediately so the tab is never blank before the panel's first refresh.
func setup(colors: Dictionary = {}) -> void:
	_text_color = Color(colors.get("text", "#e0e0e0"))

	for child in get_children():
		child.free()

	_dynamic_roles_label = _label()
	_role_cooldown_label = _label()
	_min_unassigned_label = _label()
	add_child(_dynamic_roles_label)
	add_child(_role_cooldown_label)
	add_child(_min_unassigned_label)

	show_settings_info({})


func _label(text: String = "") -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", _text_color)
	return lbl


## Populates the role market's live runtime knobs from
## OrganizationManager.get_debug_info()'s snapshot - read-only display, no
## controls here ever change the underlying settings.
func show_settings_info(info: Dictionary) -> void:
	_dynamic_roles_label.text = "Dynamic Roles Enabled: %s" % info.get("dynamic_roles_enabled", false)
	_role_cooldown_label.text = "Role Cooldown: %.1fs" % info.get("role_cooldown", 0.0)
	_min_unassigned_label.text = "Min Unassigned Threshold: %d" % info.get("min_unassigned_threshold", 0)
