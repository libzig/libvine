# Peers and Sessions

`libvine` keeps identity, overlay addressing, and transport reachability separate:

- `PeerId` comes from `libself`
- `VinePrefix` says which overlay range a peer owns
- the session manager decides which transport path is currently best

Configured peers are loaded from `vine.toml` and translated into runtime session candidates.
At runtime, `libmesh` reachability is mapped into three session classes:

- `direct`
- `signaling_then_direct`
- `relay`

The runtime preference order is fixed:

1. `direct`
2. `signaling_then_direct`
3. `relay`

Relay sessions are only accepted for peers explicitly marked `relay_capable = true`.
This prevents the runtime from silently treating every peer as a relay target.

When a better path appears, the session manager promotes it. When a preferred path dies,
the manager can fall back to an existing relay session without changing peer identity or
prefix ownership.

Use the CLI to inspect the current session snapshot:

```text
vine sessions -c /etc/libvine/vine.toml
```

The command reports:

- configured peer count
- session counts by class
- preferred session per peer
- whether the peer is relay-capable

At this stage the command is config-driven and renders the runtime session-manager view
for configured peers. The later diagnostics slices will extend this into a fuller
daemon-backed runtime snapshot.
