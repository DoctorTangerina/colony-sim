extends Node2D

const AGENT_SCENE: PackedScene = preload("res://agents/agent.tscn")
const SPAWN_SCATTER_RADIUS: float = 40.0

var navigation_map: RID

func _ready() -> void:
	navigation_map = get_world_2d().navigation_map
	var rm = $ResourceManager
	var nest = $Nest

	_connect_resources(rm)
	var agents: Array = await _spawn_agents(nest, rm)
	_connect_om(nest)
	_maybe_start_metrics_logger(nest, agents)


func _connect_resources(rm: Node) -> void:
	for child in get_children():
		if child is ResourceNode:
			child.depleted.connect(rm._on_resource_depleted)


## Spawns `agentCount` agents near the Nest, all starting Unassigned. Waits
## for the navigation map to become queryable first - the same nav-sync race
## resource_manager.gd already guards against when spawning onto the navmesh.
## Returns the spawned agents (ADR 12: MetricsLogger needs the list to
## connect its per-agent signals - no bulk "all agent nodes" getter exists on
## OrganizationManager today, and adding one for this single opt-in consumer
## isn't worth it when the spawn loop already has the list for free).
func _spawn_agents(nest: Node2D, rm: Node) -> Array:
	var data: Dictionary = ConfigLoader.load_dict("res://configs/simulation.json")
	var agent_count: int = ExperimentCLI.get_int("agent-count", data.get("agentCount", 8))
	if agent_count <= 0:
		return []

	await _wait_for_navigation_map_ready(nest.global_position)

	var spawned: Array = []
	var spawn_parent: Node = $NavigationRegion
	for i in range(agent_count):
		var agent = AGENT_SCENE.instantiate()
		spawn_parent.add_child(agent)
		agent.global_position = nest.global_position + Vector2(
			randf_range(-SPAWN_SCATTER_RADIUS, SPAWN_SCATTER_RADIUS),
			randf_range(-SPAWN_SCATTER_RADIUS, SPAWN_SCATTER_RADIUS)
		)
		agent.setup(nest, rm)
		if agent.has_signal("agent_died"):
			agent.agent_died.connect(_on_agent_died)
		spawned.append(agent)

	return spawned


func _wait_for_navigation_map_ready(probe: Vector2) -> void:
	for _attempt in range(100):
		var changed_map: RID = await NavigationServer2D.map_changed
		if changed_map != navigation_map:
			continue
		if NavigationServer2D.map_get_closest_point(navigation_map, probe) != Vector2.ZERO:
			return
	push_error("simulation: navigation map never became queryable; agents may spawn at (0,0)")


func _connect_om(nest: Node2D) -> void:
	var om = get_node_or_null("/root/OrganizationManager")
	if om and om.has_method("setup"):
		om.setup(nest)


## ADR 12: opt-in only - a normal interactive run passes no --log-metrics
## flag and never instances this, never touches the filesystem for it.
func _maybe_start_metrics_logger(nest: Node2D, agents: Array) -> void:
	if not ExperimentCLI.has_flag("log-metrics"):
		return
	var om := get_node_or_null("/root/OrganizationManager")
	var logger := MetricsLogger.new()
	logger.name = "MetricsLogger"
	add_child(logger)
	logger.setup(nest, om, agents)


func _on_agent_died(agent_id: String, _last_role: String) -> void:
	var om = get_node_or_null("/root/OrganizationManager")
	if om and om.has_method("handle_agent_death"):
		om.handle_agent_death(agent_id)
