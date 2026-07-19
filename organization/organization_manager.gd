extends Node

const ROLE_CONFIG_DIR := "res://configs/roles"

signal role_request_posted(role_name: String)
signal role_request_fulfilled(agent_id: String, role_name: String)
signal agent_registered(agent_id: String, role: String)
signal agent_unregistered(agent_id: String)

var _role_requests: Array = []
var _agent_roles: Dictionary = {}
var _agent_nodes: Dictionary = {}
var _role_counts: Dictionary = {}
var _role_change_log: Array = []
var _death_counter: int = 0
var _eval_timer: float = 0.0
var _eval_interval: float = 1.0
var _dynamic_roles_enabled: bool = true
var _distribution_mode: String = "dynamic"
var _role_cooldown: float = 10.0
var _min_unassigned_threshold: int = 5
var _nest_ref: Node = null
var _thresholds: Dictionary = {}
var _role_defs: Dictionary = {}
var _cached_targets: Dictionary = {}


func _ready() -> void:
	# ADR 12: applied here, before anything else, because OrganizationManager
	# is the project's sole autoload (AGENTS.md) and therefore the first
	# script whose _ready() runs at all - earlier than resource_manager.gd's,
	# whose _ready() is the first thing that actually calls randf_range. Not
	# a Threshold Policy concern by nature, just the earliest hook available
	# without adding a second autoload.
	var seed_override := ExperimentCLI.get_int("seed", -1)
	if seed_override >= 0:
		seed(seed_override)

	_load_config()
	_load_nest_thresholds()
	_load_role_defs()


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
	_distribution_mode = ExperimentCLI.get_string("distribution-mode", data.get("distributionMode", "dynamic"))
	_role_cooldown = data.get("roleCooldown", 10.0)
	_min_unassigned_threshold = data.get("minUnassignedThreshold", 5)


func _load_nest_thresholds() -> void:
	var data: Dictionary = ConfigLoader.load_dict("res://configs/nest.json")
	_thresholds = data.get("thresholds", {})


