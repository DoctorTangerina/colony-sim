# 03 — Navigation

## What to do

This step configures the Godot navigation system. It is mostly editor work on the `NavigationRegion2D` created in step 01.

1. Open `Simulation.tscn` and select the `NavigationRegion2D` node.
2. In the inspector:
   - Set `NavigationPolygon` to a new `NavigationPolygon` resource.
   - Click the polygon icon and draw a rectangle covering the play area (e.g., 1152 x 648).
   - Click **Bake NavigationPolygon**.
3. Ensure `NavigationAgent2D` is already a child of each agent (set up in step 02).

### NavigationServer2D Setup

In `simulation.gd` (or an autoload), ensure the navigation map is accessible:

```gdscript
var navigation_map: RID

func _ready():
    navigation_map = get_world_2d().navigation_map
```

This is optional for Phase 1, since `NavigationAgent2D` handles map lookup automatically. Include it as a convenience for future phases.

## Why

Godot's `NavigationServer2D` provides baked pathfinding that agents will follow. Getting this right early prevents movement bugs later.

## Verification

- Agents can successfully pathfind around static obstacles (if any were placed on the navigation polygon's outline).
- `NavAgent.get_next_path_position()` returns valid positions along the path.
- No "NavigationServer2D: NavigationMap not found" errors in the console.
