class_name GoapUtils
extends Node


static func state_satisfies(state: Dictionary, preconditions: Dictionary) -> bool:
	for key in preconditions:
		if not state.has(key) or state[key] != preconditions[key]:
			return false
	return true


static func merge_states(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var result := base.duplicate()
	for key in overrides:
		result[key] = overrides[key]
	return result
