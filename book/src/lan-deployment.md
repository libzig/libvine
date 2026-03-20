# First Deployment On A LAN

The safest first real deployment is on one local network where you control all four machines.

Use that environment to prove:

- identities load correctly
- bootstrap works
- peer ownership matches config
- the TUN interface comes up
- traffic moves without relay unless needed

## Recommended Order

1. prepare all four configs from `examples/multi-pc/`
2. generate one identity per machine
3. replace placeholder peer IDs with real exported identities
4. validate each config locally
5. start `relay`
6. start `alpha`, `beta`, and `gamma`
7. inspect `vine status`, `peers`, `routes`, and `sessions`

## Why Start On A LAN

A LAN removes several variables at once:

- NAT complexity
- public reachability problems
- firewall uncertainty

That makes it easier to tell whether failure is caused by:

- wrong allowlist identity
- wrong prefix ownership
- bad config distribution
- TUN or route setup problems

## Success Criteria

The first LAN deployment should show:

- all peers enrolled into the same `network_id`
- expected prefixes installed
- at least one direct session
- observable relay fallback only when forced
