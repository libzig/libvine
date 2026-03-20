const VineError = @import("../common/error.zig").VineError;
const types = @import("../core/types.zig");
const std = @import("std");

pub fn encodeAlloc(allocator: std.mem.Allocator, packet: []const u8) VineError![]u8 {
    if (packet.len == 0 or packet.len > types.max_data_payload_len) return VineError.MessageTooLarge;
    if ((packet[0] >> 4) != 4) return VineError.ParseFailure;
    return allocator.dupe(u8, packet) catch return VineError.MessageTooLarge;
}

pub fn decode(packet: []const u8) VineError![]const u8 {
    if (packet.len == 0 or packet.len > types.max_data_payload_len) return VineError.MessageTooLarge;
    if ((packet[0] >> 4) != 4) return VineError.ParseFailure;
    return packet;
}
