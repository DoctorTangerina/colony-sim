# 01 — Project Scaffold

## What to do

1. Create a new Godot 4.7 project in the `Smas/` directory.
2. Create the following subdirectories inside the project root:

```
agents/
organization/
resources/
pheromones/
enemies/
metrics/
ui/
configs/
  roles/
  goals/
  actions/
  resources/
simulation/
```

3. Create a `Simulation.tscn` scene:
   - Root node: `Node2D` named `Simulation`
   - Add a child `NavigationRegion2D` named `NavigationRegion`
   - Draw a simple polygon on its `NavigationPolygon` resource (e.g., a rectangle covering the visible area)
   - Bake the navigation polygon

4. Save `Simulation.tscn` in the `simulation/` folder.

5. Create placeholder `.gd` files for the main systems (empty scripts is fine):

```
agents/agent.gd
agents/role_component.gd
agents/goal_selector.gd
organization/organization_manager.gd
organization/nest.gd
resources/resource_node.gd
resources/resource_manager.gd
simulation/simulation.gd
```

## Why

Establishes the folder layout, the main scene, and the navigation mesh so all subsequent work has a home.

## Verification

- Project opens in Godot 4.7 with no errors.
- `Simulation.tscn` can be opened in the editor.
- The `NavigationRegion2D` shows a baked navigation polygon.
