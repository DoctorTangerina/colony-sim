class_name GotoGrounding
extends Node

## Grounds the single generic GoTo action (CONTEXT.md: GoTo; ADR 5/ADR 8) into
## one concrete Action dict per destination kind. Destination kinds are never
## hand-listed: the Nest is always available, and every other kind comes from
## the resource registry (configs/resources.json) - adding a resource kind
## there is enough to make GoTo *able* to path to it, with no second
## destination list to keep in sync.
##
## A kind only becomes a real, planner-usable GoTo variant once WorldState
## has a Sensed Fact field to hold "arrived at it" (see WorldState.gd's
## schema doc-comment). Today that's just "Nest" -> at_nest; Food/Wood get
## their at_food_position/at_wood_position fields in a later ticket. A kind
## without a matching field is silently skipped here rather than grounded
## with a fabricated effect key WorldState would reject - the same
## unmodified code starts grounding it automatically the moment that field
## is added, which is the actual point of deriving kinds from resources.json
## instead of hand-listing them.

const NEST_KIND := "Nest"
const NEST_FIELD := "at_nest"
const GOTO_ACTION_COST: float = 1.0


static func destination_kinds(resource_kinds: Array) -> Array:
	var kinds: Array = [NEST_KIND]
	for kind in resource_kinds:
		if not kinds.has(kind):
			kinds.append(kind)
	return kinds


static func destination_field(kind: String) -> String:
	if kind == NEST_KIND:
		return NEST_FIELD
	return "at_%s_position" % kind.to_lower()


static func action_name(kind: String) -> String:
	return "%s[%s]" % [GoapActions.GOTO, kind]


## known_fields is WorldState's current schema (WorldState.new().get_field_keys())
## - passed in rather than referenced directly so this stays testable with a
## fabricated schema without touching the real WorldState class.
static func build_actions(resource_kinds: Array, known_fields: Array) -> Array:
	var actions: Array = []
	for kind in destination_kinds(resource_kinds):
		var field := destination_field(kind)
		if field not in known_fields:
			continue
		actions.append({
			"name": action_name(kind),
			"cost": GOTO_ACTION_COST,
			"preconditions": {},
			"effects": {field: true}
		})
	return actions
