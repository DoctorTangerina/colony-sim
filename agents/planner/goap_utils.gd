class_name GoapUtils
extends Node


static func state_satisfies(state: WorldState, preconditions: Dictionary) -> bool:
	return state.satisfies(preconditions)


static func merge_states(base: WorldState, overrides: Dictionary) -> WorldState:
	return base.merge(overrides)