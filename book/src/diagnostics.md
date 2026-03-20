# Diagnostics

Step 9 turns `vine` into an operator-facing tool instead of a Zig-only runtime.

The current diagnostics commands are:

- `vine status`
- `vine peers`
- `vine routes`
- `vine sessions`
- `vine counters`
- `vine snapshot`
- `vine ping <overlay-ip>`

These commands are config-driven and are meant to answer different questions:

- `status`: is the node configured correctly and what overlay identity is it using?
- `peers`: which peers and prefixes are configured?
- `routes`: which overlay prefixes point at which peers?
- `sessions`: which session class is preferred for each peer?
- `counters`: are packets failing, missing routes, or falling back to relay?
- `snapshot`: dump the major sections together
- `ping`: which peer and session would carry traffic to a given overlay IP?

Diagnostics support two explicit output modes:

- `--format text`
- `--format json`

Use text for shell-driven inspection and JSON for machine parsing.

The counters surface currently includes:

- `packets_sent`
- `packets_received`
- `route_misses`
- `session_failures`
- `fallback_transitions`
- `relay_usage`

`relay_usage` is especially useful when a deployment is technically working but direct paths are not being selected as often as expected.

Example:

```text
vine status --format text -c /etc/libvine/vine.toml
vine sessions --format json -c /etc/libvine/vine.toml
vine ping --format text -c /etc/libvine/vine.toml 10.42.9.7
```

This is still a lightweight diagnostics layer, but it is now good enough to inspect peer ownership, route intent, preferred transport paths, and relay dependence without reading the Zig code.
