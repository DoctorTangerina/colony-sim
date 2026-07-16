class_name AgentActions
extends RefCounted

## IAgentActions — the seam between GoapActionExecutor and agent internals.
##
## The executor never touches agent fields directly. It only calls these methods.
## To add a new action that needs a new capability, add a method here, implement
## it on the agent, and the executor gains it without reaching into agent internals.

## --- Position & Movement ---

func get_agent_position() -> Vector2:
	return Vector2.ZERO

func move_to(target: Vector2) -> void:
	pass

## --- Nest ---

func get_nest_position() -> Vector2:
	return Vector2.ZERO

func deposit_at_nest(item_type: String) -> void:
	pass

## --- Resources ---

func get_nearest_resource(pos: Vector2, resource_type: String) -> Node:
	return null

func set_target_resource(node: Node) -> void:
	pass

## --- Inventory ---

func get_held_item() -> String:
	return "None"

func pick_up_item(item: String) -> void:
	pass

func drop_item() -> void:
	pass

## --- Stats ---

func reduce_hunger(amount: float) -> void:
	pass

func restore_energy(amount: float) -> void:
	pass

## --- Completion ---

func complete_action() -> void:
	pass

## --- Environment ---

func get_world_bounds() -> Rect2:
	return Rect2()
