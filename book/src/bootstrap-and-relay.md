# Bootstrap Peers And Relay Placement

Bootstrap peers and relay peers solve different problems.

- bootstrap peers help a node find the network
- relay-capable peers help a node keep forwarding traffic when direct paths fail

Do not collapse those roles conceptually even if one machine does both.

## Bootstrap Selection

A good bootstrap peer should be:

- usually online
- reachable from all expected nodes
- stable enough that operators can hardcode its address

For the showcase config, `relay` is the obvious bootstrap target for `alpha`, `beta`, and `gamma`
because it is intended to stay reachable and already sits in the middle of the topology.

## Relay Placement

A good relay-capable node should be:

- on a stable network
- likely to have public reachability
- not overloaded by unrelated workloads

The relay should not own a special identity class. It remains a normal allowlisted peer with:

- a normal `libself` identity
- a normal overlay prefix
- `relay_capable = true` in the allowlist

## Practical Rule

If you only have one machine that is always online, that machine will usually be:

- the first bootstrap peer
- the first relay-capable peer

If you later add better infrastructure, keep bootstrap and relay decisions explicit in config rather than
assuming every bootstrap peer should relay traffic.
