# libvine

`libvine` is a Zig virtual network library for building small authenticated IPv4 overlays on top of the existing `libzig` stack.

For the MVP, `libvine` is intentionally narrow:

- Linux only
- IPv4 L3 overlay semantics
- one overlay network per process
- small peer sets
- static or bootstrap-assisted membership

`libvine` is not a replacement control plane. It uses `libmesh` extensively for discovery, signaling, route selection, session setup, and relay fallback. `libvine` owns overlay membership policy, virtual addressing, packet forwarding, and Linux TUN integration.

## Stack Position

- `libself`: identity and authenticated peer metadata
- `libmesh`: discovery, signaling, path selection, and relay fallback
- `libdice`: NAT traversal assistance when direct paths need setup exchange
- `libfast`: encrypted transport for control and packet carriage
- `libvine`: overlay network semantics and Linux host integration

## MVP Direction

The first milestone is a coherent library skeleton with stable public boundaries, tests that compile, and enough documentation for downstream consumers to follow the intended architecture before deeper control-plane and data-plane work lands.
