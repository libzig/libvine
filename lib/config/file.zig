const std = @import("std");

pub const FileConfig = struct {
    raw: []const u8,
};

pub fn init(raw: []const u8) FileConfig {
    return .{ .raw = raw };
}

test "file config module exists" {
    const cfg = init("network_id = demo");
    try std.testing.expectEqualStrings("network_id = demo", cfg.raw);
}
