const types = @import("../core/types.zig");

pub const frame_version: u8 = 1;
pub const max_unfragmented_payload_len: usize = 1200;

pub const CarriageMode = enum {
    reliable_control_stream,
    packet_data_path,
};

pub const Flags = packed struct(u8) {
    fragmented: bool = false,
    control_priority: bool = false,
    compressed: bool = false,
    reserved: u5 = 0,
};

pub const Header = packed struct {
    version: u8 = frame_version,
    kind: types.PacketKind,
    flags: Flags = .{},
    session_id: u64,
    payload_len: u32,
};
