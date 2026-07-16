class_name WorldStateBuilder


static func build(
	held_item: String,
	energy: float,
	hunger: float,
	at_nest: bool,
	food_visible: bool,
	wood_visible: bool,
	near_unreported_resource: bool = false
) -> Dictionary:
	return {
		"at_nest": at_nest,
		"has_food": held_item == "Food",
		"has_wood": held_item == "Wood",
		"has_item": held_item != "None",
		"low_energy": energy < 30.0,
		"high_hunger": hunger > 70.0,
		"food_visible": food_visible,
		"wood_visible": wood_visible,
		"resource_visible": food_visible or wood_visible,
		"enemy_near": false,
		"near_unreported_resource": near_unreported_resource
	}
