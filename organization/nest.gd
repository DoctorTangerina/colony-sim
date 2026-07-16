extends Node2D

signal storage_low(resource_type: String)
signal storage_abundant(resource_type: String)

var food_storage: int = 0
var wood_storage: int = 0
var _thresholds: Dictionary = {}
var _storage_states: Dictionary = {}
var _blackboard: Node = null


func _ready() -> void:
	_load_thresholds()
	_blackboard = $Blackboard
	_setup_blackboard_cleanup()


func _load_thresholds() -> void:
	var data: Dictionary = ConfigLoader.load_dict("res://configs/nest.json")
	_thresholds = data.get("thresholds", {})
	var zone: Area2D = $TriggerZone
	var shape: CollisionShape2D = zone.get_node_or_null("CollisionShape2D")
	if shape and shape.shape:
		(shape.shape as CircleShape2D).radius = data.get("triggerZoneRadius", 50.0)


func deposit(resource_type: String, amount: int) -> void:
	if resource_type == "Food":
		food_storage += amount
		_check_thresholds("Food", food_storage)
	elif resource_type == "Wood":
		wood_storage += amount
		_check_thresholds("Wood", wood_storage)


func get_storage_summary() -> Dictionary:
	return {"Food": food_storage, "Wood": wood_storage}


func get_storage(resource_type: String) -> int:
	if resource_type == "Food":
		return food_storage
	elif resource_type == "Wood":
		return wood_storage
	return 0


func get_threshold(resource_type: String, key: String, default_val: int = 0) -> int:
	var thresh: Dictionary = _thresholds.get(resource_type, {})
	return thresh.get(key, default_val)


func _check_thresholds(resource_type: String, current: int) -> void:
	var thresh: Dictionary = _thresholds.get(resource_type, {})
	if thresh.is_empty():
		return

	var low: int = thresh.get("low", 10)
	var abundant: int = thresh.get("abundant", 50)

	var was_low: bool = _storage_states.get(resource_type + "_low", false)
	var was_abundant: bool = _storage_states.get(resource_type + "_abundant", false)

	var is_low: bool = current <= low
	var is_abundant: bool = current >= abundant

	if is_low and not was_low:
		storage_low.emit(resource_type)
	if is_abundant and not was_abundant:
		storage_abundant.emit(resource_type)

	_storage_states[resource_type + "_low"] = is_low
	_storage_states[resource_type + "_abundant"] = is_abundant


func get_trigger_zone() -> Area2D:
	return $TriggerZone as Area2D


func get_blackboard() -> Node:
	return _blackboard


func _setup_blackboard_cleanup() -> void:
	var timer := Timer.new()
	timer.name = "BlackboardCleanupTimer"
	timer.wait_time = 5.0
	timer.autostart = true
	timer.timeout.connect(_on_blackboard_cleanup_timeout)
	add_child(timer)


func _on_blackboard_cleanup_timeout() -> void:
	if _blackboard == null:
		return
	var rm = get_node_or_null("/root/Simulation/ResourceManager")
	if rm and _blackboard.has_method("clean_stale_entries"):
		_blackboard.clean_stale_entries(rm)
