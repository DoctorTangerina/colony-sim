class_name BlackboardSync
extends Node

## Single source of truth for building the known-position dict (keyed by
## resource type, e.g. "Food"/"Wood") from a colony Blackboard, filtered to
## entries a ResourceManager confirms still exist. Used by
## agent.gd:_build_world_state() so the Blackboard->known-positions mapping
## lives in exactly one place.

static func sync_known_positions(blackboard: Node, resource_manager: Node) -> Dictionary:
	var known_positions: Dictionary = {}
	for res_type in ["Food", "Wood"]:
		var entries: Array[Dictionary] = blackboard.get_entries(res_type)
		for entry in entries:
			var entry_pos: Vector2 = entry["position"]
			if resource_manager.resource_exists_at(res_type, entry_pos):
				known_positions[res_type] = known_positions.get(res_type, [])
				known_positions[res_type].append(entry_pos)
	return known_positions
