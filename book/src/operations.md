# Operations

The `vine` binary is intended to support both development-time foreground use and long-running daemon use.

## Foreground Workflow

Foreground mode is for:

- initial configuration bring-up
- debugging TUN and routing behavior
- watching logs and counters interactively

The expected foreground flow is:

1. validate config
2. load identity
3. start the node runtime
4. observe peers, routes, sessions, and counters
5. stop cleanly with a signal or explicit command

## Daemon Workflow

Daemon mode is for:

- multi-PC deployments
- persistent background VPN service
- boot-time or service-manager startup

The expected daemon flow is:

1. start with a config file
2. record pidfile and state paths
3. own TUN lifecycle and session lifecycle
4. expose status and diagnostics through CLI subcommands
5. stop cleanly without leaking routes or stale runtime state

## Operational Priorities

- identity must load before overlay membership is advertised
- route ownership must remain tied to authenticated peers
- direct sessions should be preferred over relay when both are available
- relay fallback should be observable rather than silent
