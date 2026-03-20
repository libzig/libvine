# libvine

`libvine` is a Zig virtual network library for building small authenticated IPv4 overlays on top of the existing `libzig` stack.

For the MVP, `libvine` is intentionally narrow:

- Linux only
- IPv4 L3 overlay semantics
- one overlay network per process
- small peer sets
- static or bootstrap-assisted membership

`libvine` is not a replacement control plane. It uses `libmesh` extensively for discovery, signaling, route selection, session setup, and relay fallback. `libvine` owns overlay membership policy, virtual addressing, packet forwarding, and Linux TUN integration.

## Identity Versus Addressing

`libvine` does not treat overlay IP addresses as peer identity.

- `libself` identity answers who a node is
- `NetworkId` answers which overlay network the node belongs to
- `VinePrefix` answers which overlay IP range the node advertises
- `libmesh` answers which current path should be used to reach that node

This separation is critical for a real VPN deployment across multiple machines: peer trust and allowlisting
must bind to `libself` identity first, and only then to overlay addressing policy.

## Stack Position

- `libself`: identity and authenticated peer metadata
- `libmesh`: discovery, signaling, path selection, and relay fallback
- `libdice`: NAT traversal assistance when direct paths need setup exchange
- `libfast`: encrypted transport for control and packet carriage
- `libvine`: overlay network semantics and Linux host integration

## MVP Direction

The first milestone is a coherent library skeleton with stable public boundaries, tests that compile, and enough documentation for downstream consumers to follow the intended architecture before deeper control-plane and data-plane work lands.

## Documentation

The project documentation now lives in the mdBook under [`book/`](./book/). The entry point is [`book/src/SUMMARY.md`](./book/src/SUMMARY.md).
