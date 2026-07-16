extends Node

var _in_nest_zone: bool = false
var _agent_body: Node2D = null


func setup(nest_ref: Node2D, agent_body: Node2D) -> void:
	_agent_body = agent_body
	if not nest_ref:
		return
	var zone = nest_ref.get_trigger_zone() if nest_ref.has_method("get_trigger_zone") else null
	if zone == null:
		zone = nest_ref.get_node_or_null("TriggerZone")
	if zone is Area2D:
		zone.body_entered.connect(_on_body_entered)
		zone.body_exited.connect(_on_body_exited)


func is_in_nest_zone() -> bool:
	return _in_nest_zone


func _on_body_entered(body: Node2D) -> void:
	if body == _agent_body:
		_in_nest_zone = true


func _on_body_exited(body: Node2D) -> void:
	if body == _agent_body:
		_in_nest_zone = false
