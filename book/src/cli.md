# CLI

`vine` is the operator-facing binary for running `libvine` as a real VPN process on Linux hosts.

## Top-Level Commands

- `vine help`
- `vine version`
- `vine identity`
- `vine config`
- `vine daemon`
- `vine status`
- `vine diagnostics`

## Command Intent

- `identity` manages persistent `libself`-backed node identity
- `config` manages validation and initialization of the node config file
- `daemon` controls long-running runtime lifecycle
- `status` reports current node and network state
- `diagnostics` exposes counters, snapshots, and debug output

## Current State

The binary surface is being built incrementally. The first milestone is to freeze the operator contract
before deeper identity, config, and daemon behavior is implemented.
