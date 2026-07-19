class_name GetResourceGrounding
extends Node

## Grounds the single generic GetResource action (SPEC.md
## .scratch/survival-loop Ticket 03) into one concrete Action dict per
## resource kind, mirroring GotoGrounding's shape exactly. Kinds are never
## hand-listed: they come from the resource registry (configs/resources.json)
## - adding a resource kind there is enough to make GetResource able to
## withdraw it, with no second kind list to keep in sync. Unlike GoTo, this
## family is not a Universal Capability (ADR 8) - Gatherer's role config
## lists the concrete grounded instance names directly.
##
## A kind only becomes a real, planner-usable GetResource variant once
## WorldState has a has_<kind> Sensed Fact field to hold its effect - same
## known_fields guard as GotoGrounding.build_actions, for the same reason.

const GET_RESOURCE_ACTION_COST: float = 1.0


static func effect_field(kind: String) -> String:
	return "has_%s" % kind.to_lower()


static func action_name(kind: String) -> String:
	return "%s[%s]" % [GoapActions.GET_RESOURCE, kind]


## known_fields is WorldState's current schema (WorldState.new().get_field_keys())
## - passed in rather than referenced directly so this stays testable with a
## fabricated schema without touching the real WorldState class.
static func build_actions(resource_kinds: Array, known_fields: Array) -> Array:
	var actions: Array = []
	for kind in resource_kinds:
		var field := effect_field(kind)
		if field not in known_fields:
			continue
		actions.append({
			"name": action_name(kind),
			"cost": GET_RESOURCE_ACTION_COST,
			"preconditions": {"has_item": false, "at_nest": true},
			"effects": {field: true}
		})
	return actions
