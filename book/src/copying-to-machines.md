# Copying The Binary To Multiple Machines

`vine` is meant to be the same binary on every Linux PC in the deployment.

The node role comes from local config and local identity, not from a machine-specific build.

## Recommended Layout

Install the binary once per host:

```text
/usr/local/bin/vine
```

Install config and state paths separately:

```text
/etc/libvine/vine.toml
/var/lib/libvine/
```

That lets you copy one executable everywhere while keeping:

- one identity file per machine
- one node config per machine
- one runtime state directory per machine

## Operator Sequence

On each machine:

1. copy the `vine` binary to the same path
2. create `/etc/libvine` and `/var/lib/libvine`
3. run `vine identity init`
4. install the machine-specific `vine.toml`
5. validate with `vine config validate`
6. start the daemon

## What Must Differ Per Machine

- the persisted `libself` identity
- the local node name
- the local TUN address and advertised prefix
- the bootstrap addresses that point at reachable peers

## What Must Stay Shared

- the binary itself
- the `network_id`
- the allowlist view of which peer owns which prefix
- the operator workflow and CLI surface
