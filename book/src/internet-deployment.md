# Internet Deployment With One Relay-Capable Node

After the LAN proof, the next practical deployment is several machines on different networks with one
publicly reachable relay-capable node.

The simplest version is:

- `relay` on a stable public host
- `alpha`, `beta`, and `gamma` behind normal home or office NATs

## Recommended Placement

Put the relay-capable node where it has:

- a stable address
- predictable firewall rules
- enough uptime to be the bootstrap point

That single host becomes the operational anchor for:

- bootstrap discovery
- failed direct-session fallback

## Configuration Advice

- keep `allow_relay = true` for remote nodes
- make the relay node explicit in every allowlist
- point remote bootstrap entries at the relay's reachable UDP address
- avoid depending on an edge node that frequently changes networks

## Success Criteria

An internet deployment is healthy when:

- nodes still join the same `network_id`
- overlay prefixes remain tied to configured peer IDs
- direct sessions appear when possible
- relay paths appear when necessary
- relay usage is visible through diagnostics instead of being guessed

The operator goal is not to eliminate relay entirely. The goal is to prefer direct paths while keeping
connectivity when direct reachability is impossible.
