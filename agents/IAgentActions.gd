class_name IAgentActions
extends CharacterBody2D

## The seam between GoapActionExecutor and agent internals: the executor calls
## only these methods, never reaches into agent fields directly. agent.gd
## implements this by extending it (GDScript has no separate interface
## mechanism, and IAgentActions extends CharacterBody2D so agent.gd keeps its
## physics/movement base while also satisfying this type).
##
## move_to through get_known_positions are the ticket-specified minimal set;
## get_world_bounds and deposit_at_nest were added because RandomExplore and
## DepositResource (both kept, spec-required actions) still need them -
## omitting them would force the executor back to direct field access for
## those actions. attempt_pickup encapsulates PickupFood/PickupWood's grab
## (find nearest node of a type via get_nearest_resource, range-check,
## extract) behind one call, matching deposit_at_nest's shape, so the
## executor orchestrates a single intent instead of several primitives.

func move_to(_target: Vector2) -> void:
	pass


func get_nest_position() -> Vector2:
	return Vector2.ZERO


func get_held_item() -> String:
	return "None"


func pick_up_item(_item: String) -> void:
	pass


## Instantaneous, Interaction-Range-gated grab (ADR 5) - never moves the
## agent. A no-op if nothing of resource_type is within reach, or if the
## agent's hands are already full (single-slot: CONTEXT.md's Held Item).
func attempt_pickup(_resource_type: String) -> void:
	pass


## Withdraws resource_type from the Nest's own storage into hands, mirroring
## attempt_pickup's shape (single-slot, no-op if hands already full) but
## sourced from Nest.withdraw() instead of a live field resource node.
func attempt_withdraw(_resource_type: String) -> void:
	pass


func drop_item() -> void:
	pass


func reduce_hunger(_amount: float) -> void:
	pass


func reset_hunger() -> void:
	pass


func restore_energy(_amount: float) -> void:
	pass


func drain_energy(_amount: float) -> void:
	pass


func start_resting() -> void:
	pass


func stop_resting() -> void:
	pass


func complete_action() -> void:
	pass


func get_nearest_resource(_pos: Vector2, _resource_type: String) -> Node:
	return null


func get_known_positions() -> Dictionary:
	return {}


func get_world_bounds() -> Rect2:
	return Rect2()


func deposit_at_nest(_item_type: String) -> void:
	pass


## RandomExplore's target selection (Ticket 7/ADR 9): a point inside the map
## bounds, biased away from ground the colony-shared Explored Trail already
## covers. Kept behind this seam so GoapActionExecutor never reaches into
## nest_ref/ExploredTrail directly, matching deposit_at_nest/attempt_pickup's
## shape.
func pick_explore_target() -> Vector2:
	return Vector2.ZERO


## ADR 6: called by GoapCycle when verify-by-effect finds a just-completed
## Pickup action's declared effect doesn't hold - direct evidence (the agent
## was physically at this position; extraction yielded nothing) that the
## Blackboard's matching entry is stale. Carried independently of the
## discovery carry-slot until ReportDepletion clears it at the Nest.
func record_failed_report(_resource_type: String, _position: Vector2) -> void:
	pass


## ADR 12: called by GoapCycle once verify-by-effect confirms a completed
## action's declared effect genuinely holds (Action Verified, CONTEXT.md) -
## generic on purpose, agent.gd stays ignorant of what any listener does with
## the name. Kept behind this seam rather than agent.gd emitting its signal
## directly from GoapCycle, matching every other GoapCycle->agent notification.
func notify_action_verified(_action_name: String) -> void:
	pass
