# SMAS (Social Multi-Agent System)

A Godot-based research platform for experimenting with dynamic organizational role allocation in a colony-inspired multi-agent system.

## Language

**Organization Manager (OM)**:
The central authority that owns the role-request queue, agent registry, and role-change log. It evaluates colony needs and posts anonymous role requests — it never assigns an agent directly.
_Avoid_: Dispatcher, scheduler

**Nest**:
The colony's physical structure in the simulation. Owns the Area2D trigger zone, resource storage counters, and emits low/abundant signals. Acts as the Organization Manager's physical proxy for agent interaction.
_Avoid_: Hive, base

**Role Request**:
An entry in the OM's queue requesting that an unspecified agent assume a given role. First agent to grab it wins. Multiple identical requests may coexist.
_Avoid_: Order, assignment, directive

**Role Change Log**:
A timestamped record of agent role changes (agent ID, old role, new role, timestamp). Exposed via the debug panel.

**Unassigned**:
An explicit role with no allowed goals or actions. Agents in this unassigned state stand still and recover energy. They may request any role from the nest.

**Role Cooldown**:
A 10-second period (configurable at runtime) during which an agent that just changed roles cannot accept another role request.

**Threshold Policy**:
The OM's decision logic for computing target role distribution. Absolute resource thresholds (low/abundant) from nest config drive ratio-based distribution targets. No enemy factors until Phase 6.
_Avoid_: Role assignment algorithm

**Simulation Config**:
The `simulation.json` config file. Extended with `roleEvalInterval` (OM evaluation period, default 1s) and `roleCooldown` (agent role-change cooldown, default 10s). All values adjustable from the debug panel at runtime.
