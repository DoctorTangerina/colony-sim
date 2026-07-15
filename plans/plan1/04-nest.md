# 04 — Nest (`organization/nest.gd`)

## What to do

Create `nest.gd` attached to a `StaticBody2D` (or `Area2D`) node in the scene.

### Properties

```gdscript
var food_storage: int = 0
var wood_storage: int = 0
```

### Methods

```gdscript
func deposit(resource_type: String, amount: int) -> void
```

- If `resource_type == "Food"`, add `amount` to `food_storage`.
- If `resource_type == "Wood"`, add `amount` to `wood_storage`.
- Print a debug line confirming the deposit.

```gdscript
func get_storage_summary() -> Dictionary
```

- Returns `{"Food": food_storage, "Wood": wood_storage}`.

### Scene Setup

- Place the Nest node in `Simulation.tscn` at a fixed position (e.g., center of the map).
- Give it a colored sprite (e.g., brown hexagon or house icon) so it is visually identifiable.

## Why

The nest is the central hub — resource deposit and storage are required before any gathering logic can work.

## Verification

- Calling `nest.deposit("Food", 5)` increases `food_storage` to 5.
- `get_storage_summary()` returns the correct dictionary.
- The nest sprite is visible in the running scene.
