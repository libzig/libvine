# Control Plane

`libvine` does not build an independent reachability control plane for the MVP.

## What `libmesh` Owns

- peer discovery
- signaling exchange
- path selection
- relay fallback decisions
- session orchestration hooks

## What `libvine` Adds

- overlay network identity checks
- virtual prefix advertisement semantics
- membership policy
- route ownership updates specific to overlay forwarding

`libvine` control messages should be small, versioned, and designed to travel through `libmesh` signaling and setup flows rather than bypassing them.
