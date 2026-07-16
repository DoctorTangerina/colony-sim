extends Node

signal role_changed(agent_id: String, old_role: String, new_role: String)

var current_role: String = ""
var _om_ref: Node = null
var _role_component: Node = null
var _nest_zone: Node = null
var _agent_id: String = ""
var _role_cooldown: float = 0.0
var _role_cooldown_duration: float = 10.0


func setup(om_ref: Node, role_component: Node, nest_zone: Node, agent_id: String, cooldown_duration: float = 10.0) -> void:
	_om_ref = om_ref
	_role_component = role_component
	_nest_zone = nest_zone
	_agent_id = agent_id
	_role_cooldown_duration = cooldown_duration


func process(delta: float) -> void:
	if _role_cooldown > 0.0:
		_role_cooldown = maxf(_role_cooldown - delta, 0.0)


func set_role(role_name: String) -> void:
	if _role_component:
		var old_role := current_role
		_role_component.load_role(role_name)
		current_role = role_name
		_role_cooldown = _role_cooldown_duration
		role_changed.emit(_agent_id, old_role, role_name)

		if role_name != "" and role_name != "Unassigned" and _om_ref:
			_om_ref.update_agent_role(_agent_id, role_name, "role_request_fulfilled")


func get_current_role() -> String:
	return current_role


func check_and_acquire_role() -> void:
	if _role_cooldown > 0.0:
		return
	if _nest_zone and not _nest_zone.is_in_nest_zone():
		return
	if _om_ref == null:
		return

	var requests = _om_ref.get_all_requests()
	for req_role in requests:
		if req_role == current_role:
			continue
		if _om_ref.take_request(req_role):
			set_role(req_role)
			return
