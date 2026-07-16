class_name ConfigLoader
extends Node


static func load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ConfigLoader: Could not open file: %s" % path)
		return null
	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("ConfigLoader: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	return json.data


static func load_dict(path: String) -> Dictionary:
	var data = load_json(path)
	if data is Dictionary:
		return data
	return {}


static func load_array(path: String) -> Array:
	var data = load_json(path)
	if data is Array:
		return data
	return []
