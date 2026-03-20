const types = @import("../core/types.zig");

pub const frame_version: u8 = 1;

pub const Header = packed struct {
    version: u8 = frame_version,
    kind: types.PacketKind,
    flags: u8 = 0,
    session_id: u64,
    payload_len: u32,
};
