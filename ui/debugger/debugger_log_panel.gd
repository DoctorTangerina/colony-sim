class_name DebuggerLogPanel
extends ScrollContainer

const EMPTY_STATE_TEXT := "(no role changes yet)"

var _text_color: Color = Color("#e0e0e0")
var _log_list: VBoxContainer
var _last_log_length: int = -1


## Builds the scrollable row list; call once at startup. `colors` is the
## debugger config's colors block, reused so log rows match the rest of the
## panel's dark styling. No fold wrapper here - the Log tab itself is the
## section boundary. Renders the empty-state row immediately so the tab is
## never blank before the panel's first refresh tick.
func setup(colors: Dictionary = {}) -> void:
	_text_color = Color(colors.get("text", "#e0e0e0"))

	if _log_list:
		_log_list.free()
	_log_list = VBoxContainer.new()
	_log_list.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(_log_list)

	_last_log_length = -1
	_rebuild_rows([])


func _label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", _text_color)
	return lbl


## Rebuilds the row list only when the log's length has changed since the
## last refresh - the log is unbounded for a whole run, so rebuilding a large
## Label list at the panel's refresh rate regardless of change would be
## wasted work.
func show_log_info(log: Array) -> void:
	if log.size() == _last_log_length:
		return
	_last_log_length = log.size()
	_rebuild_rows(log)


func _rebuild_rows(log: Array) -> void:
	for child in _log_list.get_children():
		child.free()

	if log.is_empty():
		_log_list.add_child(_label(EMPTY_STATE_TEXT))
		return

	for i in range(log.size() - 1, -1, -1):
		_log_list.add_child(_label(_format_entry(log[i])))


func _format_entry(entry: Dictionary) -> String:
	return "[%.1fs] %s: %s → %s" % [
		entry.get("timestamp", 0.0),
		entry.get("agent_id", ""),
		entry.get("old_role", ""),
		entry.get("new_role", ""),
	]
