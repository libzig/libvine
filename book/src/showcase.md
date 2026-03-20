# Multi-PC Showcase

The `examples/multi-pc/` directory is the reference deployment story for `vine` as a real binary.

It uses four Linux machines running the same executable:

- `alpha`
- `beta`
- `gamma`
- `relay`

Each machine keeps its own `libself` identity file and advertises one overlay prefix into the same network:

- `alpha` -> `10.42.0.0/24`
- `beta` -> `10.42.1.0/24`
- `gamma` -> `10.42.2.0/24`
- `relay` -> `10.42.254.0/24`

## Expected Path Story

The example is designed to demonstrate three normal cases and one failure case:

1. `alpha` talks to `beta` over a direct session.
2. `gamma` reaches `beta` after signaling-assisted setup.
3. `gamma` reaches `alpha` through `relay` if no direct path can be formed.
4. `alpha` falls back to `relay` if the direct path to `beta` disappears.

That is the intended `vine` operator model:

- direct when possible
- signaling when setup is needed
- relay when direct reachability fails

## Narrative Walkthrough

Start with all four configs installed and one identity generated per machine.

Bring up `relay` first so the other nodes have a stable bootstrap target. Then start `alpha`, `beta`, and `gamma`.

Once all nodes are running:

- `vine peers` should show the allowlisted remote peers
- `vine routes` should show owned prefixes for those peers
- `vine sessions` should initially favor direct or signaling-assisted paths when available

Now force a direct-path failure between `alpha` and `beta`. The expected recovery is:

- route ownership stays the same
- the preferred session changes
- `relay_usage` and `fallback_transitions` increase
- traffic still has a path through `relay`

This is why relay capability belongs to the peer policy layer instead of to the overlay address itself.

## Files

- `examples/multi-pc/README.md`
- `examples/multi-pc/alpha.toml`
- `examples/multi-pc/beta.toml`
- `examples/multi-pc/gamma.toml`
- `examples/multi-pc/relay.toml`
