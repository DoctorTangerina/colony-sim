class_name IAgentActions
extends CharacterBody2D

## The seam between GoapActionExecutor and agent internals: the executor calls
## only these methods, never reaches into agent fields directly. agent.gd
## implements this by extending it (GDScript has no separate interface
## mechanism, and IAgentActions extends CharacterBody2D so agent.gd keeps its
## physics/movement base while also satisfying this type).
##
## move_to through get_known_positions are the ticket-specified minimal set;
## get_agent_position, get_world_bounds, and deposit_at_nest were added
## because RandomExplore, PickupFood/PickupWood, and DepositResource (all
## kept, spec-required actions) still need them - omitting them would force
## the executor back to direct field access for those actions.

func move_to(_target: Vector2) -> void:
	pass


func get_nest_position() -> Vector2:
	return Vector2.ZERO


func get_held_item() -> String:
	return "None"


func pick_up_item(_item: String) -> void:
	pass


func drop_item() -> void:
	pass


func reduce_hunger(_amount: float) -> void:
	pass


func restore_energy(_amount: float) -> void:
	pass


func complete_action() -> void:
	pass


func get_nearest_resource(_pos: Vector2, _resource_type: String) -> Node:
	return null


func set_target_resource(_node: Node) -> void:
	pass


func get_known_positions() -> Dictionary:
	return {}


func get_agent_position() -> Vector2:
	return Vector2.ZERO


func get_world_bounds() -> Rect2:
	return Rect2()


func deposit_at_nest(_item_type: String) -> void:
	pass
