const frame = @import("frame.zig");
const control_codec = @import("control_codec.zig");
const packet_codec = @import("packet_codec.zig");
const types = @import("../core/types.zig");
const protocol = @import("../control/protocol.zig");
const VineError = @import("../common/error.zig").VineError;
const std = @import("std");

pub const EncodedFrame = struct {
    header: frame.Header,
    payload: []u8,
};

pub const ReceivedFrame = union(types.PacketKind) {
    control: protocol.Message,
    data: []const u8,
    keepalive: []const u8,
    diagnostic: []const u8,
};

pub const Session = struct {
    session_id: types.SessionId,
    control_mode: frame.CarriageMode = .reliable_control_stream,
    data_mode: frame.CarriageMode = .packet_data_path,

    pub fn init(session_id: types.SessionId) Session {
        return .{ .session_id = session_id };
    }

    pub fn sendControl(self: Session, allocator: std.mem.Allocator, message: protocol.Message) VineError!EncodedFrame {
        const payload = try control_codec.encodeAlloc(allocator, message);
        return .{
            .header = .{
                .kind = .control,
                .flags = .{ .control_priority = true },
                .session_id = self.session_id.value,
                .payload_len = @intCast(payload.len),
            },
            .payload = payload,
        };
    }

    pub fn sendPacket(self: Session, allocator: std.mem.Allocator, packet: []const u8) VineError!EncodedFrame {
        if (packet.len > frame.max_unfragmented_payload_len) return VineError.MessageTooLarge;
        const payload = try packet_codec.encodeAlloc(allocator, packet);

        return .{
            .header = .{
                .kind = .data,
                .session_id = self.session_id.value,
                .payload_len = @intCast(payload.len),
            },
            .payload = payload,
        };
    }

    pub fn receive(self: Session, header: frame.Header, payload: []const u8) VineError!ReceivedFrame {
        _ = self;
        return switch (header.kind) {
            .control => .{ .control = try control_codec.decode(payload) },
            .data => .{ .data = try packet_codec.decode(payload) },
            .keepalive => .{ .keepalive = payload },
            .diagnostic => .{ .diagnostic = payload },
        };
    }
};

test "session send paths enforce frame kinds and payload bounds" {
    const allocator = std.testing.allocator;
    const session = Session.init(.{ .value = 9 });
    const control = try session.sendControl(allocator, .{ .hello = .{
        .network_id = try types.NetworkId.init("devnet"),
        .version_major = protocol.protocol_version_major,
        .version_minor = protocol.protocol_version_minor,
        .capabilities = .{},
    } });
    defer allocator.free(control.payload);

    try std.testing.expectEqual(types.PacketKind.control, control.header.kind);
    try std.testing.expect(control.header.flags.control_priority);

    const packet = [_]u8{ 0x45, 0x00, 0x00, 0x14 } ++ ([_]u8{0} ** 16);
    const data_frame = try session.sendPacket(allocator, &packet);
    defer allocator.free(data_frame.payload);
    try std.testing.expectEqual(types.PacketKind.data, data_frame.header.kind);

    const oversized = try allocator.alloc(u8, frame.max_unfragmented_payload_len + 1);
    defer allocator.free(oversized);
    @memset(oversized, 0);
    oversized[0] = 0x45;
    try std.testing.expectError(VineError.MessageTooLarge, session.sendPacket(allocator, oversized));
}

test "session receive demux routes control and packet payloads" {
    const allocator = std.testing.allocator;
    const session = Session.init(.{ .value = 5 });

    const control = try session.sendControl(allocator, .{ .hello = .{
        .network_id = try types.NetworkId.init("meshnet"),
        .version_major = protocol.protocol_version_major,
        .version_minor = protocol.protocol_version_minor,
        .capabilities = .{},
    } });
    defer allocator.free(control.payload);
    const received_control = try session.receive(control.header, control.payload);
    try std.testing.expectEqual(types.PacketKind.control, std.meta.activeTag(received_control));

    const packet = [_]u8{ 0x45, 0x00, 0x00, 0x14 } ++ ([_]u8{0} ** 16);
    const data_frame = try session.sendPacket(allocator, &packet);
    defer allocator.free(data_frame.payload);
    const received_data = try session.receive(data_frame.header, data_frame.payload);
    try std.testing.expectEqual(types.PacketKind.data, std.meta.activeTag(received_data));
    try std.testing.expectEqualSlices(u8, &packet, received_data.data);
}
