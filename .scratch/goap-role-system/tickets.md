# Tickets: GOAP Planning + Role System (Phases 2-3)

Implement GOAP planning, goal selection, role filtering, the Organization Manager's role-request
queue, and the Nest-based indirect role assignment protocol. Reference: SPEC.md in this directory.

Work the **frontier**: any ticket whose blockers are all done.

## T0 — Populate JSON configs with real schemas

**What to build:** The three role JSONs (`explorer.json`, `gatherer.json`, `guard.json`) get
populated `allowedGoals`/`allowedActions` matching the architecture spec. `goals.json` gets
`preconditions` and `effects` fields with world-state atoms (e.g. `"has_food"`, `"at_nest"`,
`"resource_visible"`). `actions.json` gets `cost`, `preconditions`, and `effects` fields.
`simulation.json` gains `roleEvalInterval` and `roleCooldown`. A new `configs/nest.json` defines
resource thresholds per type (low/abundant, absolute values). Pure data — no engine code changes.

**Blocked by:** None — can start immediately.

- [ ] Role JSONs populated with allowedGoals/allowedActions per architecture spec §17
- [ ] goals.json has preconditions and effects for all 10 goals
- [ ] actions.json has cost/preconditions/effects for all 13 actions
- [ ] simulation.json has roleEvalInterval (default 1.0) and roleCooldown (default 10.0)
- [ ] configs/nest.json created with Food/Wood low/abundant thresholds

## T1 — GOAP planner + goal selector implementation

**What to build:** The agent gains a `Planner` child node with `create_plan(goal_name, world_state)`
returning an ordered action sequence, plus `cancel_plan()` and `validate_plan()`. A `GoalSelector`
node scores goals by desirability against world state, applying role priority modifiers. Verifiable
by calling `agent.planner.create_plan(...)` from the test harness and printing the plan.

**Blocked by:** T0.

- [ ] Planner evaluates actions from action configs and returns a valid plan for a given goal
- [ ] GoalSelector scores goals and returns the highest-scoring achievable goal
- [ ] GoalSelector applies priority modifiers from the role component when available
- [ ] Planner rejects impossible goals (no plan found)
- [ ] Test harness can manually trigger planning and print results

## T2 — Agent planning cycle + action execution

**What to build:** The agent runs the full GOAP loop on a timer: evaluate goals → select goal →
build plan → execute actions one by one. Action execution calls the action-specific behaviour
(MoveTo navigates, PickupResource depletes a resource node and sets held_item, DepositResource
transfers to nest). When a plan completes, the agent re-evaluates. When a plan fails, the agent
replans. An agent with no achievable goal becomes idle. Verifiable: run the scene and watch an
agent autonomously explore, collect, and deposit resources.

**Blocked by:** T1.

- [ ] Agent runs evaluate → select → plan → execute loop on a timer
- [ ] MoveTo action navigates agent to a target position
- [ ] PickupResource action extracts from a resource node and sets held_item
- [ ] DepositResource action transfers held_item to Nest
- [ ] Eat action reduces hunger
- [ ] Rest action recovers energy
- [ ] ReturnToNest action navigates agent to nest position
- [ ] Plan completion triggers re-evaluation
- [ ] Plan failure triggers replanning
- [ ] Agent idles when no goal is achievable

## T3 — Role component + role loading

**What to build:** The `RoleComponent` node loads `configs/roles/<role>.json` when assigned,
exposes `get_allowed_goals()`, `get_allowed_actions()` (always includes Eat/ReturnToNest/Rest as
global actions), and `get_priority_modifier(goal_name)`. The goal selector reads modifiers from
the role component during scoring. The "Unassigned" role returns empty allowed lists — agent
becomes idle. Verifiable: manually set an agent's role from the test harness and confirm available
goals change; apply priority modifiers and confirm goal selection shifts.

**Blocked by:** T0, T1.

- [ ] RoleComponent loads role definition JSON by role name
- [ ] get_allowed_goals() returns role's permitted goals
- [ ] get_allowed_actions() returns role's permitted actions + global actions
- [ ] get_priority_modifier(goal_name) returns the role's modifier for that goal
- [ ] GoalSelector reads modifiers from RoleComponent and applies them
- [ ] "Unassigned" role returns empty allowed-goal and allowed-action lists
- [ ] Role change clears the agent's current goal and plan
- [ ] Agent immediately selects a new goal after role change

## T4 — OM role-request queue + Nest trigger zone

**What to build:** Organization Manager becomes an autoload singleton with `post_request()`,
`take_request()`, and `clear_requests_for_role()`. The Nest gains an Area2D child trigger zone
(body_entered detection). When an agent finishes its current action and is inside the Nest zone
with cooldown zero: it queries the OM queue, accepts a matching role request (no-op if same role),
loads the new role via RoleComponent, clears goal/plan, and begins replanning. Role Cooldown
(default 10s) is enforced. Agent reports role change to OM — counts updated, role-change log entry
appended. Verifiable: manually post a request to the OM queue, walk an agent to the Nest, watch
it change role and begin executing new-role behavior.

**Blocked by:** T3.

- [ ] Organization Manager is an autoload singleton
- [ ] OM exposes post_request, take_request, clear_requests_for_role
- [ ] Nest has an Area2D trigger zone (almost-touching proximity)
- [ ] Agent detects Nest proximity after finishing current action
- [ ] Agent queries OM queue when inside Nest zone and cooldown is zero
- [ ] Same-role requests are ignored (no-op)
- [ ] Different-role triggers: clear goal/plan, load new role, set cooldown
- [ ] Agent emits role_changed signal to OM
- [ ] OM maintains per-role agent counts
- [ ] OM appends role-change log entries
- [ ] Role Cooldown is enforced (configurable, default 10s)

## T5 — OM evaluation loop + threshold-based role request posting

**What to build:** Nest stores resource thresholds from config and emits `storage_low(resource_type)`
and `storage_abundant(resource_type)` signals when storage crosses boundaries. OM runs a timer
every `roleEvalInterval` seconds: reads Nest storage, computes target role distribution from
thresholds, posts requests for roles below target, cleans up requests for roles above target.
Death-counter handler is wired on OM (no death trigger yet — signal infrastructure only).
Unassigned agents count toward distribution denominator. Verifiable: drain Nest below low threshold,
watch Gatherer requests appear in the queue; exceed abundant threshold, watch Explorer requests
replace them.

**Blocked by:** T4.

- [ ] Nest loads thresholds from configs/nest.json
- [ ] Nest emits storage_low and storage_abundant signals
- [ ] OM evaluates every roleEvalInterval seconds
- [ ] OM computes target distribution from thresholds + current counts
- [ ] OM posts requests for roles below target
- [ ] OM clears requests for roles above target
- [ ] Death-counter handler wired on OM (decrement agent/role counts, increment death counter)
- [ ] Unassigned agents count toward distribution denominator
- [ ] EnableDynamicRoles flag controls whether OM posts requests
- [ ] All config values editable at runtime via debug panel (plumbing only — no UI)
