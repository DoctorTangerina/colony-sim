class_name Blackboard
extends Node

signal entries_changed(entries: Array[Dictionary])

var _entries: Array[Dictionary] = []

const DEDUP_TOLERANCE: float = 10.0
const STALE_CHECK_RADIUS: float = 50.0


func add_entry(resource_type: String, position: Vector2) -> bool:
	for e in _entries:
		if e["type"] == resource_type and e["position"].distance_to(position) < DEDUP_TOLERANCE:
			return false
	_entries.append({"type": resource_type, "position": position, "timestamp": Time.get_ticks_msec()})
	entries_changed.emit(_entries)
	return true


func get_entries(resource_type: String = "") -> Array[Dictionary]:
	if resource_type.is_empty():
		return _entries.duplicate()
	var result: Array[Dictionary] = []
	for e in _entries:
		if e["type"] == resource_type:
			result.append(e)
	return result


func remove_entries(resource_type: String = "", position: Vector2 = Vector2.ZERO) -> int:
	var to_remove: Array[Dictionary] = []
	for e in _entries:
		var matches_type: bool = resource_type.is_empty() or e["type"] == resource_type
		var matches_pos: bool = position == Vector2.ZERO or e["position"].distance_to(position) < DEDUP_TOLERANCE
		if matches_type and matches_pos:
			to_remove.append(e)
	for entry in to_remove:
		_entries.erase(entry)
	if to_remove.size() > 0:
		entries_changed.emit(_entries)
	return to_remove.size()


func has_entry_at(resource_type: String, position: Vector2) -> bool:
	for e in _entries:
		if e["type"] == resource_type and e["position"].distance_to(position) < DEDUP_TOLERANCE:
			return true
	return false


func clean_stale_entries(resource_manager: Node) -> int:
	var to_remove: Array[Dictionary] = []
	for e in _entries:
		var res_type: String = e["type"]
		var pos: Vector2 = e["position"]
		var found := false
		if resource_manager.has_method("get_all_resources"):
			for node in resource_manager.get_all_resources():
				if is_instance_valid(node) and node.resource_type == res_type and node.global_position.distance_to(pos) < STALE_CHECK_RADIUS:
					found = true
					break
		if not found:
			to_remove.append(e)
	for entry in to_remove:
		_entries.erase(entry)
	if to_remove.size() > 0:
		entries_changed.emit(_entries)
	return to_remove.size()


func get_entry_count() -> int:
	return _entries.size()
