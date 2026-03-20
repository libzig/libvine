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

test "frame header and constants stay stable" {
    try @import("std").testing.expectEqual(@as(u8, 1), frame_version);
    try @import("std").testing.expectEqual(@as(usize, 1200), max_unfragmented_payload_len);

    const header = Header{
        .kind = .control,
        .flags = .{ .control_priority = true },
        .session_id = 42,
        .payload_len = 128,
    };
    try @import("std").testing.expectEqual(types.PacketKind.control, header.kind);
    try @import("std").testing.expect(header.flags.control_priority);
    try @import("std").testing.expectEqual(@as(u64, 42), header.session_id);
    try @import("std").testing.expectEqual(@as(u32, 128), header.payload_len);
}
