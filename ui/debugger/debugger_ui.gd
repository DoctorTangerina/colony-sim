class_name DebuggerUI
extends Control

const CONFIG_PATH := "res://configs/ui/debugger.json"
const ROLE_CONFIG_DIR := "res://configs/roles"
const TREE_BOTTOM_FRACTION := 0.5

## Backdrop-only translucency (ADR 4 / org-overlay spec) - text, fold
## styleboxes, and every other panel element stay fully opaque so nothing
## becomes hard to read; only the outer background dims to sense sim activity
## behind the panel. Hardcoded, not config-driven - nothing else needs it.
const BACKGROUND_ALPHA := 0.85

const COLUMN_TITLES := {
	"agent_id": "Agent ID",
	"role": "Role",
	"action": "Action",
}

var _columns: Array = []
var _update_interval: float = 0.2
var _update_timer: float = 0.0
var _role_colors: Dictionary = {}
var _default_role_color: Color = Color("#888888")

var _tabs: TabContainer
var _agent_tab: Control

var _tree: Tree
var _tree_root: TreeItem
var _agent_items: Dictionary = {}

var _inspector: DebuggerInspector
var _selected_agent_id: String = ""

var _org_panel: DebuggerOrgPanel

var _log_panel: DebuggerLogPanel

var _settings_panel: DebuggerSettingsPanel

@onready var _om: Node = get_node("/root/OrganizationManager")


func _ready() -> void:
	var config: Dictionary = ConfigLoader.load_dict(CONFIG_PATH)
	_apply_layout(config)
	_load_role_colors(config)
	_build_tabs()
	_build_tree(config)
	_build_inspector(config)
	_build_organization_tab(config)
	_build_log_tab(config)
	_build_settings_tab(config)
	_update_interval = 1.0 / maxf(config.get("update_hz", 5.0), 0.001)

	_om.agent_registered.connect(_on_agent_registered)
	_om.agent_unregistered.connect(_on_agent_unregistered)

	# Scene tree ready-order isn't guaranteed relative to sibling nodes, so
	# agents may already be registered by the time this panel boots; back
	# them in rather than relying solely on future agent_registered signals.
	for agent_id in _om.get_registered_agent_ids():
		_on_agent_registered(agent_id, "")


func _apply_layout(config: Dictionary) -> void:
	var panel_width: float = config.get("panel_width", 450)
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -panel_width
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var colors: Dictionary = config.get("colors", {})
	var background := ColorRect.new()
	background.name = "Background"
	var background_color := _config_color(colors, "background", "#1e1e1e")
	background_color.a = BACKGROUND_ALPHA
	background.color = background_color
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_default_role_color = _config_color(colors, "text_dim", "#888888")


func _config_color(colors: Dictionary, key: String, default_hex: String) -> Color:
	return Color(colors.get(key, default_hex))


## Anchors a control to a horizontal band of the panel (full width, top..bottom
## as anchor fractions), used to stack the tree above the inspector.
func _anchor_band(control: Control, top: float, bottom: float) -> void:
	control.anchor_left = 0.0
	control.anchor_top = top
	control.anchor_right = 1.0
	control.anchor_bottom = bottom
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


## Role colors come from configs/roles/*.json so a new role with a color
## needs no code change; the debugger config's own role_colors map (if any)
## is loaded first and can still be overridden per-role by the role JSON.
func _load_role_colors(config: Dictionary) -> void:
	_role_colors = {}
	var configured: Dictionary = config.get("colors", {}).get("role_colors", {})
	for role_name in configured.keys():
		_role_colors[role_name] = Color(configured[role_name])

	var dir := DirAccess.open(ROLE_CONFIG_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data: Dictionary = ConfigLoader.load_dict("%s/%s" % [ROLE_CONFIG_DIR, file_name])
			var role_name: String = data.get("name", "")
			if not role_name.is_empty() and data.has("color"):
				_role_colors[role_name] = Color(data["color"])
		file_name = dir.get_next()
	dir.list_dir_end()


## The Agent tab is today's only tab - the Tree + Inspector move inside it
## unchanged, so future tabs (Organization/Log/Settings) plug in as siblings
## without touching this one's internals.
func _build_tabs() -> void:
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tabs)

	_agent_tab = Control.new()
	_agent_tab.name = "Agent"
	_agent_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tabs.add_child(_agent_tab)
	_tabs.set_tab_title(0, "Agent")


func _build_tree(config: Dictionary) -> void:
	_columns = config.get("tree_columns", ["agent_id", "role", "action"])
	var colors: Dictionary = config.get("colors", {})

	_tree = Tree.new()
	_tree.name = "AgentTree"
	_anchor_band(_tree, 0.0, TREE_BOTTOM_FRACTION)
	_tree.columns = _columns.size()
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.add_theme_color_override("font_color", _config_color(colors, "text", "#e0e0e0"))
	_tree.add_theme_color_override("title_button_color", _config_color(colors, "accent", "#4ec9b0"))

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _config_color(colors, "panel", "#2d2d2d")
	_tree.add_theme_stylebox_override("panel", panel_style)

	for i in range(_columns.size()):
		_tree.set_column_title(i, COLUMN_TITLES.get(_columns[i], String(_columns[i]).capitalize()))

	# Selection is the only trigger for the inspector - no keyboard shortcuts
	# are wired anywhere in this panel, per the mouse/touch-only requirement.
	_tree.item_selected.connect(_on_tree_item_selected)

	_agent_tab.add_child(_tree)
	_tree_root = _tree.create_item()


