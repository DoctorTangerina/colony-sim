static func load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	var text = file.get_as_text()
	return JSON.parse_string(text)
