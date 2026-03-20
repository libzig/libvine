# Data Plane

The MVP data plane carries raw IPv4 packets between Linux TUN interfaces over sessions established through the lower stack.

## Packet Flow

1. a local packet arrives from the TUN device
2. `libvine` maps the destination address to an owned overlay prefix
3. `libvine` selects the preferred reachable peer session
4. the packet is framed and sent over the active transport path
5. the remote node decapsulates the payload and injects it into its TUN device

## Scope

- raw IPv4 payload carriage only for the MVP
- explicit framing for control messages versus packet data
- bounded payload sizes derived from transport and relay constraints
- no hidden control-plane reinvention in the packet path
