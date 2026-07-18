extends Node

signal role_changed(old_role: String, new_role: String)

const GLOBAL_ACTIONS: Array = ["Eat", "Rest"]

var _role_name: String = ""
var _allowed_goals: Array = []
var _allowed_actions: Array = []
var _priority_modifiers: Dictionary = {}


func _ready() -> void:
	pass


func load_role(role_name: String) -> void:
	var old_role := _role_name
	_role_name = role_name

	if role_name.is_empty() or role_name == "Unassigned":
		_allowed_goals = []
		_allowed_actions = []
		_priority_modifiers = {}
		role_changed.emit(old_role, role_name)
		return

	var path := "res://configs/roles/%s.json" % role_name.to_lower()
	var data: Dictionary = ConfigLoader.load_dict(path)
	if data.is_empty():
		push_warning("RoleComponent: Could not load role config: %s" % path)
		_allowed_goals = []
		_allowed_actions = []
		_priority_modifiers = {}
		return

	_allowed_goals = data.get("allowedGoals", [])
	_allowed_actions = data.get("allowedActions", [])
	_priority_modifiers = data.get("priorityModifiers", {})
	role_changed.emit(old_role, role_name)


func get_role_name() -> String:
	return _role_name


func get_allowed_goals() -> Array:
	return _allowed_goals


func get_allowed_actions() -> Array:
	var combined := _allowed_actions.duplicate()
	for action in GLOBAL_ACTIONS:
		if not action in combined:
			combined.append(action)
	return combined


func get_priority_modifier(goal_name: String) -> float:
	return _priority_modifiers.get(goal_name, 1.0)


func has_goal(goal_name: String) -> bool:
	return goal_name in _allowed_goals


func has_action(action_name: String) -> bool:
	return action_name in _allowed_actions or action_name in GLOBAL_ACTIONS
