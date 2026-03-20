# Identity Enrollment Across Machines

Every machine needs its own local `libself` identity before it can join the overlay.

The enrollment rule is:

- identity is generated locally
- public identity material is shared with operators
- allowlist entries are updated on every participating machine

## Recommended Flow

1. On each machine, run `vine identity init`.
2. Export the public identity material with `vine identity export-public`.
3. Record the peer fingerprint with `vine identity fingerprint`.
4. Distribute the public identity or fingerprint out of band.
5. Update each machine's `[[allowed_peers]]` list so the authenticated peer ID matches the intended prefix owner.

## Why This Matters

Overlay IPs can be changed later. The `libself` identity is the stable trust anchor.

That means enrollment is really:

- collect remote peer identity
- bind it to an owned prefix
- bind relay capability as policy

not:

- trust whoever claims a certain overlay IP

## Operational Advice

- keep fingerprints in operator notes or inventory
- review allowlist updates before daemon restart or reload
- reject any peer whose claimed prefix does not match the configured owner

In other words, machine enrollment is a trust update first and a routing update second.
