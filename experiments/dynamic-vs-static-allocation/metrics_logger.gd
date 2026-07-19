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

var _nest: Node = null
var _om: Node = null
var _file: FileAccess = null

var _elapsed: float = 0.0
var _sample_timer: float = 0.0
var _duration: float = DEFAULT_DURATION


func setup(nest: Node, om: Node) -> void:
	_nest = nest
	_om = om
	_duration = ExperimentCLI.get_float("duration", DEFAULT_DURATION)
	_open_file()


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
	]))


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

	_file.store_csv_line(PackedStringArray([
		"%.2f" % _elapsed,
		str(food),
		str(wood),
		JSON.stringify(role_counts),
		str(role_changes),
		str(deposits),
	]))


func _close_and_quit() -> void:
	if _file:
		_file.flush()
		_file.close()
		_file = null
	get_tree().quit()
