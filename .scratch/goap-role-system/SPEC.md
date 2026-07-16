# SPEC: GOAP Planning + Role System (Phases 2-3)

## Problem Statement

The simulation has Phase 1 working: agents navigate, resources exist with extraction, and the nest
stores deposits. But agents have no real decision-making — they move to hardcoded targets via the
test harness. The GOAP planner, goal selector, role component, and organization manager are all
stubs with empty `_ready()` passes. Role JSON configs have empty `allowedGoals`/`allowedActions`
arrays, and goal/action configs have no preconditions or effects.

To run dynamic-role experiments, the agent needs to: (a) evaluate goals against world state, (b)
plan sequences of actions to achieve them, (c) be constrained by a role that filters which goals
and actions are available, and (d) accept role changes from a queue at the nest — then replan
under the new role without human intervention.

## Solution

Implement the GOAP planning cycle on each agent (evaluate goals → select goal → build plan →
execute actions → monitor → replan if needed), powered by `configs/goals/goals.json` and
`configs/actions/actions.json` with full preconditions and effects. Implement the Role Component
as a policy filter: it receives a role definition from `configs/roles/*.json`, exposes a filtered
set of available goals and actions, and applies `priorityModifiers` during goal evaluation. The
agent reports role changes to the Organization Manager, which maintains counts per role and can
post role requests to a queue at the Nest for indirect assignment.

The architecture spec §2.2 (GOAP remains local), §2.3 (roles are policies), and ADR 0001 (indirect
assignment via request queue) are authoritative.

## User Stories

1. As a researcher, I want agents to evaluate goals against the current world state, so that they
   autonomously choose what to work on.

2. As a researcher, I want agents to build a plan (sequence of actions) to achieve a selected goal,
   so that they execute multi-step behaviors without human guidance.

3. As a researcher, I want agents to execute actions step-by-step from their plan, so that the
   plan becomes observable behavior in the simulation.

4. As a researcher, I want agents to re-evaluate and replan when their current goal becomes invalid
   or the plan fails, so that they recover without stalling.

5. As a researcher, I want the role component to filter the agent's available goals and actions
   based on the current role definition, so that agents behave within their role's permissions.

6. As a researcher, I want the role component to apply priority modifiers from the role definition
   during goal evaluation, so that some goals are more likely within a role.

7. As a researcher, I want the "Unassigned" role to allow zero goals and zero actions, so that
   unassigned agents stand still and recover energy.

8. As a researcher, I want the Organization Manager to manage a role-request queue that the Nest
   exposes as a physical proxy, so that agents can query and accept pending role requests.

9. As a researcher, I want the Nest to detect agent proximity via an Area2D trigger zone, so that
   agents can query the role-request queue only when physically near the nest.

10. As a researcher, I want an agent that finishes its current action to check the queue when
    touching the nest, accept any compatible role request, and set the Role Cooldown.

11. As a researcher, I want an agent that accepts a role request to immediately clear its current
    goal and plan, then select a new goal compatible with the new role.

12. As a researcher, I want the agent to ignore role requests that match its current role, so that
    same-role queue entries are no-ops.

13. As a researcher, I want the Role Cooldown (configurable, default 10s) to prevent an agent from
    accepting another role request too soon, so that role flapping is controlled.

14. As a researcher, I want the OM to evaluate the colony's role needs every `roleEvalInterval`
    (configurable, default 1s), so that role requests reflect current colony conditions.

15. As a researcher, I want the OM to compute a target role distribution using ratios derived from
    the Nest's resource thresholds, so that role requests are driven by colony need — not manual
    configuration.

16. As a researcher, I want the OM to post N identical role requests for a role when the target
    count exceeds current count, so that the shortfall is advertised.

17. As a researcher, I want the OM to delete pending requests for a role when the target count
    drops below current count, so that excess requests don't accumulate.

18. As a researcher, I want the Nest to emit `storage_low(resource_type)` and
    `storage_abundant(resource_type)` signals when resource storage crosses configured thresholds,
    so that the OM can use them for its evaluation.

19. As a researcher, I want agents to self-report their role change to the OM (via signal), so that
    the OM maintains an accurate count per role and records a role-change log entry.

