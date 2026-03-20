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

pub fn decode(data: []const u8) VineError!SessionMetadata {
    var cursor: usize = 0;
    if (data.len < 11) return VineError.InvalidControlMessage;

    const network_id_len = data[cursor];
    cursor += 1;
    if (cursor + network_id_len > data.len) return VineError.InvalidControlMessage;
    const network_id = try types.NetworkId.decode(data[cursor .. cursor + network_id_len]);
    cursor += network_id_len;

    if (cursor + 5 > data.len) return VineError.InvalidControlMessage;
    const prefix = try types.VinePrefix.init(types.VineAddress.init(.{
        data[cursor],
        data[cursor + 1],
        data[cursor + 2],
        data[cursor + 3],
    }), data[cursor + 4]);
    cursor += 5;

    const version_major = try readU16(data, &cursor);
    const version_minor = try readU16(data, &cursor);
    if (cursor >= data.len) return VineError.InvalidControlMessage;
    const features: FeatureFlags = @bitCast(data[cursor]);
    cursor += 1;
    if (cursor != data.len) return VineError.InvalidControlMessage;

    return .{
        .network_id = network_id,
        .prefix = prefix,
        .transport_version_major = version_major,
        .transport_version_minor = version_minor,
        .features = features,
    };
}

pub fn validateCompatibility(local: SessionMetadata, remote: SessionMetadata) VineError!void {
    try rejectWrongOverlay(local, remote);
    try rejectIncompatibleMajorVersion(local, remote);
}

pub fn rejectWrongOverlay(local: SessionMetadata, remote: SessionMetadata) VineError!void {
    if (!local.network_id.eql(remote.network_id)) return VineError.NetworkMismatch;
}

pub fn rejectIncompatibleMajorVersion(local: SessionMetadata, remote: SessionMetadata) VineError!void {
    if (local.transport_version_major != remote.transport_version_major) return VineError.VersionMismatch;
}

fn appendU16(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    try bytes.append(allocator, @intCast(value & 0xff));
    try bytes.append(allocator, @intCast((value >> 8) & 0xff));
}

fn readU16(data: []const u8, cursor: *usize) VineError!u16 {
    if (cursor.* + 2 > data.len) return VineError.InvalidControlMessage;
    defer cursor.* += 2;
    return @as(u16, data[cursor.*]) | (@as(u16, data[cursor.* + 1]) << 8);
}
