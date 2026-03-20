const protocol = @import("../control/protocol.zig");
const VineError = @import("../common/error.zig").VineError;
const std = @import("std");

pub fn encodeAlloc(allocator: std.mem.Allocator, message: protocol.Message) VineError![]u8 {
    return protocol.encodeAlloc(allocator, message);
}

pub fn decode(data: []const u8) VineError!protocol.Message {
    return protocol.decode(data);
}

test "control codec round trips control messages and rejects wrong version" {
    const allocator = std.testing.allocator;
    const message = protocol.Message{ .hello = .{
        .network_id = try @import("../core/types.zig").NetworkId.init("devnet"),
        .version_major = protocol.protocol_version_major,
        .version_minor = protocol.protocol_version_minor,
        .capabilities = .{},
    } };
    const encoded = try encodeAlloc(allocator, message);
    defer allocator.free(encoded);

    const decoded = try decode(encoded);
    try std.testing.expectEqual(protocol.MessageTag.hello, std.meta.activeTag(decoded));

    var wrong_version = try allocator.dupe(u8, encoded);
    defer allocator.free(wrong_version);
    wrong_version[1] = 0xff;
    try std.testing.expectError(VineError.VersionMismatch, decode(wrong_version));
}
