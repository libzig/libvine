# Architecture

`libvine` sits at the overlay edge of the `libzig` networking stack.

## Responsibility Split

- `libself` owns node identity and authenticated peer metadata.
- `libmesh` owns discovery, signaling, path selection, and relay fallback.
- `libdice` helps with traversal setup when direct connectivity needs coordination.
- `libfast` carries encrypted control and packet traffic once a path is open.
- `libvine` owns overlay membership policy, virtual IPv4 addressing, forwarding, and Linux TUN integration.

## Architectural Rule

If `libmesh` already owns a reachability concern, `libvine` reuses it instead of rebuilding it. `libvine` should consume `libmesh` decisions and expose overlay semantics on top of them rather than inventing a second control plane.

## MVP Shape

The MVP is Linux-only, IPv4-only, and intentionally optimized for small peer sets. One process hosts one overlay network instance, and the first policy model is expected to be explicit and static enough to keep routing and membership deterministic.
