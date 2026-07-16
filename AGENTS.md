# AGENTS.md

## What This Is

Godot 4.7 GDScript project: a data-driven multi-agent system with GOAP planning and dynamic role assignment. See `ARCHITECTURE_SPECIFICATION.md` for the full architecture spec — it is the authoritative reference for design intent.

**Status:** Early stage (Phase 1-2). Many files are stubs (e.g. `organization_manager.gd`, `role_component.gd`, `goal_selector.gd` are empty `_ready()` passes).

## Engine & Runtime

- Engine: Godot 4.7, GDScript, Forward Plus renderer, Jolt Physics
- Entry scene: `Main.tscn` → `main.gd`
- Display: canvas_items stretch mode, expand aspect
- Windows rendering driver: d3d12
- No package manager, no external dependencies

## How to Validate Changes

There is no test framework, linter, or CI set up. Validation means:
1. Open the project in the Godot 4.7 editor and run the main scene
2. Or run headless: `godot --headless --scene Main.tscn` (no assertions — check for script errors in output)

## Key Architecture Facts

- **Organization Manager** (`organization/organization_manager.gd`): intended as an autoload singleton, but currently a stub. Will own role assignments, colony storage, agent registry.
- **Config-driven**: all role/goal/action/resource/simulation definitions live in `configs/` as JSON. New roles should be added via JSON only — no engine code changes per the extensibility requirement.
- **Config loading**: `simulation/config_loader.gd` provides `load_json(path)`. However, `resource_manager.gd` uses raw `FileAccess.open("res://configs/...")` directly — both patterns exist.
- **Navigation**: all agent movement goes through `NavigationServer2D`. Agents use `NavigationAgent2D` child nodes. Map bounds are hardcoded in `resource_manager.gd` as `MAP_MIN=(32,32)` / `MAP_MAX=(1120,616)`.
- **Resources**: `ResourceNode` (class_name) is the only node with a registered global class. Resource respawning is handled by `ResourceManager` with `respawnTime` from JSON config.
- **Scene tree**: `Main.tscn` contains `Simulation` → `NavigationRegion`, `Agent`, `FoodNode`, `Nest`.

## File Structure

```
configs/          JSON definitions (roles/, goals/, actions/, resources.json, simulation.json)
agents/           agent.gd (CharacterBody2D), role_component.gd, goal_selector.gd
organization/     organization_manager.gd (stub), nest.gd
resources/        resource_node.gd (ResourceNode class), resource_manager.gd
pheromones/       (empty or minimal)
enemies/          (empty or minimal)
metrics/          (empty or minimal)
ui/               (empty or minimal)
simulation/       simulation.gd, config_loader.gd
```

## Gotchas

- `.uid` files are Godot-generated per script — do not edit or delete them, and do not commit them if they change unexpectedly.
- `.godot/` is gitignored (editor cache, imports, shaders).
- Role JSON configs (`configs/roles/*.json`) currently have empty `allowedGoals`/`allowedActions` arrays — these need populating as implementation progresses.
- `resource_manager.gd` spawns resources at random positions within hardcoded map bounds — these bounds must match the NavigationRegion walkable area or resources may spawn in unwalkable space.
- No `.godot` export templates or platform configs are checked in.

## Agent skills

### Issue tracker

Local markdown — issues live as files under `.scratch/<feature>/` in this repo. No external PR triage. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` at repo root, ADRs in `docs/adr/`. See `docs/agents/domain.md`.
