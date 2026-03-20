# libvine

`libvine` is the repo behind `vine`, a Linux overlay VPN binary built in Zig on top of the `libzig` stack.

The primary product is now:

- one `vine` binary you can copy to multiple Linux PCs
- one `libself` identity per machine
- one TOML config per machine
- one overlay network with explicit prefix ownership
- direct sessions when possible, relay fallback when necessary

The library remains important, but the intended operator experience is:

1. build `vine`
2. copy the same binary to each Linux host
3. generate one identity per host
4. install one host-specific config per host
5. start the daemon
6. inspect peers, routes, sessions, counters, and snapshots

## Build

```text
nix develop -c make build
```

This produces the `vine` binary through `zig build vine`.

## Quick Start

Use the multi-PC showcase under [`examples/multi-pc/`](./examples/multi-pc/) as the reference deployment:

- `alpha`
- `beta`
- `gamma`
- `relay`

Typical first steps on a host:

```text
vine identity init
vine config validate -c /etc/libvine/vine.toml
vine doctor -c /etc/libvine/vine.toml
vine daemon run -c /etc/libvine/vine.toml
```

## Identity Versus Addressing

`vine` does not treat overlay IP addresses as peer identity.

- `libself` identity answers who a node is
- `NetworkId` answers which overlay network the node belongs to
- `VinePrefix` answers which overlay IP range the node advertises
- `libmesh` answers which current path should be used to reach that node

Peer trust and allowlisting must bind to `libself` identity first, and only then to overlay addressing policy.

## Stack Position

- `libself`: identity and authenticated peer metadata
- `libmesh`: discovery, signaling, path selection, and relay fallback
- `libdice`: NAT traversal assistance when direct paths need setup exchange
- `libfast`: encrypted transport for control and packet carriage
- `libvine`: overlay network semantics and Linux host integration

`libvine` is not a replacement control plane. It uses `libmesh` for discovery, signaling, route selection,
session setup, and relay fallback. `libvine` owns overlay membership policy, virtual addressing, packet
forwarding, and Linux TUN integration.

## Documentation

The project documentation lives in the mdBook under [`book/`](./book/).

Useful entry points:

- [`book/src/SUMMARY.md`](./book/src/SUMMARY.md)
- [`book/src/showcase.md`](./book/src/showcase.md)
- [`book/src/copying-to-machines.md`](./book/src/copying-to-machines.md)
- [`book/src/bootstrap-and-relay.md`](./book/src/bootstrap-and-relay.md)
- [`book/src/enrollment-across-machines.md`](./book/src/enrollment-across-machines.md)
- [`book/src/lan-deployment.md`](./book/src/lan-deployment.md)
- [`book/src/internet-deployment.md`](./book/src/internet-deployment.md)
