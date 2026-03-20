# Identity

`libvine` node identity comes from `libself`, not from overlay IP addresses.

## Separation Of Concerns

- `libself` identity answers who the node is
- `NetworkId` answers which overlay the node is joining
- `VinePrefix` answers which virtual IP range the node advertises
- `libmesh` answers which path should carry traffic right now

## Persistent Identity

The `vine` binary stores node identity on disk so the same node can restart without
appearing as a new peer.

Current default path:

- `/var/lib/libvine/identity`

The persisted identity file is a text format with a stable header and derived public fields:

- `format`
- `seed`
- `public_key`
- `peer_id`
- `fingerprint`

## CLI Commands

- `vine identity init`
- `vine identity show`
- `vine identity export-public`
- `vine identity fingerprint`

## Enrollment Use

`export-public` is intended for enrollment and allowlist workflows. It exposes public identity material
that another node or operator can use when binding a peer identity to an overlay prefix.

The important rule is that the peer is trusted as a `libself` identity first, and only then
associated with overlay addressing policy.
