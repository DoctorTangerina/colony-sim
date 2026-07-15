# 07 — JSON Configs

## What to do

Create the following JSON files under `configs/`.

### `configs/simulation.json`

```json
{
  "enableEnemies": true,
  "enableDynamicRoles": true,
  "simulationSpeed": 1.0
}
```

### `configs/resources.json`

```json
[
  {
    "type": "Food",
    "maxAmount": 100,
    "respawnTime": 20
  },
  {
    "type": "Wood",
    "maxAmount": 100,
    "respawnTime": 20
  }
]
```

### `configs/roles/explorer.json`

```json
{
  "name": "Explorer",
  "allowedGoals": [],
  "allowedActions": [],
  "priorityModifiers": {}
}
```

### `configs/roles/gatherer.json`

```json
{
  "name": "Gatherer",
  "allowedGoals": [],
  "allowedActions": [],
  "priorityModifiers": {}
}
```

### `configs/roles/guard.json`

```json
{
  "name": "Guard",
  "allowedGoals": [],
  "allowedActions": [],
  "priorityModifiers": {}
}
```

### `configs/goals/goals.json`

```json
[
  { "name": "Explore", "preconditions": {}, "effects": {} },
  { "name": "DiscoverResource", "preconditions": {}, "effects": {} },
  { "name": "CollectFood", "preconditions": {}, "effects": {} },
  { "name": "CollectWood", "preconditions": {}, "effects": {} },
  { "name": "DepositResource", "preconditions": {}, "effects": {} },
  { "name": "DefendNest", "preconditions": {}, "effects": {} },
  { "name": "AttackEnemy", "preconditions": {}, "effects": {} },
  { "name": "Eat", "preconditions": {}, "effects": {} },
  { "name": "Rest", "preconditions": {}, "effects": {} },
  { "name": "ReturnToNest", "preconditions": {}, "effects": {} }
]
```

### `configs/actions/actions.json`

```json
[
  { "name": "MoveTo", "cost": 1.0 },
  { "name": "Eat", "cost": 1.0 },
  { "name": "Rest", "cost": 1.0 },
  { "name": "ReturnToNest", "cost": 1.0 },
  { "name": "RandomExplore", "cost": 1.0 },
  { "name": "LayReturnPheromone", "cost": 1.0 },
  { "name": "LayResourcePheromone", "cost": 1.0 },
  { "name": "ReportResource", "cost": 1.0 },
  { "name": "FollowPheromone", "cost": 1.0 },
  { "name": "PickupResource", "cost": 1.0 },
  { "name": "DepositResource", "cost": 1.0 },
  { "name": "PatrolNest", "cost": 1.0 },
  { "name": "AttackTarget", "cost": 1.0 }
]
```

### GDScript Loader (optional for Phase 1, recommended to stub now)

Create a simple `ConfigLoader` autoload or helper:

```gdscript
# simulation/config_loader.gd
static func load_json(path: String) -> Dictionary:
    var file = FileAccess.open(path, FileAccess.READ)
    var text = file.get_as_text()
    return JSON.parse_string(text)
```

This will be used in later phases but is harmless to add now.

## Why

Keeps all configuration data-driven per spec §2.4. Even though roles/goals/actions are empty stubs, the files and structure are ready for Phase 2 and 3.

## Verification

- All JSON files parse correctly (valid JSON, no trailing commas).
- `ConfigLoader.load_json()` returns the expected dictionary/array for any config file.
