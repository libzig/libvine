# Linux

The MVP assumes a Linux host with access to `/dev/net/tun` and sufficient privileges to create and configure a TUN interface.

## Expectations

- `libvine` opens and manages a TUN device in userspace
- the host must allow interface creation and address assignment
- local route installation is expected for remote overlay prefixes
- one process owns one overlay instance and its associated TUN interface

## Operational Notes

- interface and route management should stay narrow and explicit
- shell fallbacks, if used at all, should be tightly scoped and easy to audit
- privilege requirements and failure modes should be surfaced clearly to callers and operators
