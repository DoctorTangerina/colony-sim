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


## Gates the action on the Nest actually holding stock (WorldState's
## food_stored/wood_stored) - without this, the action's declared effect
## (has_<kind>:true) isn't honest: Nest.withdraw() only succeeds when stock is
## nonzero, but the preconditions used to say otherwise, so the forward-search
## planner treated withdrawal as always achievable at cost 1.0 and never
## explored the pricier-but-real GoTo[Kind]->Pickup<Kind> field-collection
## path (cost 2.0) it was competing against. That stranded Gatherers retrying
## an honest no-op at the Nest forever whenever stock was empty - including
## every first-ever report of a resource type, since nothing can be in
## storage before something has been collected from the field at least once.
static func stored_field(kind: String) -> String:
	return "%s_stored" % kind.to_lower()


## high_hunger is the other precondition guarding this action, added
## alongside stored_field: without it, GetResource[Kind] and DepositResource
## are exact inverses (has_item true/false, storage -1/+1, net zero) with
## neither requiring travel - so a Gatherer with nonzero stock could satisfy
## CollectFood/CollectWood by pulling straight from the Nest's own pantry and
## immediately redepositing it, forever. Every action in that pair completes
## synchronously (GoapCycle.on_action_completed's "clean finish, replan
## immediately" path has no frame boundary to stop at, unlike a GoTo leg),
## so the pair free-ran as a tight same-frame oscillation instead of doing
## any real colony work. Gating on high_hunger restores this action's actual
## purpose (SPEC.md's GetFood goal: a hungry agent eating from stock) and
## keeps CollectFood/CollectWood - which don't care about hunger - on the
## honest GoTo[Kind]->Pickup<Kind> field-collection path instead.


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
		var preconditions: Dictionary = {"has_item": false, "at_nest": true, "high_hunger": true}
		var stored := stored_field(kind)
		if stored in known_fields:
			preconditions[stored] = true
		actions.append({
			"name": action_name(kind),
			"cost": GET_RESOURCE_ACTION_COST,
			"preconditions": preconditions,
			"effects": {field: true}
		})
	return actions
