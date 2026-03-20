# libvine Testing Guide

## Core Commands

- `make build`
- `make test`
- `zig build examples`

The development loop used for the MVP slices is:

1. apply one small change
2. run `make build`
3. run `make test`
4. commit only after both pass

## What Is Covered

The current test suite covers:

- core type parsing and validation
- route-table precedence, stale update rejection, withdrawals, and stress cases
- session promotion, churn, and relay fallback behavior
- control/data codec parsing, including mutation-style malformed input tests
- session send/receive framing
- fake Linux TUN lifecycle behavior
- node lifecycle, bootstrap, membership refresh, event callbacks, diagnostics, and debug snapshots
- direct, signaling-assisted, and relay-backed integration-style flows

## What Is Not Covered

The MVP tests do not currently provide:

- real multi-process Linux network namespace coverage
- live `libmesh` network interoperability beyond the adapter-level contract
- throughput or latency benchmarking
- privileged end-to-end route programming on a real host

## Recommended Downstream Practice

Downstream consumers should:

- reuse `lib/testing/fixtures.zig` for shared test setup
- keep integration tests deterministic and in-memory where possible
- add host-specific tests outside `libvine` when validating deployment environments
