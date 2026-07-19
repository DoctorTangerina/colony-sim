class_name ExploredTrail
extends Node

## Colony-shared, Nest-owned record of recently-visited positions (CONTEXT.md:
## Explored Trail; ADR 9). Structurally mirrors Blackboard's shape
## (timestamped positions, distance-tolerance dedup) but tracks ground
## coverage, not resource discoveries - kept as its own array, never mixed
## into the Blackboard's entries. Written directly from the field by any
## agent's passive, continuous, role-blind movement (agent.gd calls
## mark_visited every frame regardless of role) - read only by target
## selection for an Explore-style goal, via pick_target. Never referenced by
## any Goal or Action precondition/effect: freshness here is a
## target-selection-time concern, not something the Planner reasons about.

var _entries: Array[Dictionary] = []

const DEDUP_TOLERANCE: float = 50.0
const CANDIDATE_COUNT: int = 12


## Refreshes an existing nearby entry's timestamp instead of duplicating it -
## an agent lingering in or repeatedly crossing one spot collapses to a
## single, recency-updated entry, and total entries stay bounded by map area
## rather than growing with every frame's write.
func mark_visited(position: Vector2) -> void:
	for e in _entries:
		if e["position"].distance_to(position) < DEDUP_TOLERANCE:
			e["timestamp"] = Time.get_ticks_msec()
			return
	_entries.append({"position": position, "timestamp": Time.get_ticks_msec()})


func is_covered(position: Vector2, tolerance: float = DEDUP_TOLERANCE) -> bool:
	for e in _entries:
		if e["position"].distance_to(position) < tolerance:
			return true
	return false


## Picks an exploration target inside bounds, biased away from recently-
## covered ground: samples CANDIDATE_COUNT random candidates and keeps
## whichever sits farthest from its own nearest Explored Trail entry
## (uncovered ground scores highest). An entirely-fresh trail has no entries,
## so every candidate ties on "infinitely far" and the first one wins -
## equivalent to today's plain uniform random pick.
func pick_target(bounds: Rect2) -> Vector2:
	var best_pos: Vector2 = _random_point(bounds)
	var best_score: float = _distance_to_nearest(best_pos)
	for i in range(CANDIDATE_COUNT - 1):
		var candidate := _random_point(bounds)
		var score := _distance_to_nearest(candidate)
		if score > best_score:
			best_score = score
			best_pos = candidate
	return best_pos


func _distance_to_nearest(position: Vector2) -> float:
	var nearest: float = INF
	for e in _entries:
		nearest = minf(nearest, e["position"].distance_to(position))
	return nearest


func _random_point(bounds: Rect2) -> Vector2:
	return Vector2(
		randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
		randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
	)


func get_entry_count() -> int:
	return _entries.size()
