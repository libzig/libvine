# Configuration

`vine` reads operator configuration from a TOML file, by default:

- `/etc/libvine/vine.toml`

The file defines overlay membership, local TUN settings, bootstrap peers, allowlisted peer prefixes,
and runtime policy toggles. Identity is configured by path, but identity itself is still derived from
`libself` material on disk rather than from overlay IP addresses.

## Example

```toml
[node]
name = "alpha"
network_id = "home-net"
identity_path = "/var/lib/libvine/identity"

[tun]
name = "vine0"
address = "10.42.0.1"
prefix_len = 24
mtu = 1400

[[bootstrap_peers]]
peer_id = "seed-a"
address = "udp://198.51.100.10:4100"

[[allowed_peers]]
peer_id = "beta"
prefix = "10.42.1.0/24"
relay_capable = false

[[allowed_peers]]
peer_id = "relay-a"
prefix = "10.42.254.0/24"
relay_capable = true

[policy]
strict_allowlist = true
allow_relay = true
allow_signaling_upgrade = true
```

## Sections

`[node]`

- `name`: operator-facing node label
- `network_id`: shared overlay network identifier
- `identity_path`: absolute path to the persisted `libself` identity file

`[tun]`

- `name`: Linux TUN interface name
- `address`: local overlay IPv4 address
- `prefix_len`: local prefix length
- `mtu`: interface MTU

`[[bootstrap_peers]]`

- `peer_id`: remote authenticated peer identifier
- `address`: bootstrap transport address

`[[allowed_peers]]`

- `peer_id`: remote authenticated peer identifier
- `prefix`: overlay prefix owned by that peer
- `relay_capable`: whether the peer may act as a relay fallback

`[policy]`

- `strict_allowlist`: require explicit peer allowlisting
- `allow_relay`: permit relay fallback
- `allow_signaling_upgrade`: permit direct-path upgrade after signaling

## Validation

Use:

```text
vine config validate -c /etc/libvine/vine.toml
```

Validation currently checks:

- TOML-shaped section and key parsing
- repeated `bootstrap_peers` and `allowed_peers` records
- boolean and integer field decoding
- config path must be absolute and not group/world writable
- identity path must be absolute and point to a `0600` file

Malformed config should be rejected before daemon startup rather than at packet-forwarding time.