20. As a researcher, I want the role-change log to be available at runtime through the debug
    panel, so that I can inspect who changed roles and when.

21. As a researcher, I want the OM to maintain a death counter and adjust total-agent count and
    role counts when an agent dies, so that ratios stay consistent.

22. As a researcher, I want `Unassigned` agents to count toward the target-distribution denominator,
    so that the OM plans for the full population.

23. As a researcher, I want the global actions (Eat, ReturnToNest, Rest) to be available to every
    agent regardless of role, so that survival behaviors are never blocked by role constraints.

24. As a researcher, I want `simulation.json` to support `roleEvalInterval` and `roleCooldown`
    overrides at startup, so that I can script different simulation configurations.

25. As a researcher, I want the `configs/nest.json` to define resource thresholds by type
    (low/abundant with absolute values), so that thresholds are data-driven.

## Implementation Decisions

### GOAP Planner

Each agent owns a local planner instance (no centralized planning). The planner operates on world
state and action definitions loaded from configs. The planning algorithm will be a forward-search
or backward-chaining search that respects preconditions and effects declared in
`configs/actions/actions.json` and `configs/goals/goals.json`. The plan is an ordered list of
actions. The planner exposes `create_plan(goal, world_state)`, `cancel_plan()`, and
`validate_plan(plan, world_state)`. If validation fails, the agent triggers a full replan.

### Goal Selector

The goal selector receives the filtered goal list from the Role Component. It evaluates each
goal's desirability against the current world state. Priority modifiers from the role definition
are applied multiplicatively to base desirability scores. The highest-scoring goal becomes the
agent's selected goal. If no goal is achievable, the agent enters Unassigned behavior (idle /
energy recovery). The evaluation runs on a timer tied to the planning cycle.

### Role Component

The Role Component is a child node attached to the agent. When the agent's role changes, the OM
sends the new role name; the Role Component loads the matching definition from
`configs/roles/<role>.json`. It exposes:

- `get_allowed_goals() -> Array` — goal names the role permits
- `get_allowed_actions() -> Array` — action names the role permits (always includes global
  actions: Eat, ReturnToNest, Rest)
- `get_priority_modifier(goal_name) -> float` — multiplier for goal scoring

The "Unassigned" role definition returns empty allowed-goal and allowed-action lists.

### Agent Role-Change Protocol

1. Agent finishes its current action (action execution signals completion).
2. Agent checks if it's within the Nest's Area2D trigger zone.
3. If yes, agent queries the OM's role-request queue for any pending request.
4. If a request is found and the agent's Role Cooldown is zero:
   - If request.role == current_role, skip (no-op).
   - If different: clear current goal and plan, load new role definition into Role Component,
     set Role Cooldown to configured value, emit `role_changed(agent_id, old_role, new_role)`.
5. Agent immediately selects a new goal from the new role's allowed list.
6. Agent starts building/executing a plan for the new goal.

### Organization Manager Role-Request Queue

The OM owns an internal queue as an array of role-name entries. Multiple identical entries may
exist (e.g. `["Gatherer", "Gatherer"]` means two open gatherer slots). The OM exposes:

- `post_request(role_name)` — appends one entry
- `take_request(role_name) -> bool` — removes one matching entry, returns true if found
- `clear_requests_for_role(role_name)` — removes all entries for that role

The OM evaluates every `roleEvalInterval` seconds:

1. Read resource storage from Nest (or via Nest signals).
2. Compute target role distribution: for each resource type, if storage < low threshold,
   increase target for the role that collects it (Gatherer); if storage > abundant threshold,
   increase target for Explorer; maintain a minimum of one Unassigned slot if population is
   large enough.
3. For each role, if target_count > current_count(post N requests for that role, where N =
   target_count - current_count). If target_count < current_count, clear pending requests for
   that role (excess agents will return to the nest naturally and become Unassigned).

The OM listens to agent `role_changed` signals to maintain current counts and append to the
role-change log.

### Nest Changes

