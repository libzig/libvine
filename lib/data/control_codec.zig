const protocol = @import("../control/protocol.zig");
const VineError = @import("../common/error.zig").VineError;
const std = @import("std");

pub fn encodeAlloc(allocator: std.mem.Allocator, message: protocol.Message) VineError![]u8 {
    return protocol.encodeAlloc(allocator, message);
}

pub fn decode(data: []const u8) VineError!protocol.Message {
    return protocol.decode(data);
}
