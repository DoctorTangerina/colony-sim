# ARCHITECTURE_SPECIFICATION.md

# Dynamic Social Roles Multi-Agent Framework

**Version:** 1.0

**Target Engine:** Godot 4.7

**Language:** GDScript

**Architecture Style:** Data-Driven OCMAS + GOAP

**Primary Goal:** Demonstrate dynamic organizational role reassignment in a colony-like Multi-Agent System.

---

# 1. Project Overview

This project implements a Multi-Agent System (MAS) inspired by ant colonies, where agents operate under an organizational structure and may dynamically change social roles during execution.

The framework follows an Organization-Centered Multi-Agent System (OCMAS) approach. Individual agents remain autonomous and perform local planning through Goal-Oriented Action Planning (GOAP), while a centralized Organization Manager is responsible for assigning roles according to organizational needs.

The framework must prioritize:

* Simplicity
* Extensibility
* Clear modularity
* Data-driven configuration

The framework is not intended to be a game. It is a research platform for experimenting with dynamic role allocation and organizational behavior.

---

# 2. Core Design Principles

## 2.1 Organization Controls Roles

The organization never controls actions.

The organization only decides:

* Which role an agent should perform
* When a role should change

Agents remain responsible for:

* Goal selection
* Planning
* Action execution

---

## 2.2 GOAP Remains Local

Every agent owns its own GOAP planner.

There is no centralized planning.

Role changes trigger replanning.

---

## 2.3 Roles Are Policies

Roles do not directly contain behavior implementations.

Roles only grant permissions.

A role defines:

* Allowed Goals
* Allowed Actions
* Goal Priority Modifiers

---

## 2.4 Data-Driven Configuration

The following systems must be configurable through JSON:

* Roles
* Goals
* Actions
* Resources
* Agent parameters
* Organization parameters
* Simulation parameters

No role should require engine modifications.

---

## 2.5 Replaceable Components

Major systems must be isolated behind interfaces.

Replaceable systems include:

* GOAP planner
* Role assignment policy
* Resource generator
* Pheromone system
* Enemy behavior
* Metrics collection

---

# 3. High-Level Architecture

```text
Simulation
│
├── Organization Manager
│
├── Resource System
│
├── Enemy System
│
├── Pheromone System
│
├── Metrics System
│
└── Agents
      │
      ├── Role Component
      ├── Goal Selector
      ├── GOAP Planner
      ├── Action Executor
      └── Navigation Component
```

---

# 4. World Model

## Environment

The simulation world is:

* 2D
* Continuous
* Real-time

Maps are predefined.

---

## Nest

The colony owns a single nest.

The nest is responsible for:

* Resource storage
* Agent resting
* Resource deposit
* Agent spawning (future extension)

---

## Navigation

Navigation must use:

```text
NavigationServer2D
```

All movement operations must rely on navigation paths.

---

# 5. Agent Model

## Agent State

Each agent contains:

```text
AgentID
Position
CurrentRole
CurrentGoal
CurrentPlan
HeldItem
Energy
Hunger
RoleCooldown
```

---

## Inventory

Agents may carry only one item.

```text
None
Food
Wood
```

Resources only count after being deposited in the nest.

---

## Global Behaviors

All agents have access to:

* Eat
* ReturnToNest
* Rest

These actions are independent of role.

---

# 6. Resource System

## Resource Types

Initial resources:

```text
Food
Wood
```

---

## Resource Node

Each node contains:

```text
ResourceType
RemainingAmount
Position
```

---

## Resource Lifecycle

Resources:

* Are finite
* Disappear when exhausted
* Respawn elsewhere

The system guarantees:

```text
At least one active Food node
At least one active Wood node
```

at all times.

---

# 7. Pheromone System

The pheromone system provides indirect communication between agents.

---

## Pheromone Types

### Return Pheromone

Created by explorers while moving away from the nest.

Purpose:

Allow explorers to navigate back.

---

### Resource Pheromone

Created by explorers while returning from discovered resources.

Purpose:

Guide gatherers toward resources.

---

## Pheromone Data

```text
Type
Position
Intensity
ResourceID
```

---

## Decay Rules

Trails disappear when:

* Associated resource no longer exists
* All agents using the trail returned to the nest

Intensity should gradually decay over time.

---

# 8. Enemy System

Enemies represent organizational emergencies.

---

## Enemy Behavior

Enemies:

* Spawn randomly
* Move toward the nest
* Attempt to damage the colony

---

## Configuration

Enemy attacks must be toggleable.

```json
{
  "enableEnemies": true
}
```

---

# 9. Role System

Roles are organizational permissions.

They never directly implement behavior.

---

## Role Definition

```json
{
  "name": "",
  "allowedGoals": [],
  "allowedActions": [],
  "priorityModifiers": {}
}
```

---

## Initial Roles

### Explorer

Responsibilities:

* Discover resources
* Generate pheromone trails

---

### Gatherer

Responsibilities:

* Follow resource pheromones
* Collect resources
* Deliver resources

---

### Guard

Responsibilities:

* Defend nest
* Intercept enemies

---

## Idle State

Agents may temporarily have no role.

Idle agents still:

* Consume energy
* Consume food

---

## Role Cooldown

Role changes create a cooldown.

```text
10 seconds
```

Role reassignment cannot occur during cooldown.

---

# 10. Goal System

Goals are reusable entities.

Roles determine which goals are available.

---

## Global Goals

```text
Eat
Rest
ReturnToNest
```

---

## Explorer Goals

```text
Explore
DiscoverResource
```

---

## Gatherer Goals

```text
CollectFood
CollectWood
DepositResource
```

---

