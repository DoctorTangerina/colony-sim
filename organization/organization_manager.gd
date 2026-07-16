extends Node

signal role_request_posted(role_name: String)
signal role_request_fulfilled(agent_id: String, role_name: String)
signal agent_registered(agent_id: String, role: String)
signal agent_unregistered(agent_id: String)

var _role_requests: Array = []
var _agent_roles: Dictionary = {}
var _role_counts: Dictionary = {}
var _role_change_log: Array = []
var _death_counter: int = 0
var _eval_timer: float = 0.0
var _eval_interval: float = 1.0
var _dynamic_roles_enabled: bool = true
var _role_cooldown: float = 10.0
var _nest_ref: Node = null
var _thresholds: Dictionary = {}
var _role_defs: Dictionary = {}


func _ready() -> void:
	_load_config()
	_load_nest_thresholds()


func _process(delta: float) -> void:
	if not _dynamic_roles_enabled:
		return
	if _nest_ref == null:
		return

	_eval_timer -= delta
	if _eval_timer <= 0.0:
		_eval_timer = _eval_interval
		_evaluate_roles()


func setup(nest: Node) -> void:
	_nest_ref = nest


func set_dynamic_roles(enabled: bool) -> void:
	_dynamic_roles_enabled = enabled


func get_role_cooldown() -> float:
	return _role_cooldown


func _load_config() -> void:
	var data: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	_eval_interval = data.get("roleEvalInterval", 1.0)
	_dynamic_roles_enabled = data.get("enableDynamicRoles", true)
	_role_cooldown = data.get("roleCooldown", 10.0)


func _load_nest_thresholds() -> void:
	var data: Dictionary = ConfigLoader.load_dict("res://configs/nest.json")
	_thresholds = data.get("thresholds", {})


func _get_role_def(role_name: String) -> Dictionary:
	if _role_defs.has(role_name):
		return _role_defs[role_name]
	var path := "res://configs/roles/%s.json" % role_name.to_lower()
	var data: Dictionary = ConfigLoader.load_dict(path)
	_role_defs[role_name] = data
	return data


func post_request(role_name: String) -> void:
	_role_requests.append(role_name)
	role_request_posted.emit(role_name)


func take_request(role_name: String) -> bool:
	var idx := _role_requests.find(role_name)
	if idx >= 0:
		_role_requests.remove_at(idx)
		return true
	return false


func clear_requests_for_role(role_name: String) -> void:
	var result: Array = []
	for r in _role_requests:
		if r != role_name:
			result.append(r)
	_role_requests = result


func get_request_count(role_name: String) -> int:
	var count := 0
	for r in _role_requests:
		if r == role_name:
			count += 1
	return count


func get_total_request_count() -> int:
	return _role_requests.size()


func get_all_requests() -> Array:
	return _role_requests.duplicate()


func register_agent(agent_id: String, role: String) -> void:
	_agent_roles[agent_id] = role
	_role_counts[role] = _role_counts.get(role, 0) + 1
	agent_registered.emit(agent_id, role)


func unregister_agent(agent_id: String) -> void:
	if _agent_roles.has(agent_id):
		var old_role: String = _agent_roles[agent_id]
		_role_counts[old_role] = _role_counts.get(old_role, 0) - 1
		if _role_counts[old_role] <= 0:
			_role_counts.erase(old_role)
		_agent_roles.erase(agent_id)
		agent_unregistered.emit(agent_id)


func update_agent_role(agent_id: String, new_role: String, reason: String = "") -> void:
	if not _agent_roles.has(agent_id):
		register_agent(agent_id, new_role)
		return

	var old_role: String = _agent_roles[agent_id]
	if old_role == new_role:
		return

	_role_counts[old_role] = _role_counts.get(old_role, 0) - 1
	if _role_counts[old_role] <= 0:
		_role_counts.erase(old_role)

	_agent_roles[agent_id] = new_role
	_role_counts[new_role] = _role_counts.get(new_role, 0) + 1

	_role_change_log.append({
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"agent_id": agent_id,
		"old_role": old_role,
		"new_role": new_role,
		"reason": reason
	})


func get_role_count(role_name: String) -> int:
	return _role_counts.get(role_name, 0)


func get_total_agent_count() -> int:
	return _agent_roles.size()


func get_role_counts() -> Dictionary:
	return _role_counts.duplicate()


func get_role_change_log() -> Array:
	return _role_change_log.duplicate()


func handle_agent_death(agent_id: String) -> void:
	if _agent_roles.has(agent_id):
		var role: String = _agent_roles[agent_id]
		_role_counts[role] = _role_counts.get(role, 0) - 1
		if _role_counts[role] <= 0:
			_role_counts.erase(role)
		_agent_roles.erase(agent_id)
	_death_counter += 1


func get_death_count() -> int:
	return _death_counter


func get_threshold(resource_type: String, key: String, default_val: int = 0) -> int:
	var thresh: Dictionary = _thresholds.get(resource_type, {})
	return thresh.get(key, default_val)


func _evaluate_roles() -> void:
	if _nest_ref == null:
		return
	if not _nest_ref.has_method("get_storage"):
		return

	var food_storage: int = _nest_ref.get_storage("Food")
	var wood_storage: int = _nest_ref.get_storage("Wood")

	var total_agents := get_total_agent_count()
	if total_agents == 0:
		return

	var target_counts := _compute_target_distribution(food_storage, wood_storage, total_agents)

	for role_name in target_counts:
		var target: int = target_counts[role_name]
		var current := get_request_count(role_name)
		if target > current:
			for i in range(target - current):
				post_request(role_name)
		elif target < current:
			clear_requests_for_role(role_name)


func _compute_target_distribution(food: int, wood: int, total: int) -> Dictionary:
	var result := {}

	for role_name in _role_defs:
		var def: Dictionary = _role_defs[role_name]
		var dist: Dictionary = def.get("distribution", {})
		var rules: Array = dist.get("rules", [])
		var target := 0

		for rule in rules:
			if rule.get("default", false):
				target = maxi(0, ceili(total * rule.get("percent", 0.0)))
				break

			var cond: Dictionary = rule.get("if_resource_at_or_below", {})
			if cond.is_empty():
				continue

			var res_type: String = cond.get("type", "")
			var level_name: String = cond.get("level", "low")
			var threshold_val: int = get_threshold(res_type, level_name, 0)
			var multiply: int = cond.get("multiply_level", 1)
			var effective_threshold: int = threshold_val * multiply

			var resource_val: int = food if res_type == "Food" else wood
			if resource_val <= effective_threshold:
				target = maxi(1, ceili(total * rule.get("percent", 0.0)))
				break

		result[role_name] = target

	return result
