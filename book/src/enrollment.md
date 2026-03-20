# Enrollment

Enrollment in `libvine` is now explicit and deterministic.

The daemon no longer treats a discovered peer as automatically valid just because it exists on the network.
A remote membership update must satisfy all of the following:

- the peer is on the allowlist by `PeerId`
- the update targets the same configured `NetworkId`
- the peer is claiming the exact overlay prefix it was configured to own

## Phase-One Ownership Model

For phase one, each allowed peer owns one configured prefix.

That mapping comes from the node config and is translated into runtime enrollment state. The result is:

- one authenticated `PeerId`
- one owned `VinePrefix`
- optional relay-capable flag

This keeps ownership simple enough for real multi-PC bring-up without introducing distributed routing policy.

## Accepted Membership Flow

When a membership update is accepted:

1. remote membership state is refreshed
2. route-table state is updated for the accepted prefix
3. topology callbacks can observe the change

When a membership update is rejected:

- remote membership state is unchanged
- route-table state is unchanged

## Rejection Cases

Current rejection rules include:

- peer not present in the configured allowlist
- wrong overlay network ID
- claimed prefix does not match configured ownership
- overlapping configured peer prefixes at startup

## Shutdown

Withdrawal follows the inverse path:

- remote membership is marked expired
- the matching route is withdrawn
- topology observers receive the change

This keeps local routing state aligned with membership state during daemon shutdown and peer departure.
