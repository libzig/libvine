# Multi-PC Topology

This example shows one `vine` binary deployed to four Linux machines:

- `alpha`: user workstation advertising `10.42.0.0/24`
- `beta`: server node advertising `10.42.1.0/24`
- `gamma`: second workstation advertising `10.42.2.0/24`
- `relay`: relay-capable node advertising `10.42.254.0/24`

All four nodes join the same overlay network:

- `network_id = "home-net"`

The intended path behavior is:

1. `alpha` reaches `beta` directly when a direct `libmesh` session is available.
2. `gamma` reaches `beta` through signaling-assisted setup when direct reachability needs help.
3. `gamma` reaches `alpha` through `relay` when direct setup fails.
4. `alpha` falls back to `relay` if an existing direct session to `beta` drops.

The examples in this directory are operator-facing config assets, not Zig embedding samples.
They are designed to be copied to multiple PCs alongside the same `vine` binary.

## Prefix Ownership

Each authenticated peer owns exactly one overlay prefix in this showcase:

- `alpha` owns `10.42.0.0/24`
- `beta` owns `10.42.1.0/24`
- `gamma` owns `10.42.2.0/24`
- `relay` owns `10.42.254.0/24`

The relay node is still a normal peer with a normal prefix. Relay capability is an explicit policy flag,
not a special identity type.

## Identity Binding

Peer IDs in the example configs are placeholders. In a real deployment, replace them with `vine identity export-public`
or `vine identity fingerprint` output derived from each machine's persisted `libself` identity.

Overlay IPs are routing coordinates only. They do not identify the node.

## Bootstrap Layout

The example assumes:

- `alpha` bootstraps from `relay`
- `beta` bootstraps from `relay`
- `gamma` bootstraps from `relay`
- `relay` bootstraps from `alpha`

That keeps one relay-capable node easy to discover while avoiding a single completely isolated first-start path.

## Deployment Notes

- Copy the same `vine` binary to all machines.
- Generate one local `libself` identity per machine.
- Install the matching node config from this directory.
- Replace example peer IDs and UDP addresses with real values before starting the daemon.
