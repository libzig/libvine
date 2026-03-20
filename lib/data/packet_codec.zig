const VineError = @import("../common/error.zig").VineError;
const types = @import("../core/types.zig");
const std = @import("std");

pub fn encodeAlloc(allocator: std.mem.Allocator, packet: []const u8) VineError![]u8 {
    try validatePacket(packet);
    return allocator.dupe(u8, packet) catch return VineError.MessageTooLarge;
}

pub fn decode(packet: []const u8) VineError![]const u8 {
    try validatePacket(packet);
    return packet;
}

fn validatePacket(packet: []const u8) VineError!void {
    if (packet.len == 0 or packet.len > types.max_data_payload_len) return VineError.MessageTooLarge;
    if (packet.len < 20) return VineError.ParseFailure;
    if ((packet[0] >> 4) != 4) return VineError.ParseFailure;

    const ihl_words = packet[0] & 0x0f;
    if (ihl_words < 5) return VineError.ParseFailure;

    const header_len = @as(usize, ihl_words) * 4;
    if (header_len > packet.len) return VineError.ParseFailure;

    const total_len = (@as(u16, packet[2]) << 8) | @as(u16, packet[3]);
    if (total_len < header_len or total_len > packet.len) return VineError.ParseFailure;
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
        _ = decode(mutated) catch |err| {
            try std.testing.expect(err == VineError.ParseFailure);
            continue;
        };
        try std.testing.expectEqual(mutated.len, (try decode(mutated)).len);
    }

    try std.testing.expectError(VineError.MessageTooLarge, decode(&.{}));
}

test "packet codec rejects invalid ihl and total length combinations" {
    const short_header = [_]u8{ 0x44, 0x00, 0x00, 0x14 } ++ ([_]u8{0} ** 16);
    try std.testing.expectError(VineError.ParseFailure, decode(&short_header));

    const oversized_total = [_]u8{ 0x45, 0x00, 0x00, 0x40 } ++ ([_]u8{0} ** 16);
    try std.testing.expectError(VineError.ParseFailure, decode(&oversized_total));

    const undersized_total = [_]u8{ 0x46, 0x00, 0x00, 0x14 } ++ ([_]u8{0} ** 20);
    try std.testing.expectError(VineError.ParseFailure, decode(&undersized_total));
}
