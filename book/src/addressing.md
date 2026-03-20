# Addressing

The MVP uses an IPv4-only overlay model.

## Overlay Semantics

- each node belongs to one named overlay network
- each node owns one primary IPv4 prefix for the MVP
- packet forwarding is based on prefix ownership, not dynamic distributed routing
- route selection prefers the best reachable session provided by `libmesh`

## Initial Constraints

- no IPv6 data plane in the MVP
- no multi-prefix complexity unless later slices explicitly add it
- no overlapping prefix acceptance without a deterministic conflict policy

The addressing model stays intentionally small so control-plane compatibility and forwarding behavior can stabilize before broader routing features are attempted.
