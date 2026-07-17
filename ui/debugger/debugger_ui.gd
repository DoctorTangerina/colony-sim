class_name DebuggerUI
extends Control

const CONFIG_PATH := "res://configs/ui/debugger.json"
const ROLE_CONFIG_DIR := "res://configs/roles"

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

var _tree: Tree
var _tree_root: TreeItem
var _agent_items: Dictionary = {}

@onready var _om: Node = get_node("/root/OrganizationManager")


func _ready() -> void:
	var config: Dictionary = ConfigLoader.load_dict(CONFIG_PATH)
	_apply_layout(config)
	_load_role_colors(config)
	_build_tree(config)
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
	background.color = _config_color(colors, "background", "#1e1e1e")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_default_role_color = _config_color(colors, "text_dim", "#888888")


func _config_color(colors: Dictionary, key: String, default_hex: String) -> Color:
	return Color(colors.get(key, default_hex))


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


func _build_tree(config: Dictionary) -> void:
	_columns = config.get("tree_columns", ["agent_id", "role", "action"])
	var colors: Dictionary = config.get("colors", {})

	_tree = Tree.new()
	_tree.name = "AgentTree"
	_tree.set_anchors_preset(Control.PRESET_FULL_RECT)
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

	add_child(_tree)
	_tree_root = _tree.create_item()


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < _update_interval:
		return
	_update_timer = 0.0
	_refresh_all_rows()


func _refresh_all_rows() -> void:
	for agent_id in _agent_items.keys():
		var node: Node = _om.get_agent_node(agent_id)
		if node == null:
			continue
		_update_row(_agent_items[agent_id], node.get_debug_info())


func _on_agent_registered(agent_id: String, role: String) -> void:
	if _agent_items.has(agent_id):
		return
	var item: TreeItem = _tree.create_item(_tree_root)
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


func _update_row(item: TreeItem, info: Dictionary) -> void:
	for i in range(_columns.size()):
		var key: String = _columns[i]
		var info_key: String = "executing_action" if key == "action" else key
		var value: String = str(info.get(info_key, ""))
		item.set_text(i, value)
		if key == "role":
			item.set_custom_color(i, _role_colors.get(value, _default_role_color))