func _build_inspector(config: Dictionary) -> void:
	var sections: Array = config.get("inspector_sections", ["role", "goal", "stats", "action"])
	_inspector = DebuggerInspector.new()
	_inspector.name = "Inspector"
	_anchor_band(_inspector, TREE_BOTTOM_FRACTION, 1.0)
	_agent_tab.add_child(_inspector)
	_inspector.setup(sections, config.get("colors", {}), config.get("plan_expanded_by_default", false))


## The Organization tab sources everything from a single
## OrganizationManager.get_debug_info() snapshot (ticket 2) - no separate Nest
## query needed. Sections are config-gated by org_sections, mirroring how
## inspector_sections gates the Agent tab.
func _build_organization_tab(config: Dictionary) -> void:
	var org_tab := Control.new()
	org_tab.name = "Organization"
	org_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tabs.add_child(org_tab)
	_tabs.set_tab_title(1, "Organization")

	var sections: Array = config.get("org_sections", ["storage", "role_market"])
	_org_panel = DebuggerOrgPanel.new()
	_org_panel.name = "OrgPanel"
	_org_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	org_tab.add_child(_org_panel)
	_org_panel.setup(sections, config.get("colors", {}))


## The Log tab has no fold wrapper (the tab itself is the section boundary,
## per the org-overlay spec) and no config gating - unlike the Organization
## tab's sections, there's nothing to opt in or out of here.
func _build_log_tab(config: Dictionary) -> void:
	var log_tab := Control.new()
	log_tab.name = "Log"
	log_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tabs.add_child(log_tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "Log")

	_log_panel = DebuggerLogPanel.new()
	_log_panel.name = "LogPanel"
	_log_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_tab.add_child(_log_panel)
	_log_panel.setup(config.get("colors", {}))


## The Settings tab has no fold wrapper (same rationale as Log) and no config
## gating - unlike Organization's sections, there's nothing to opt in or out
## of for a fixed set of three read-only knobs.
func _build_settings_tab(config: Dictionary) -> void:
	var settings_tab := Control.new()
	settings_tab.name = "Settings"
	settings_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tabs.add_child(settings_tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "Settings")

	_settings_panel = DebuggerSettingsPanel.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_tab.add_child(_settings_panel)
	_settings_panel.setup(config.get("colors", {}))


## The testable seam for the F1 overlay toggle (ADR 4) - _unhandled_input
## calls this rather than embedding the visibility flip inline, so the
## behavior is exercisable directly in headless tests without simulating a
## physical key event.
func toggle_visibility() -> void:
	visible = not visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debugger"):
		toggle_visibility()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < _update_interval:
		return
	_update_timer = 0.0
	_refresh_all_rows()
	_refresh_inspector()
	_refresh_organization_state()


func _refresh_all_rows() -> void:
	for agent_id in _agent_items.keys():
		var node: Node = _om.get_agent_node(agent_id)
		if node == null:
			continue
		_update_row(_agent_items[agent_id], node.get_debug_info())


func _refresh_inspector() -> void:
	if _selected_agent_id.is_empty():
		return
	var node: Node = _om.get_agent_node(_selected_agent_id)
	if node == null:
		return
	var info: Dictionary = node.get_debug_info()
	_inspector.show_agent_info(info, _role_colors.get(info.get("role", ""), _default_role_color))


## Ticket 2's single OM snapshot backs the Organization, Log, and Settings
## tabs, so a refresh tick never queries the OM twice for the same data.
func _refresh_organization_state() -> void:
	var info: Dictionary = _om.get_debug_info()
	_org_panel.show_org_info(info)
	_log_panel.show_log_info(info.get("role_change_log", []))
	_settings_panel.show_settings_info(info)


func _on_tree_item_selected() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	_selected_agent_id = str(item.get_metadata(0))
	_refresh_inspector()


func _on_agent_registered(agent_id: String, role: String) -> void:
	if _agent_items.has(agent_id):
		return
	var item: TreeItem = _tree.create_item(_tree_root)
	item.set_metadata(0, agent_id)
	_agent_items[agent_id] = item

	var node: Node = _om.get_agent_node(agent_id)
	if node != null:
		_update_row(item, node.get_debug_info())
	else:
		_update_row(item, {"agent_id": agent_id, "role": role, "executing_action": ""})


func _on_agent_unregistered(agent_id: String) -> void:
	var item: TreeItem = _agent_items.get(agent_id)
	if item == null:
		return
	item.free()
	_agent_items.erase(agent_id)

	if agent_id == _selected_agent_id:
		_selected_agent_id = ""
		_inspector.clear()


func _update_row(item: TreeItem, info: Dictionary) -> void:
	for i in range(_columns.size()):
		var key: String = _columns[i]
		var info_key: String = "executing_action" if key == "action" else key
		var value: String = str(info.get(info_key, ""))
		item.set_text(i, value)
		if key == "role":
			item.set_custom_color(i, _role_colors.get(value, _default_role_color))
