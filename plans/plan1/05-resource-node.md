# 05 — Resource Node (`resources/resource_node.gd`)

## What to do

Create `resource_node.gd` attached to a `StaticBody2D` (or `Area2D`) placed on the map.

### Properties

```gdscript
var resource_type: String       # "Food" | "Wood"
var remaining_amount: int
var position: Vector2           # (redundant with global_position, useful for data)
```

### Signals

```gdscript
signal depleted(node: ResourceNode)
```

### Behavior

- When `remaining_amount` reaches 0, emit `depleted(self)` and queue_free().
- Provide a method for agents to extract resources:
  ```gdscript
  func extract(amount: int) -> int
  ```
  - Reduces `remaining_amount` by `amount` (clamped to 0).
  - Returns the actual amount extracted.
  - If depleted, emits the signal.

### Scene Setup

- Give the node a sprite:
  - Green circle for Food
  - Brown rectangle for Wood
- Optionally overlay a label showing remaining amount.

## Why

Resource nodes are what agents interact with. The extraction interface is needed by gatherers in later phases.

## Verification

- A resource node placed in the scene displays the correct sprite.
- Calling `extract(10)` reduces `remaining_amount` and returns the correct value.
- When `remaining_amount` reaches 0, the `depleted` signal fires and the node disappears.
