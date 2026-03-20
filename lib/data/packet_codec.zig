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

test "packet codec accepts IPv4 payloads and rejects invalid versions" {
    const allocator = std.testing.allocator;
    const packet = [_]u8{ 0x45, 0x00, 0x00, 0x14 } ++ ([_]u8{0} ** 16);
    const encoded = try encodeAlloc(allocator, &packet);
    defer allocator.free(encoded);

    try std.testing.expectEqualSlices(u8, &packet, try decode(encoded));
    try std.testing.expectError(VineError.ParseFailure, decode(&[_]u8{ 0x60, 0x00 }));
}

test "packet codec fuzz-style mutations reject malformed data payloads" {
    const allocator = std.testing.allocator;
    const packet = @import("../testing/fixtures.zig").packet(.{ 10, 1, 0, 1 }, .{ 10, 2, 0, 1 });
    const encoded = try encodeAlloc(allocator, &packet);
    defer allocator.free(encoded);

    for (0..encoded.len) |index| {
        var mutated = try allocator.dupe(u8, encoded);
        defer allocator.free(mutated);

        if (index == 0) {
            mutated[index] = 0x60;
            try std.testing.expectError(VineError.ParseFailure, decode(mutated));
            continue;
        }

        mutated[index] |= 0x0f;
        try std.testing.expectEqual(mutated.len, (try decode(mutated)).len);
    }

    try std.testing.expectError(VineError.MessageTooLarge, decode(&.{}));
}
