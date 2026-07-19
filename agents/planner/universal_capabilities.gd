class_name UniversalCapabilities
extends Node

## Registration point for goals/actions available to every role automatically,
## bypassing allowedGoals/allowedActions entirely (CONTEXT.md: Universal
## Capability; ADR 8). GoTo is registered here as of Ticket 2 (a role without
## it could satisfy zero location-based preconditions, ever, under honest
## atomic actions). ReportDiscovery/ReportResource are registered as of
## Ticket 5 - passive discovery scanning (agent.gd's _scan_for_discovery)
## already runs role-blind for every agent, so any non-Explorer role that
## incidentally captures a discovery into its carry-slot must also be able
## to clear it, or that slot jams permanently. Idle is registered as of
## Ticket 6 - the always-relevant, lowest-priority fallback every role
## (assigned or Unassigned) falls into once nothing else is relevant;
## role-gating it would reproduce the exact "stands frozen forever" gap it
## exists to close.
const GOALS: Array = ["ReportDiscovery", "Idle"]
const ACTIONS: Array = [GoapActions.GOTO, GoapActions.REPORT_RESOURCE, GoapActions.IDLE]


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