## Guard Goals

```text
DefendNest
AttackEnemy
```

---

# 11. Action System

Actions are reusable components.

---

## Global Actions

```text
MoveTo
Eat
Rest
ReturnToNest
```

---

## Explorer Actions

```text
RandomExplore
LayReturnPheromone
LayResourcePheromone
ReportResource
```

---

## Gatherer Actions

```text
FollowPheromone
PickupResource
DepositResource
```

---

## Guard Actions

```text
PatrolNest
AttackTarget
```

---

# 12. GOAP System

Every agent owns a GOAP planner.

---

## Planning Cycle

```text
Evaluate Goals
      ↓
Select Goal
      ↓
Build Plan
      ↓
Execute Actions
      ↓
Monitor World State
      ↓
Replan If Necessary
```

---

## Replanning Triggers

Replanning occurs when:

* Role changes
* Agent state changes
* Goal becomes invalid
* Plan fails

---

## Planner Interface

```text
IGOAPPlanner
```

Required methods:

```text
create_plan()
cancel_plan()
validate_plan()
```

---

# 13. Organization System

The Organization Manager is the central authority.

Implemented as:

```text
Singleton (Autoload)
```

---

## Responsibilities

Maintain:

* Colony storage
* Agent registry
* Resource statistics
* Emergency state
* Role assignments

---

## Forbidden Responsibilities

The organization must never:

* Execute actions
* Generate plans
* Control movement

---

# 14. Role Assignment Policy

Role assignment must be isolated.

---

## Interface

```text
IRolePolicy
```

---

## Default Policy

```text
ThresholdRolePolicy
```

---

### Resource Shortage

If food or wood falls below threshold:

Increase Gatherers.

---

### Resource Stability

If resources are stable:

Increase Explorers.

---

### Emergency

If enemies exist:

Increase Guards.

---

### Static Mode

A simulation option must disable dynamic assignment.

```text
Dynamic Roles = OFF
```

In this mode, agents retain their initial roles.

---

# 15. Metrics System

Metrics must be collected continuously.

---

## Required Metrics

### Role Switches

```text
Total role changes
Role changes per minute
```

---

### Task Completion

```text
Resources delivered
Enemies defeated
```

---

### Idle Time

```text
Total idle duration
Idle percentage
```

---

## Interface

```text
IMetricsCollector
```

---

# 16. Debug Visualization

The framework must provide debugging tools.

---

## Agent Overlay

Display:

```text
Current Role
Current Goal
Current Plan
Energy
Hunger
Role Cooldown
```

---

## Organization Panel

Display:

```text
Food Storage
Wood Storage
Agent Count
Current Role Distribution
Emergency Status
```

---

## Planner Panel

Display:

```text
Goal Evaluation
Selected Goal
Generated Plan
Plan Failures
```

---

## Pheromone Visualization

Render:

```text
Return Pheromones
Resource Pheromones
Intensity Levels
```

---

## Role Change Log

Display:

```text
Timestamp
Agent
Old Role
New Role
Reason
```

---

# 17. JSON Schemas

## Role

```json
{
  "name": "Gatherer",
  "allowedGoals": [
    "CollectFood",
    "CollectWood",
    "DepositResource"
  ],
  "allowedActions": [
    "MoveTo",
    "PickupResource",
    "DepositResource",
    "FollowPheromone"
  ],
  "priorityModifiers": {
    "CollectFood": 2.0
  }
}
```

---

## Resource

```json
{
  "type": "Food",
  "maxAmount": 100,
  "respawnTime": 20
}
```

---

## Simulation

```json
{
  "enableEnemies": true,
  "enableDynamicRoles": true,
  "simulationSpeed": 1.0
}
```

---

# 18. Recommended Folder Structure

```text
project/
│
├── agents/
│   ├── agent.gd
│   ├── role_component.gd
│   ├── goal_selector.gd
│   ├── planner/
│
├── organization/
│   ├── organization_manager.gd
│   ├── role_policy/
│
├── resources/
│   ├── resource_node.gd
│   ├── resource_manager.gd
│
├── pheromones/
│   ├── pheromone.gd
│   ├── pheromone_manager.gd
│
├── enemies/
│
├── metrics/
│
├── ui/
│
├── configs/
│   ├── roles/
│   ├── goals/
│   ├── actions/
│   ├── resources/
│
└── simulation/
```

---

# 19. Development Order

The recommended implementation order is:

### Phase 1

Core Simulation

* Agent
* Navigation
* Resource Nodes
* Nest

---

### Phase 2

GOAP

* Goals
* Actions
* Planner

---

### Phase 3

Roles

* Role System
* Role Loading
* Goal Permissions

---

### Phase 4

Organization

* Storage
* Role Assignment
* Dynamic Reassignment

---

### Phase 5

Pheromones

* Return Trails
* Resource Trails

---

### Phase 6

Enemies

* Enemy AI
* Emergency Handling

---

### Phase 7

Metrics

* Statistics
* Logging

---

### Phase 8

Debug Interface

* Panels
* Visualization
* Controls

---

# 20. Acceptance Criteria

The framework is considered complete when:

1. Agents successfully execute GOAP plans.
2. Explorers discover resources.
3. Gatherers collect resources through pheromone guidance.
4. Resources are deposited into the nest.
5. Guards defend against enemy attacks.
6. The Organization Manager dynamically changes roles.
7. Role reassignment causes successful replanning.
8. Static-role mode can be enabled.
9. Metrics are collected.
10. Debug tools expose organizational state.
11. New roles can be added exclusively through JSON configuration without modifying existing engine systems.

This final criterion is considered the primary extensibility requirement of the framework.
