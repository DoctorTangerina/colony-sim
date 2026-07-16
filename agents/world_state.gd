class_name WorldStateBuilder


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
	var WorldStateScript = preload("res://agents/WorldState.gd")
	return WorldStateScript.build(held_item, energy, hunger, at_nest, food_visible, wood_visible, near_unreported_resource, known_food_position, known_wood_position)