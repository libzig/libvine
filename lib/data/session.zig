const frame = @import("frame.zig");
const control_codec = @import("control_codec.zig");
const types = @import("../core/types.zig");
const protocol = @import("../control/protocol.zig");
const VineError = @import("../common/error.zig").VineError;
const std = @import("std");

pub const EncodedFrame = struct {
    header: frame.Header,
    payload: []u8,
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
};
