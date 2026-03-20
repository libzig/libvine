# Packet Flow

Step 8 turns the runtime into a real packet path instead of just a session and membership model.

The flow is:

1. read an IP packet from the TUN device
2. inspect the overlay destination address
3. match the destination against the route table
4. choose the preferred session for the route's peer
5. send the packet over that session
6. receive packets from authorized peers
7. inject inbound packets back into the local TUN device

`TunRuntime` owns the bridge between:

- `Node`
- the Linux-facing TUN handle
- installed Linux route state
- packet drop reasons

The runtime keeps explicit drop behavior:

- unknown overlay destinations are dropped as `unknown_route`
- unauthorized peers are dropped as `unauthorized_peer`
- missing session state is dropped as `no_session`

Route cleanup stays explicit too:

- withdrawing membership detaches the installed route
- stale direct sessions downgrade to relay when relay fallback exists
- stale sessions without fallback tombstone the route

The fake transport tests exercise end-to-end packet movement between nodes without needing
real sockets. That gives us coverage for:

- outbound route lookup
- preferred-session dispatch
- inbound TUN injection
- route teardown and downgrade behavior

This is the point where the daemon starts resembling a real overlay dataplane instead of
just a configuration and identity shell.
