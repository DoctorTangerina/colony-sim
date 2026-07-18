class_name UniversalCapabilities
extends Node

## Registration point for goals/actions available to every role automatically,
## bypassing allowedGoals/allowedActions entirely (CONTEXT.md: Universal
## Capability; ADR 8). GoTo is registered here as of Ticket 2 (a role without
## it could satisfy zero location-based preconditions, ever, under honest
## atomic actions); Idle and ReportDiscovery are registered by later tickets.
const GOALS: Array = []
const ACTIONS: Array = [GoapActions.GOTO]


static func is_universal_goal(goal_name: String) -> bool:
	return goal_name in GOALS


## Entries in ACTIONS are exact matches for ungrounded actions, or base names
## for grounded families like GoTo - the concrete instance always carries a
## "[Kind]" suffix (e.g. "GoTo[Nest]"), matched here via prefix instead of
## hand-listing every ground instance too.
static func is_universal_action(action_name: String) -> bool:
	if action_name in ACTIONS:
		return true
	for base in ACTIONS:
		if action_name.begins_with(base + "["):
			return true
	return false
