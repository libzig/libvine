# TUN Permissions And Route Installation

`vine` is a user-space VPN, but it still depends on Linux networking privileges.

The minimum operator expectation is:

- the process can create or open the configured TUN device
- the process can assign the configured overlay address
- the process can install and remove local routes for owned prefixes

## What Usually Requires Privilege

On a normal Linux host, the following actions often need root or equivalent delegated capability:

- opening `/dev/net/tun`
- setting interface flags
- assigning interface addresses
- changing route tables

If those operations fail, the control-plane side of `vine` may still start while packet forwarding remains broken.

## Practical Deployment Rule

Validate host readiness before relying on the daemon:

1. confirm `/dev/net/tun` exists
2. confirm the runtime user can access it
3. confirm route changes are permitted
4. confirm the configured interface name is acceptable for the target host

## Failure Shape

When TUN setup or route installation fails, expect:

- no usable overlay interface
- no local packet injection path
- misleading peer/session state if you only inspect the control plane

That is why host readiness checks belong in `vine doctor` and why operators should treat TUN permissions as
part of initial deployment, not as a later optimization.
