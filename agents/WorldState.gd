class_name WorldState
extends Resource

## World-state schema. This is the full set of flags a goal/action
## precondition or effect (configs/goals, configs/actions) may reference -
## satisfies() and merge() silently ignore any key not listed here, so an
## undocumented flag in a config file is a silent no-op, not an error.
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


static func build(
	held_item: String,
	energy: float,
	hunger: float,
	at_nest: bool,
	food_visible: bool,
	wood_visible: bool,
	near_unreported_resource: bool = false,
	known_food_position: bool = false,
	known_wood_position: bool = false
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
	return state


func satisfies(preconditions: Dictionary) -> bool:
	for key in preconditions:
		if key not in get_field_keys() or get_field(key) != preconditions[key]:
			return false
	return true


func merge(effects: Dictionary) -> WorldState:
	var new_state := clone()
	for key in effects:
		if key in new_state.get_field_keys():
			new_state.set_field(key, effects[key])
	return new_state


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
	var fields := ["at_nest", "has_food", "has_wood", "has_item", "low_energy", "high_hunger",
		"food_visible", "wood_visible", "resource_visible", "enemy_near", "near_unreported_resource",
		"known_food_position", "known_wood_position"]
	for field in fields:
		dict[field] = get_field(field)
	return dict


func get_field_keys() -> Array:
	return ["at_nest", "has_food", "has_wood", "has_item", "low_energy", "high_hunger",
		"food_visible", "wood_visible", "resource_visible", "enemy_near", "near_unreported_resource",
		"known_food_position", "known_wood_position"]


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
