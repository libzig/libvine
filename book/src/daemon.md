# Daemon

`vine` now has a dedicated daemon lifecycle surface:

- `vine daemon run`
- `vine daemon start`
- `vine daemon stop`
- `vine daemon status`

The current implementation is still a lightweight skeleton, but it already establishes the runtime
ownership model that later slices will connect to real node startup and multi-peer operation.

## Runtime Ownership

The daemon runtime owns:

- phase transitions: `stopped`, `starting`, `running`, `stopping`
- the configured config path for the active process
- pidfile and runtime state paths
- bounded startup sequencing
- bounded shutdown sequencing
- signal conventions for shutdown, reload, and diagnostics

Those behaviors live in `lib/daemon/runtime.zig`.

## Foreground And Background

`vine daemon run -c /etc/libvine/vine.toml`

- runs in the foreground
- enters the bounded startup sequence
- transitions to `running`

`vine daemon start -c /etc/libvine/vine.toml`

- spawns the current `vine` executable in background daemon mode
- writes a pidfile
- leaves runtime state for `status` to inspect

## Stop And Status

`vine daemon stop`

- reads the pidfile
- sends `SIGTERM`
- runs the bounded shutdown sequence
- removes the pidfile

`vine daemon status`

- reads the runtime state file when present
- reports the daemon phase
- reports the pid from pidfile or stored state

## Signals

Current signal conventions are explicit:

- clean shutdown: `SIGTERM`
- reload request: `SIGHUP`
- diagnostics dump request: `SIGUSR1`

This keeps the control contract stable before the runtime is fully connected to live TUN and session ownership.
