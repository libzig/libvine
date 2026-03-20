# libvine Troubleshooting

## Build Fails

If `make build` fails:

- confirm the Nix shell is active and Zig `0.15.2` is the toolchain in use
- check that local path dependencies `libself`, `libmesh`, `libdice`, and `libfast` are present
- remember that example programs are compiled as part of the build

## Test Fails

If `make test` fails:

- start with the failing module instead of chasing the full stack
- check whether a new test exposed a stale assumption in route/session fallback behavior
- confirm changes under `lib/data/` were force-added if Git ignore rules apply there

## Runtime Issues

Common runtime expectations:

- unknown routes should be dropped, not guessed
- unauthorized source peers should not inject packets into the TUN path
- relay fallback should preserve connectivity but not match direct-path performance
- stale session cleanup may detach routes if no relay fallback remains

## Linux Limitations

This MVP assumes:

- Linux only
- TUN-backed IPv4 L3 overlay behavior
- userspace-controlled route programming

Real host deployment may still require:

- elevated privileges for TUN setup
- explicit local route installation
- environment-specific firewall and namespace adjustments

## Debugging Tools

Use:

- node event callbacks for lifecycle and topology signals
- node diagnostics counters for traffic and failure trends
- `debugSnapshot()` for structured inspection of sessions and advertised prefixes
