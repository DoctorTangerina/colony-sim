# 06 — Resource Manager (`resources/resource_manager.gd`)

## What to do

Create `resource_manager.gd` as a plain `Node` (not autoload). It is instantiated as a child of `Simulation`.

### Properties

```gdscript
var resource_definitions: Dictionary   # loaded from JSON
var active_nodes: Array                # Array of ResourceNode instances
```

### Methods

```gdscript
func _ready()
```

- Reads `configs/resources.json`.
- Spawns initial resource nodes: one Food node and one Wood node at random positions.
- Stores them in `active_nodes`.

---

```gdscript
func _on_resource_depleted(node: ResourceNode)
```

- Removes `node` from `active_nodes`.
- Calls `respawn(node.resource_type)`.

---

```gdscript
func respawn(resource_type: String)
```

- Waits `respawnTime` seconds (from config).
- Picks a random valid position on the navigation map.
- Instantiates a new `ResourceNode` of that type.
- Re-adds to `active_nodes`.

---

```gdscript
func get_nearest_resource(from_position: Vector2, resource_type: String) -> ResourceNode
```

- Returns the closest active node of the given type (useful in later phases).

### Guarantee

After any respawn, ensure at least one Food and one Wood node exist. If both are depleted simultaneously, spawn both.

## Why

Keeps resource lifecycle decoupled from individual nodes. The guarantee prevents the world from running out of resources.

## Verification

- On scene start, one Food and one Wood node exist.
- When a node is depleted, a new one spawns after the configured `respawnTime`.
- If all nodes of one type are depleted, a replacement is created.
- The `ResourceManager` never lets the count of Food or Wood nodes drop to zero permanently.
