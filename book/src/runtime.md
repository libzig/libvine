# Runtime

Step 5 turns static config and persisted identity into a real startup model.

The key rule stays the same:

- `libself` identity determines who the node is
- config determines which overlay prefix the node advertises

Those are related at startup, but they are not the same thing.

## Runtime Translation

`lib/runtime/runtime_config.zig` now translates:

- `vine.toml`
- the persisted identity file

into runtime-facing state:

- `NodeConfig`
- local `PeerId`
- local `LocalMembership`
- allowlist-driven admission policy
- bootstrap peer startup state
- relay-capable peer declarations

## Startup Inputs

The runtime loader consumes:

- `[node]`
- `[tun]`
- `[[bootstrap_peers]]`
- `[[allowed_peers]]`
- `[policy]`

and the identity file referenced by `node.identity_path`.

The resulting startup state is then suitable for:

- `Node.init`
- `Node.start`
- foreground bring-up through `vine up`

## Operator Commands

`vine up -c /etc/libvine/vine.toml`

- loads config
- loads persisted identity
- derives the local peer identity from `libself`
- binds the configured local prefix into local membership
- starts the node in foreground mode

`vine down`

- reads the daemon pidfile when present
- sends a shutdown request
- removes the pidfile for controlled local stop

## Identity Versus Prefix

The same identity can be restarted with a different configured overlay prefix.
That should change the local membership prefix, but not the authenticated `PeerId`.

The runtime tests now lock that behavior in:

- identity is stable across reloads
- configured prefix is translated from config
- changing config address does not change peer identity
