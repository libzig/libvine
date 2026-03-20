# Troubleshooting

## Build Fails

If `make build` fails:

- confirm the Nix shell is active and Zig `0.15.2` is the toolchain in use
- check that local path dependencies `libself`, `libmesh`, `libdice`, and `libfast` are present
- remember that example programs are compiled as part of the build

## Test Fails

If `make test` fails:

- start with the failing module instead of chasing the full stack
- check whether a new test exposed a stale assumption in route/session fallback behavior
- confirm changes under `lib/data/` were force-added if Git ignore rules apply there

## Peer Mismatch

Symptoms:

- a remote node appears to exist but never becomes an accepted peer
- membership updates are rejected
- the advertised prefix never becomes a usable route

Checks:

- confirm the remote `libself` identity was exported from the correct machine
- confirm the configured `peer_id` matches that identity exactly
- confirm every machine updated its allowlist before restart or reload

`vine` should trust the authenticated peer ID first and only then accept the owned prefix.

## Route Mismatch

Symptoms:

- `vine peers` looks correct but `vine routes` is missing a prefix
- traffic to an overlay subnet is dropped as unknown

Checks:

- confirm the configured prefix matches the node that is actually advertising it
- confirm no two peers claim overlapping prefixes
- confirm the local config still points at the intended `network_id`

If prefix ownership is wrong, the correct outcome is rejection rather than silent route guessing.

## TUN Failure

Symptoms:

- control-plane commands look healthy but packets do not enter the overlay
- interface creation or route install fails at startup

Checks:

- run `vine doctor -c /etc/libvine/vine.toml`
- confirm `/dev/net/tun` exists and is accessible to the runtime user
- confirm the process has the privileges required to assign the interface and routes
- confirm the configured TUN name is valid for Linux

## Relay Overuse

Symptoms:

- traffic works, but `vine sessions` shows relay more often than expected
- `relay_usage` and `fallback_transitions` climb steadily

Checks:

- inspect whether the direct path is actually reachable between the two peers
- confirm bootstrap and relay placement are not masking a broken direct-session setup
- treat relay as a resilience mechanism, not as the default steady-state path

## Debugging Tools

Use:

- `vine doctor`
- `vine status`
- `vine peers`
- `vine routes`
- `vine sessions`
- `vine counters`
- `vine snapshot`
