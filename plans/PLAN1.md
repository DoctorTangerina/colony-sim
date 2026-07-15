# Plan 1 — Phase 1: Core Simulation

## Goal

Establish the minimal running simulation: a 2D Godot scene with agents that move, resource nodes that exist in the world, and a nest that stores deposited resources.

## Deliverables

### 1. Project Scaffold

- Create a Godot 4.7 project with the folder structure from the spec (agents/, organization/, resources/, pheromones/, enemies/, metrics/, ui/, configs/, simulation/).
- Set up the main `Simulation` scene as the entry point, with a `Node2D` root.
- Add a `NavigationRegion2D` with a predefined polygon map.

### 2. Agent (`agents/agent.gd`)

- An `Area2D` (or `CharacterBody2D`) with:
  - `agent_id: String`
  - `position: Vector2`
  - `energy: float`
  - `hunger: float`
  - `held_item: String` (None / Food / Wood)
- A reference to a `NavigationAgent2D` for pathfinding.
- A `_process(delta)` that moves the agent along the current navigation path.
- Placeholder state machine slots: `current_role`, `current_goal`, `current_plan`.

### 3. Navigation

- Use `NavigationServer2D` baked on a `NavigationRegion2D`.
- `NavigationAgent2D` on each agent.
- Agents can request a path to any `Vector2` target and steer toward it.

### 4. Nest (`organization/nest.gd`)

- A `StaticBody2D` (or `Area2D`) positioned on the map.
- Inventory:
  - `food_storage: int`
  - `wood_storage: int`
- Methods:
  - `deposit(resource_type: String, amount: int) -> void`
  - `get_storage_summary() -> Dictionary`

### 5. Resource Nodes (`resources/resource_node.gd`)

- A `StaticBody2D` (or `Area2D`) placed on the map.
- Properties:
  - `resource_type: String` (Food / Wood)
  - `remaining_amount: int`
  - `position: Vector2`
- On depletion, signal the `ResourceManager` to respawn elsewhere.

### 6. Resource Manager (`resources/resource_manager.gd`)

- A plain `Node` (not autoload) that:
  - Spawns initial resource nodes.
  - Guarantees at least one Food and one Wood node alive.
  - Handles respawn logic (pick new random position, create a new node).

### 7. JSON Configs (minimal)

- `configs/simulation.json`
  - `enableEnemies`, `enableDynamicRoles`, `simulationSpeed`
- `configs/resources.json`
  - Array of resource type definitions with `type`, `maxAmount`, `respawnTime`
- `configs/roles/explorer.json`, `gatherer.json`, `guard.json`
  - Basic role definitions (only `name` and empty arrays for now — extended in Phase 3)
- `configs/goals/goals.json`
  - Goal definitions with names and preconditions/effects (stubs for Phase 2)

### 8. Visual Verification

- A simple `Main` scene that instantiates the `Simulation` node.
- Place a few agent sprites (colored squares), a nest sprite, and resource sprites on the map.
- Agents should be able to move to a hardcoded target (demonstrating navigation works).

## Non-Goals (for this phase)

- GOAP planning (Phase 2)
- Role permissions / goal selection (Phase 3)
- Organization manager logic (Phase 4)
- Pheromones (Phase 5)
- Enemies (Phase 6)
- Metrics (Phase 7)
- Debug UI panels (Phase 8)
- Any dynamic behavior — all agent movement is script-driven or manually targeted.

## Dependencies

- Godot 4.7 installed and functional.
- The project must open, run, and show the 2D scene with moving agents.

## Acceptance Check

1. The project opens in Godot 4.7 without errors.
2. Agent sprites are visible on the map.
3. Agents move to a navigable target when given a position.
4. Resource nodes appear in the world with correct type labels.
5. Nest accepts deposits (verified via print or debug log).
6. When a resource node is depleted, a new one spawns elsewhere.

## Next Phase

After Phase 1 is verified, proceed to **Phase 2: GOAP** — implementing Goals, Actions, and the Planner.