The Nest gains an Area2D child node serving as the trigger zone for agent proximity. Zone size
is set so that agents must be "almost touching" the Nest collision shape. The Nest gains resource
thresholds loaded from `configs/nest.json`. When storage crosses a threshold boundary, the Nest
emits `storage_low(resource_type)` or `storage_abundant(resource_type)`.

The Nest does not own the role-request queue — that belongs to the OM. The Nest is the OM's
physical proxy: the OM must be accessible as an autoload, and the agents query the OM's queue
when the Area2D body_entered signal fires for an agent.

### Death Counter Integration

When an agent detects death (energy reaches zero or starvation max), it emits
`agent_died(agent_id, last_role)`. The OM handles this by:
- Decrementing total agent count
- Decrementing the count for the agent's last role
- Incrementing the death counter

Death causes are not implemented in this phase (no energy depletion yet); the signal and handler
are added to the OM but the wiring to agent state is left for Phase 2 energy lifecycle work.

### Config Additions

**`configs/nest.json` (new):**

```json
{
  "thresholds": {
    "Food": { "low": 10, "abundant": 50 },
    "Wood": { "low": 10, "abundant": 50 }
  }
}
```

**`simulation.json` additions:**

```json
{
  "enableEnemies": true,
  "enableDynamicRoles": true,
  "simulationSpeed": 1.0,
  "roleEvalInterval": 1.0,
  "roleCooldown": 10.0
}
```

### Role-Change Log

Stored in the OM as an array of dictionaries. Each entry: `{ "timestamp": float, "agent_id":
String, "old_role": String, "new_role": String }`. The debug panel reads this log and renders
it in a scrollable table. No log rotation or pruning in this phase.

## Testing Decisions

There is no test framework in the project. Testing is manual verification via the Godot editor:
run the main scene, observe behavior, check console output. The prior art is `main.gd` — a
scripted sequence of timed moves and resource interactions that exercises Phase 1 features
step by step.

For this phase, the corresponding test approach is:

- A `test_goap.gd` script (or extended `main.gd`) that:
  - Spawns an agent with a known role
  - Sets a goal and verifies the planner produces an expected action sequence
  - Changes the role mid-execution and verifies replanning
  - Manually posts a role request to the OM queue and moves an agent to the Nest trigger zone,
    then verifies the agent accepts it and changes role
  - Prints the role-change log to confirm entries
  - Prints death counter on agent death signal

Tests live in a `tests/` directory or remain in an extended `main.gd`. Because the project
lacks a test runner, all tests are "manual watch" tests — the developer runs the scene and
reads the console output to validate behavior.

The good test for this system tests external behavior: agents move differently after a role
change, resource types are collected by the right roles, the plan fails when the world changes.
Tests should not assert internal state like planner internals or action costs — those are
implementation details.

## Out of Scope

- **Pheromone system** (Phase 5) — explorers won't lay pheromone trails; the LayReturnPheromone
  and LayResourcePheromone actions are defined in configs but will not be actionable until the
  pheromone system exists.
- **Enemies** (Phase 6) — Guard role, DefendNest, and AttackEnemy are defined but cannot be
  tested until enemies exist.
- **Energy/starvation mechanics** — energy is tracked but not consumed. The death counter signal
  is wired but death is not triggerable yet.
- **Metrics system** (Phase 7) — no statistics collection.
- **Debug UI panels** (Phase 8) — role-change log is defined as data but has no visual panel
  yet. Console-only.
- **Threshold policy math** — the exact ratio calculation is left for implementation; this spec
  defines the contract (thresholds in, requests out) but not the formula.

## Further Notes

- The spec (architecture spec §17) shows example role JSONs with populated allowedGoals and
  allowedActions arrays. Those must be populated as part of this work — the current stubs with
  empty arrays will cause all roles to behave as Unassigned.
- Goal and action JSON configs currently lack preconditions and effects. Those must be added.
  The exact set of world-state properties (e.g. "has_food", "at_nest", "low_energy",
  "resource_visible", "enemy_near") should be documented in an agreed world-state schema that
  both goals and actions reference.
- The GOAP planner algorithm choice (forward vs backward search) is left open for the
  implementer to decide based on simplicity. Forward search from current state is recommended
  for initial implementation.
