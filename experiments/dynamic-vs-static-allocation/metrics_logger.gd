class_name MetricsLogger
extends Node

## ADR 12: samples the Nest and OrganizationManager on a fixed interval and
## writes one CSV row per sample to results/, tagged by this run's swept
## parameters (agent count, respawn time, distribution mode, seed). Only
## instanced by simulation.gd when --log-metrics is passed - a normal
## interactive run never touches the filesystem for this. Rows are raw
## counters only (no derived recovery-time/churn-rate/throughput-rate
## columns) - Ticket 04's offline analysis script computes those from the
## time series, so the same derivation logic doesn't have to be written
## twice in two languages.

const RESULTS_DIR := "res://experiments/dynamic-vs-static-allocation/results"
const SAMPLE_INTERVAL: float = 1.0
const DEFAULT_DURATION: float = 600.0  # 10 simulated minutes, per ADR 12

## ADR 12 amendment: which Action Verified names count toward the transition
## latency metric - Eat deliberately excluded (serves the agent's own
## survival, not its new role's output). Scoped to MetricsLogger on purpose:
## agent.gd/GoapCycle.gd's action_verified signal stays generic.
const _LATENCY_ACTIONS: Array = ["DepositResource", "ReportResource", "ReportDepletion"]

var _nest: Node = null
var _om: Node = null
var _file: FileAccess = null
var _events_file: FileAccess = null

var _elapsed: float = 0.0
var _sample_timer: float = 0.0
var _duration: float = DEFAULT_DURATION

## ADR 12 amendment: last-observed known/unknown state per resource type,
## mirroring the same Blackboard-emptiness check organization_manager.gd's
## _get_known_resource_types() already does colony-side - tracked here only
## to detect the false->true flip (a genuine discovery), since
## entries_changed also fires on Depletion Report removals.
var _known_state: Dictionary = {"Food": false, "Wood": false}


func setup(nest: Node, om: Node, agents: Array) -> void:
	_nest = nest
	_om = om
	_duration = ExperimentCLI.get_float("duration", DEFAULT_DURATION)
	_open_file()
	_open_events_file()
	_connect_agents(agents)
	_connect_blackboard()


func _connect_agents(agents: Array) -> void:
	for agent in agents:
		if agent.has_signal("role_changed"):
			agent.role_changed.connect(_on_role_changed)
		if agent.has_signal("action_verified"):
			agent.action_verified.connect(_on_action_verified.bind(agent.agent_id))
		if agent.has_signal("agent_died"):
			agent.agent_died.connect(_on_agent_died)


func _connect_blackboard() -> void:
	if _nest == null or not _nest.has_method("get_blackboard"):
		return
	var blackboard: Node = _nest.get_blackboard()
	if blackboard == null or not blackboard.has_signal("entries_changed"):
		return
	for res_type in _known_state.keys():
		_known_state[res_type] = not blackboard.get_entries(res_type).is_empty()
	blackboard.entries_changed.connect(_on_blackboard_changed.bind(blackboard))


func _on_blackboard_changed(_entries: Array, blackboard: Node) -> void:
	for res_type in _known_state.keys():
		var known: bool = not blackboard.get_entries(res_type).is_empty()
		if known and not _known_state[res_type]:
			_write_event({
				"event": "discovery",
				"resource_type": res_type,
				"timestamp": _elapsed,
			})
		_known_state[res_type] = known


func _on_agent_died(agent_id: String, last_role: String) -> void:
	_write_event({
		"event": "death",
		"agent_id": agent_id,
		"timestamp": _elapsed,
		"last_role": last_role,
		"food_storage": _nest.get_storage("Food") if _nest else 0,
		"wood_storage": _nest.get_storage("Wood") if _nest else 0,
	})


func _on_role_changed(agent_id: String, old_role: String, new_role: String) -> void:
	_write_event({
		"event": "role_changed",
		"agent_id": agent_id,
		"timestamp": _elapsed,
		"old_role": old_role,
		"new_role": new_role,
	})


func _on_action_verified(action_name: String, agent_id: String) -> void:
	if action_name not in _LATENCY_ACTIONS:
		return
	_write_event({
		"event": "action_verified",
		"agent_id": agent_id,
		"timestamp": _elapsed,
		"action_name": action_name,
	})


func _open_file() -> void:
	DirAccess.make_dir_recursive_absolute(RESULTS_DIR)
	var path := "%s/%s.csv" % [RESULTS_DIR, _build_run_tag()]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("MetricsLogger: could not open %s for writing (error %s)" % [path, FileAccess.get_open_error()])
		return
	_file.store_csv_line(PackedStringArray([
		"timestamp", "food_storage", "wood_storage",
		"role_counts_json", "cumulative_role_changes", "cumulative_deposits",
		"pending_role_requests",
	]))


func _open_events_file() -> void:
	DirAccess.make_dir_recursive_absolute(RESULTS_DIR)
	var path := "%s/%s_events.jsonl" % [RESULTS_DIR, _build_run_tag()]
	_events_file = FileAccess.open(path, FileAccess.WRITE)
	if _events_file == null:
		push_error("MetricsLogger: could not open %s for writing (error %s)" % [path, FileAccess.get_open_error()])


func _write_event(event: Dictionary) -> void:
	if _events_file == null:
		return
	_events_file.store_line(JSON.stringify(event))


func _build_run_tag() -> String:
	var agent_count := ExperimentCLI.get_int("agent-count", 8)
	var respawn_time := ExperimentCLI.get_float("respawn-time", 20.0)
	var distribution_mode := ExperimentCLI.get_string("distribution-mode", "dynamic")
	var run_seed := ExperimentCLI.get_int("seed", -1)
	return "pop%d_respawn%s_%s_seed%d" % [agent_count, respawn_time, distribution_mode, run_seed]


func _process(delta: float) -> void:
	if _file == null:
		return

	_elapsed += delta
	_sample_timer += delta

	if _sample_timer >= SAMPLE_INTERVAL:
		_sample_timer = 0.0
		_write_sample()

	if _elapsed >= _duration:
		_write_sample()
		_close_and_quit()


func _write_sample() -> void:
	var role_counts: Dictionary = _om.get_role_counts() if _om else {}
	var role_changes: int = _om.get_role_change_log().size() if _om else 0
	var deposits: int = _nest.get_deposit_count() if _nest else 0
	var food: int = _nest.get_storage("Food") if _nest else 0
	var wood: int = _nest.get_storage("Wood") if _nest else 0
	var pending_requests: int = _om.get_total_request_count() if _om else 0

	_file.store_csv_line(PackedStringArray([
		"%.2f" % _elapsed,
		str(food),
		str(wood),
		JSON.stringify(role_counts),
		str(role_changes),
		str(deposits),
		str(pending_requests),
	]))


func _close_and_quit() -> void:
	if _file:
		_file.flush()
		_file.close()
		_file = null
	if _events_file:
		_events_file.flush()
		_events_file.close()
		_events_file = null
	get_tree().quit()
