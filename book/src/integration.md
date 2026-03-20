# libvine Integration Contract

## Audience

This document is for downstream consumers such as `libboid` that want to embed `libvine`
as an overlay runtime instead of talking to `libmesh`, `libfast`, and Linux TUN details directly.

## Public Entry Points

- import `libvine` from the package root
- configure a node with `lib/api/config.zig`
- create and run a node with `lib/api/node.zig`
- use examples in `examples/` as the baseline integration shape

The most complete topology walkthrough in the repo is `examples/multi_node_relay_demo.zig`,
which models multiple peers plus a relay and shows direct, signaling-assisted, and relay fallback traffic choices.

## Required Consumer Inputs

A consumer is expected to provide:

- one `NetworkId` shared by all peers in the overlay
- one local TUN address and prefix length
- an allowlist of accepted peers when strict admission is desired
- either static bootstrap peers or published seed records
- an identity source, generated or deterministic seed-backed

## Runtime Contract

`Node.init` wires together local identity, membership state, TUN state, route state, session state,
and the `libmesh` adapter boundary. Consumers should treat the node as the sole owner of those runtime slices
for the lifetime of the process.

`Node.start` marks the node active and advertises local membership.

`Node.bootstrap` chooses discovery inputs in this order:

1. static bootstrap peers
2. seed records

`Node.sendPacket`, `Node.receivePacket`, and `Node.cleanupStaleSession` expose the data-plane and
fallback-sensitive runtime hooks used by the current tests and examples.

## Diagnostics And Debugging

Consumers can attach an event callback for:

- lifecycle logs
- bootstrap diagnostics
- topology changes

Consumers can also read:

- `node.diagnostics` for counters
- `node.debugSnapshot()` for structured runtime inspection

## Integration Rules For libboid

`libboid` should:

- construct `NodeConfig` once per overlay process
- keep peer identity and allowlist policy outside `libvine`, then feed approved peers in
- treat `libmesh` reachability as authoritative instead of second-guessing it in application code
- use the event callback and debug snapshot APIs for observability
- prefer the example programs as the starting point for host-side orchestration

`libboid` should not:

- bypass `Node` and mutate route/session slices concurrently while the runtime is active
- invent its own overlay packet framing on top of live `libvine` sessions
- assume relay fallback is equivalent to direct-path latency or throughput
