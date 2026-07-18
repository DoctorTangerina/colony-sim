class_name UniversalCapabilities
extends Node

## Registration point for goals/actions available to every role automatically,
## bypassing allowedGoals/allowedActions entirely (CONTEXT.md: Universal
## Capability; ADR 8). Empty until a later ticket registers GoTo, Idle, and
## ReportDiscovery here - nothing is universal yet.
const GOALS: Array = []
const ACTIONS: Array = []


static func is_universal_goal(goal_name: String) -> bool:
	return goal_name in GOALS


static func is_universal_action(action_name: String) -> bool:
	return action_name in ACTIONS
