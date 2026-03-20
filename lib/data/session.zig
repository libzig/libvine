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
        const payload = try packet_codec.encodeAlloc(allocator, packet);
        if (payload.len > frame.max_unfragmented_payload_len) return VineError.MessageTooLarge;

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
