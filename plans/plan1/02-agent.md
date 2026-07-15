# 02 — Agent (`agents/agent.gd`)

## What to do

Implement `agent.gd` as a `CharacterBody2D` (or `Area2D`) with:

### Properties

```gdscript
var agent_id: String
var energy: float = 100.0
var hunger: float = 0.0
var held_item: String = "None"       # "None" | "Food" | "Wood"
var current_role: String = ""
var current_goal: String = ""
var current_plan: Array = []          # Placeholder for Phase 2
```

### Navigation

- Add a `NavigationAgent2D` child node named `NavAgent`.
- Store a `target_position: Vector2` variable.
- Provide a `move_to(target: Vector2)` method that sets `target_position` and requests a path from `NavAgent`.
- In `_process(delta)`:
  - If `NavAgent.is_navigation_finished()`, stop.
  - Otherwise, read `NavAgent.get_next_path_position()`, compute direction, and move via `move_and_slide()`.
- Use `NavigationServer2D.map_get_closest_point()` for initial target validation (optional but helpful).

### Signals (optional, for future use)

- `arrived_at_target`
- `item_changed(new_item: String)`

## Why

Gives agents the ability to move around the map, which is the fundamental behavior everything else builds on.

## Verification

- An agent placed in the scene can be given a `move_to()` call via the inspector or a test script.
- The agent moves along the navigation mesh toward the target and stops when it arrives.
