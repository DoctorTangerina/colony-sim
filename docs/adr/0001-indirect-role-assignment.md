# ADR 1: Indirect Role Assignment via Request Queue

The Organization Manager must induce role changes without controlling agents directly (per §2.1 of the architecture spec: "Organization never controls actions"). Agents remain autonomous in their own planning. The OM role-evaluation period is 1s, and agents may only change roles at the nest (after finishing their current action), creating an inherent time lag between detecting a need and the actual role change.

**The OM does not assign roles to specific agents.** Instead, it posts N identical role requests to a queue that agents query via the Nest's Area2D trigger zone. The first agent to grab a pending request gets it. This is anonymous, first-wins, and allows the OM to be completely decoupled from individual agent identity.

This was a deliberate choice over the obvious alternative (direct assignment). Direct assignment would be simpler but would tie the OM to agent references, create tight coupling, and require the OM to reason about which specific agent to reassign — a scheduling problem that grows with agent count. The indirect approach lets agents self-select based on their own context (proximity, current action), which is more aligned with the autonomy principle.

Key implications: the OM never knows which agents hold a given role (it only knows the count); same-role requests in the queue impose no-ops, and unused requests are cleaned up periodically.
