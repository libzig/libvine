const types = @import("../core/types.zig");
const VineError = @import("../common/error.zig").VineError;
const std = @import("std");

pub const FeatureFlags = packed struct(u8) {
    supports_relay: bool = true,
    supports_diagnostics: bool = false,
    reserved: u6 = 0,
};

pub const SessionMetadata = struct {
    network_id: types.NetworkId,
    prefix: types.VinePrefix,
    transport_version_major: u16,
    transport_version_minor: u16,
    features: FeatureFlags = .{},
};

pub fn encodeAlloc(allocator: std.mem.Allocator, metadata: SessionMetadata) VineError![]u8 {
    var bytes = std.ArrayList(u8){};
    defer bytes.deinit(allocator);

    bytes.append(allocator, @intCast(metadata.network_id.encode().len)) catch return VineError.MessageTooLarge;
    bytes.appendSlice(allocator, metadata.network_id.encode()) catch return VineError.MessageTooLarge;
    bytes.appendSlice(allocator, &metadata.prefix.network.octets) catch return VineError.MessageTooLarge;
    bytes.append(allocator, metadata.prefix.prefix_len) catch return VineError.MessageTooLarge;
    appendU16(&bytes, allocator, metadata.transport_version_major) catch return VineError.MessageTooLarge;
    appendU16(&bytes, allocator, metadata.transport_version_minor) catch return VineError.MessageTooLarge;
    bytes.append(allocator, @bitCast(metadata.features)) catch return VineError.MessageTooLarge;

    if (bytes.items.len > types.max_control_payload_len) return VineError.MessageTooLarge;
    return bytes.toOwnedSlice(allocator) catch return VineError.MessageTooLarge;
}

fn appendU16(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    try bytes.append(allocator, @intCast(value & 0xff));
    try bytes.append(allocator, @intCast((value >> 8) & 0xff));
}
