extends Node

signal role_changed(agent_id: String, old_role: String, new_role: String)

var current_role: String = ""
var _om_ref: Node = null
var _role_component: Node = null
var _nest_zone: Node = null
var _agent_id: String = ""
var _role_cooldown_duration: float = 10.0
var _cooldown_ends_at_msec: int = 0


func setup(om_ref: Node, role_component: Node, nest_zone: Node, agent_id: String, cooldown_duration: float = 10.0) -> void:
	_om_ref = om_ref
	_role_component = role_component
	_nest_zone = nest_zone
	_agent_id = agent_id
	_role_cooldown_duration = cooldown_duration


## Timestamp-based (not per-frame decremented) so acquisition can be
## checked on-demand from event handlers instead of needing a process() tick.
func get_cooldown() -> float:
	return maxf(0.0, (_cooldown_ends_at_msec - Time.get_ticks_msec()) / 1000.0)


## Registers the agent with the OM at its starting role. Unlike set_role(),
## this is initialization, not a role-change event: no cooldown, no
## role_changed signal, and no update_agent_role call (register_agent covers
## a fresh registration - going through update_agent_role would just hit its
## own register-fallback for an id that isn't tracked yet).
func register_initial_role(agent_node: Node, role_name: String = "Unassigned") -> void:
	if _role_component:
		_role_component.load_role(role_name)
	current_role = role_name
	if _om_ref:
		_om_ref.register_agent(_agent_id, role_name, agent_node)


func set_role(role_name: String) -> void:
	if _role_component:
		var old_role := current_role
		_role_component.load_role(role_name)
		current_role = role_name
		_cooldown_ends_at_msec = Time.get_ticks_msec() + int(_role_cooldown_duration * 1000.0)
		role_changed.emit(_agent_id, old_role, role_name)

		if role_name != "" and _om_ref:
			_om_ref.update_agent_role(_agent_id, role_name, "role_request_fulfilled")


func get_current_role() -> String:
	return current_role


## Eligibility (ADR 2): Unassigned agents may take any request; an assigned
## agent may take a request only while its current role is Surplus - checked
## via the OM's read-only query, never by the OM selecting or demoting an
## agent itself. All other gates (cooldown, nest zone, first-eligible-wins,
## skip-own-role) are unchanged.
func check_and_acquire_role() -> void:
	if get_cooldown() > 0.0:
		return
	if _nest_zone and not _nest_zone.is_in_nest_zone():
		return
	if _om_ref == null:
		return
	if current_role != "Unassigned" and not _om_ref.is_role_surplus(current_role):
		return

	var requests = _om_ref.get_all_requests()
	for req_role in requests:
		if req_role == current_role:
			continue
		if _om_ref.take_request(req_role):
			set_role(req_role)
			_om_ref.notify_request_fulfilled(_agent_id, req_role)
			return
