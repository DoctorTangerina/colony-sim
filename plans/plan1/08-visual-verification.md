# 08 — Visual Verification

## What to do

Create a `Main.tscn` and `Main.gd` that serves as the entry point and verifies everything works.

### Scene Setup

1. Create `Main.tscn`:
   - Root: `Node` named `Main`.
   - Instance `Simulation.tscn` as a child.

2. In `Simulation.tscn`, add:
   - A `Nest` node with a brown sprite at a fixed position.
   - At least 2 `Agent` instances with colored sprites (e.g., blue squares) placed near the nest.
   - A `ResourceManager` node.
   - At least one `ResourceNode` (Food) and one `ResourceNode` (Wood) at distinct positions.

### Script (`Main.gd`)

```gdscript
extends Node

func _ready():
    # Test 1: Agent moves to a target
    await get_tree().create_timer(1.0).timeout
    var agent = $Simulation/Agent  # or get the first agent
    var target = Vector2(500, 300)
    agent.move_to(target)

    # Test 2: Agent moves to resource node
    await get_tree().create_timer(3.0).timeout
    var resource = $Simulation/ResourceNode
    agent.move_to(resource.global_position)

    # Test 3: Deposit into nest
    await get_tree().create_timer(3.0).timeout
    var nest = $Simulation/Nest
    nest.deposit("Food", 10)
    nest.deposit("Wood", 5)
    print("Storage: ", nest.get_storage_summary())

    # Test 4: Deplete a resource node
    await get_tree().create_timer(1.0).timeout
    resource.remaining_amount = 1
    resource.extract(1)   # triggers depletion and respawn
```

### Manual Verification Checklist

Run the project and observe:

- [ ] Window opens with a 2D scene.
- [ ] Nest sprite is visible (brown).
- [ ] Agent sprites are visible (blue).
- [ ] Resource sprites are visible (green for Food, brown for Wood).
- [ ] After 1 second, the first agent moves toward the target point.
- [ ] After 3 more seconds, the agent moves toward the resource node.
- [ ] Console shows deposit messages from the nest.
- [ ] Console shows depletion and respawn messages.
- [ ] A new resource node appears after the old one is depleted.

## Why

This step ties everything together and confirms the Phase 1 deliverables are working. It is the acceptance test for the entire phase.

## If Something Fails

- **Agent doesn't move**: Check `NavigationAgent2D` setup, navigation polygon baking, `move_and_slide()` call in `_process()`.
- **Resource node doesn't respawn**: Check signal connection from `depleted` to `ResourceManager._on_resource_depleted`.
- **Deposit doesn't work**: Check the `deposit()` implementation and the type string matching.
