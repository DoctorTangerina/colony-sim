class_name WorldState
extends Resource

## World-state schema. This is the full set of flags a goal/action
## precondition or effect (configs/goals, configs/actions) may reference -
## satisfies(), merge(), and set_field() fail loudly (push_error) on any key
## not listed here, so an undocumented flag in a config file breaks
## immediately in testing instead of manifesting as a silent no-op.
##
## - at_nest (bool): agent is within nest interaction range.
## - has_food (bool): agent's held item is "Food".
## - has_wood (bool): agent's held item is "Wood".
## - has_item (bool): agent is holding "Food" or "Wood" (held item != "None").
## - low_energy (bool): agent energy < 30.0.
## - high_hunger (bool): agent hunger > 70.0.
## - food_visible (bool): a Food resource node is reachable near the agent right now.
## - wood_visible (bool): a Wood resource node is reachable near the agent right now.
## - resource_visible (bool): food_visible or wood_visible.
## - enemy_near (bool): always false - enemies are Phase 6, not yet implemented.
## - near_unreported_resource (bool): agent is near a resource not yet in the Nest's Blackboard.
## - known_food_position (bool): the Blackboard holds at least one Food position (permanent field - Blackboard is kept, see Ticket 14).
## - known_wood_position (bool): the Blackboard holds at least one Wood position (permanent field - Blackboard is kept, see Ticket 14).
## - has_unreported_discovery (bool): agent is carrying a discovered resource position it has not yet reported to the Nest (persists as the agent travels, unlike near_unreported_resource which is proximity-only).
## - at_food_position (bool): a Food resource node is within Interaction Range (arm's-length) of the agent right now - distinct from food_visible's Discovery Radius (seeing != reaching).
## - at_wood_position (bool): a Wood resource node is within Interaction Range of the agent right now - distinct from wood_visible's Discovery Radius.
## - has_failed_report (bool): agent is carrying a verified Action Failure (Pickup found nothing at a known position) it has not yet reported to the Nest - independent of has_unreported_discovery (ADR 6).
## - is_idle (bool): always false, like enemy_near - Idle's declared effect (Ticket 6) targets a fact this schema never senses true, which is what keeps the Idle goal perpetually achievable (never "already satisfied") whenever nothing else is, mirroring Explore's own perpetual shape.
var at_nest: bool = false
var has_food: bool = false
var has_wood: bool = false
var has_item: bool = false
var low_energy: bool = false
var high_hunger: bool = false
var food_visible: bool = false
var wood_visible: bool = false
var resource_visible: bool = false
var enemy_near: bool = false
var near_unreported_resource: bool = false
var known_food_position: bool = false
var known_wood_position: bool = false
var has_unreported_discovery: bool = false
var at_food_position: bool = false
var at_wood_position: bool = false
var has_failed_report: bool = false
var is_idle: bool = false


static func build(
	held_item: String,
	energy: float,
	hunger: float,
	at_nest: bool,
	food_visible: bool,
	wood_visible: bool,
	near_unreported_resource: bool = false,
	known_food_position: bool = false,
	known_wood_position: bool = false,
	has_unreported_discovery: bool = false,
	at_food_position: bool = false,
	at_wood_position: bool = false,
	has_failed_report: bool = false
) -> WorldState:
	var state := WorldState.new()
	state.at_nest = at_nest
	state.has_food = held_item == "Food"
	state.has_wood = held_item == "Wood"
	state.has_item = held_item != "None"
	state.low_energy = energy < 30.0
	state.high_hunger = hunger > 70.0
	state.food_visible = food_visible
	state.wood_visible = wood_visible
	state.resource_visible = food_visible or wood_visible
	state.enemy_near = false
	state.near_unreported_resource = near_unreported_resource
	state.known_food_position = known_food_position
	state.known_wood_position = known_wood_position
	state.has_unreported_discovery = has_unreported_discovery
	state.at_food_position = at_food_position
	state.at_wood_position = at_wood_position
	state.has_failed_report = has_failed_report
	state.is_idle = false
	return state


func satisfies(preconditions: Dictionary) -> bool:
	for key in preconditions:
		if key not in get_field_keys():
			_fail_unrecognized_key(key)
			return false
		if get_field(key) != preconditions[key]:
			return false
	return true


func merge(effects: Dictionary) -> WorldState:
	var new_state := clone()
	for key in effects:
		if key not in new_state.get_field_keys():
			_fail_unrecognized_key(key)
			continue
		new_state.set_field(key, effects[key])
	return new_state


## A precondition/effect key outside get_field_keys()'s schema is a config
## bug (a typo, or a field a later ticket forgot to add here) - loud so it
## breaks in testing instead of surfacing as a mysteriously-permanent Action
## Failure (see docs/adr/0008). push_error only, no assert(): assert() halts
## the process waiting for a debugger even headless, with no attached
## debugger to resume it - a hang, not a fail-fast, in a CI/test context.
func _fail_unrecognized_key(key: String) -> void:
	push_error("WorldState: unrecognized key '%s' - not in the documented schema (get_field_keys())" % key)


# Resource.duplicate() only copies properties with PROPERTY_USAGE_STORAGE;
# plain (non-@export) script vars don't get that flag, so it silently
# returns an all-defaults copy. Use this instead of duplicate() everywhere.
func clone() -> WorldState:
	var new_state := WorldState.new()
	for key in get_field_keys():
		new_state.set_field(key, get_field(key))
	return new_state


func to_dict() -> Dictionary:
	var dict := {}
	var fields := get_field_keys()
	for field in fields:
		dict[field] = get_field(field)
	return dict


func get_field_keys() -> Array:
	return ["at_nest", "has_food", "has_wood", "has_item", "low_energy", "high_hunger",
		"food_visible", "wood_visible", "resource_visible", "enemy_near", "near_unreported_resource",
		"known_food_position", "known_wood_position", "has_unreported_discovery",
		"at_food_position", "at_wood_position", "has_failed_report", "is_idle"]


func get_field(key: String) -> Variant:
	match key:
		"at_nest": return at_nest
		"has_food": return has_food
		"has_wood": return has_wood
		"has_item": return has_item
		"low_energy": return low_energy
		"high_hunger": return high_hunger
		"food_visible": return food_visible
		"wood_visible": return wood_visible
		"resource_visible": return resource_visible
		"enemy_near": return enemy_near
		"near_unreported_resource": return near_unreported_resource
		"known_food_position": return known_food_position
		"known_wood_position": return known_wood_position
		"has_unreported_discovery": return has_unreported_discovery
		"at_food_position": return at_food_position
		"at_wood_position": return at_wood_position
		"has_failed_report": return has_failed_report
		"is_idle": return is_idle
		_: return null


func set_field(key: String, value: Variant) -> void:
	match key:
		"at_nest": at_nest = value
		"has_food": has_food = value
		"has_wood": has_wood = value
		"has_item": has_item = value
		"low_energy": low_energy = value
		"high_hunger": high_hunger = value
		"food_visible": food_visible = value
		"wood_visible": wood_visible = value
		"resource_visible": resource_visible = value
		"enemy_near": enemy_near = value
		"near_unreported_resource": near_unreported_resource = value
		"known_food_position": known_food_position = value
		"known_wood_position": known_wood_position = value
		"has_unreported_discovery": has_unreported_discovery = value
		"at_food_position": at_food_position = value
		"at_wood_position": at_wood_position = value
		"has_failed_report": has_failed_report = value
		"is_idle": is_idle = value
		_: _fail_unrecognized_key(key)