## Discovers every role definition JSON under ROLE_CONFIG_DIR so the Threshold
## Policy always evaluates the full set of defined roles - adding a role is a
## JSON-only change, no engine caller needs updating. Unassigned has no JSON
## file and is never part of this scan; its floor is applied separately in
## _compute_target_distribution.
func _load_role_defs() -> void:
	var dir := DirAccess.open(ROLE_CONFIG_DIR)
	if dir == null:
		push_error("OrganizationManager: could not open role config directory: %s" % ROLE_CONFIG_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data: Dictionary = ConfigLoader.load_dict("%s/%s" % [ROLE_CONFIG_DIR, file_name])
			var role_name: String = data.get("name", "")
			if not role_name.is_empty():
				_role_defs[role_name] = data
		file_name = dir.get_next()
	dir.list_dir_end()


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


## Withdraws at most `count` pending requests for role_name, oldest first,
## leaving any remainder untouched - unlike clear_requests_for_role, this
## never over-withdraws still-needed requests. Holders are never touched;
## only the anonymous request queue is affected (ADR 1, ADR 2).
func withdraw_requests(role_name: String, count: int) -> void:
	var result: Array = []
	var remaining_to_withdraw := count
	for r in _role_requests:
		if r == role_name and remaining_to_withdraw > 0:
			remaining_to_withdraw -= 1
			continue
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


func register_agent(agent_id: String, role: String, agent_node: Node = null) -> void:
	_agent_roles[agent_id] = role
	_role_counts[role] = _role_counts.get(role, 0) + 1
	if agent_node != null:
		_agent_nodes[agent_id] = agent_node
	agent_registered.emit(agent_id, role)


func unregister_agent(agent_id: String) -> void:
	if _agent_roles.has(agent_id):
		var old_role: String = _agent_roles[agent_id]
		_role_counts[old_role] = _role_counts.get(old_role, 0) - 1
		if _role_counts[old_role] <= 0:
			_role_counts.erase(old_role)
		_agent_roles.erase(agent_id)
		_agent_nodes.erase(agent_id)
		agent_unregistered.emit(agent_id)


## Snapshot of currently-registered agent ids, e.g. for a UI that boots after
## agents have already registered (scene tree ready-order isn't guaranteed)
## and needs to backfill state instead of relying solely on future signals.
func get_registered_agent_ids() -> Array:
	return _agent_roles.keys()


## Resolves a registered agent id to its live Agent node, e.g. for a UI that
## needs to query get_debug_info() on demand. Null if never registered with a
## node reference, or if the node has since been freed.
func get_agent_node(agent_id: String) -> Node:
	var node: Node = _agent_nodes.get(agent_id)
	if node != null and is_instance_valid(node):
		return node
	return null


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
	unregister_agent(agent_id)
	_death_counter += 1


func get_death_count() -> int:
	return _death_counter


## Single-snapshot dict for the debugger UI, mirroring Agent.get_debug_info()'s
## convention so callers never reach into OM internals or query the Nest
## directly. Storage and role-market fields (role_counts, cached_targets,
## pending_requests) report zeros/empty rather than erroring when _nest_ref
## hasn't been wired via setup() yet - the same posture the UI already takes
## toward not-yet-registered agents. Settings and the role-change log don't
## depend on the Nest, so they always report their true state. Death counter
## is deliberately excluded (out of scope).
func get_debug_info() -> Dictionary:
	var role_names: Array = _role_defs.keys()
	if not role_names.has("Unassigned"):
		role_names.append("Unassigned")

	var storage: Dictionary = {"Food": 0, "Wood": 0}
	var role_counts: Dictionary = {}
	var cached_targets: Dictionary = {}
	var pending_requests: Dictionary = {}

	if _nest_ref != null:
		storage = _nest_ref.get_storage_summary()
		for role_name in role_names:
			role_counts[role_name] = get_role_count(role_name)
			cached_targets[role_name] = get_cached_target(role_name)
			pending_requests[role_name] = get_request_count(role_name)

	return {
		"storage": storage,
		"role_counts": role_counts,
		"cached_targets": cached_targets,
		"pending_requests": pending_requests,
		"dynamic_roles_enabled": _dynamic_roles_enabled,
		"role_cooldown": _role_cooldown,
		"min_unassigned_threshold": _min_unassigned_threshold,
		"role_change_log": get_role_change_log(),
	}


func get_threshold(resource_type: String, key: String, default_val: int = 0) -> int:
	var thresh: Dictionary = _thresholds.get(resource_type, {})
	return thresh.get(key, default_val)


## Read-only target/surplus query (ADR 1): answers questions about a role
## from the target distribution cached at the last evaluation - never about,
## or to, a specific agent. The agent side of ADR 2's eligibility check
## calls this to decide whether its own current role is Surplus.
func get_cached_target(role_name: String) -> int:
	return _cached_targets.get(role_name, 0)


func is_role_surplus(role_name: String) -> bool:
	return get_role_count(role_name) > get_cached_target(role_name)


## Called by the agent side (RoleAcquisition) once a taken request has been
## applied as a role change - the OM never takes requests itself (ADR 1), so
## it relies on this notification to know when to emit its own signal.
func notify_request_fulfilled(agent_id: String, role_name: String) -> void:
	role_request_fulfilled.emit(agent_id, role_name)


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

	var known: Dictionary = _get_known_resource_types()

	_cached_targets = _compute_target_distribution(food_storage, wood_storage, total_agents, known)

	for role_name in _cached_targets:
		var target: int = _cached_targets[role_name]
		var holders := get_role_count(role_name)
		var pending := get_request_count(role_name)
		var deficit: int = target - (holders + pending)

		if deficit > 0:
			for i in range(deficit):
				post_request(role_name)
		elif deficit < 0:
			withdraw_requests(role_name, mini(-deficit, pending))


## ADR 12: an experiment-only alternative to the rule-based computation below,
## for comparing the need-based policy against a static, resource-blind
## baseline. Ignores food/wood/known entirely - a fixed 50/50 Gatherer/
## Explorer split every evaluation, regardless of colony state. Guard (and
## any other role without an explicit split here) targets 0, same as its
## zeroed/dormant distribution rule already yields in dynamic mode.
func _compute_static_target_distribution(total: int) -> Dictionary:
	var result := {}

	for role_name in _role_defs:
		if role_name == "Gatherer" or role_name == "Explorer":
			result[role_name] = ceili(total * 0.5)
		else:
			result[role_name] = 0

	return result


func _compute_target_distribution(food: int, wood: int, total: int, known: Dictionary) -> Dictionary:
	var result := {}

	if _distribution_mode == "static":
		result = _compute_static_target_distribution(total)
	else:
		for role_name in _role_defs:
			var def: Dictionary = _role_defs[role_name]
			var dist: Dictionary = def.get("distribution", {})
			var rules: Array = dist.get("rules", [])
			var target := 0

			for rule in rules:
				if rule.get("default", false):
					target = maxi(0, ceili(total * rule.get("percent", 0.0)))
					break

				var conditions: Array = rule.get("conditions", [])
				if conditions.is_empty():
					continue

				if _conditions_met(conditions, rule.get("match", "any"), food, wood, total, known):
					target = maxi(1, ceili(total * rule.get("percent", 0.0)))
					break

			result[role_name] = target

	if total >= _min_unassigned_threshold:
		result["Unassigned"] = maxi(result.get("Unassigned", 0), 1)

	return result


## Colony-wide knowledge of resource positions: does the Nest's Blackboard
## hold at least one entry of this type? Mirrors the per-agent
## known_food_position/known_wood_position Sensed Facts (agents/WorldState.gd)
## but answers "does anyone in the colony know", not "do I" - the Threshold
## Policy's own concern, since it reasons about the colony as a whole.
func _get_known_resource_types() -> Dictionary:
	var result := {"Food": false, "Wood": false}
	if _nest_ref == null or not _nest_ref.has_method("get_blackboard"):
		return result
	var blackboard: Node = _nest_ref.get_blackboard()
	if blackboard == null or not blackboard.has_method("get_entries"):
		return result
	result["Food"] = not blackboard.get_entries("Food").is_empty()
	result["Wood"] = not blackboard.get_entries("Wood").is_empty()
	return result


## A condition's level name gives its direction: "low" means at or below that
## threshold, "abundant" means at or above - so "Food low" and "Food abundant"
## read the same way they're written in the role JSON. "low" is a per-capita
## floor, not a flat number: the colony always tries to keep at least one
## unit of each resource in storage per agent, so the effective low threshold
## is never below the current agent count even when nest.json configures a
## smaller one - this floor lives only here, not in nest.gd's own copy (see
## ADR 11). "known"/"unknown" are a separate axis - not a numeric threshold
## against nest.json at all, but whether the colony's Blackboard holds any
## entry of that resource type (the colony-wide counterpart of "known").
func _conditions_met(conditions: Array, match_mode: String, food: int, wood: int, total_agents: int, known: Dictionary) -> bool:
	var require_all: bool = match_mode == "all"

	for cond in conditions:
		var res_type: String = cond.get("type", "")
		var level_name: String = cond.get("level", "low")
		var resource_val: int = food if res_type == "Food" else wood

		var condition_met: bool
		if level_name == "known":
			condition_met = known.get(res_type, false)
		elif level_name == "unknown":
			condition_met = not known.get(res_type, false)
		elif level_name == "abundant":
			condition_met = resource_val >= get_threshold(res_type, "abundant", 0)
		else:
			var low_threshold: int = maxi(get_threshold(res_type, "low", 0), total_agents)
			condition_met = resource_val <= low_threshold

		if require_all and not condition_met:
			return false
		if not require_all and condition_met:
			return true

	return require_all
