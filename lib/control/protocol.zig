const types = @import("../core/types.zig");
const VineError = @import("../common/error.zig").VineError;
const std = @import("std");

pub const protocol_version_major: u16 = 0;
pub const protocol_version_minor: u16 = 1;
pub const max_message_len: usize = types.max_control_payload_len;
pub const max_setup_metadata_len: usize = 512;

pub const MessageTag = enum(u8) {
    hello = 1,
    join_announce = 2,
    route_update = 3,
    route_withdraw = 4,
    keepalive = 5,
    diagnostic_ping = 6,
    diagnostic_pong = 7,
};

pub const CapabilityFlags = packed struct(u8) {
    relay_capable: bool = false,
    direct_capable: bool = true,
    diagnostic_capable: bool = false,
    reserved: u5 = 0,
};

pub const Hello = struct {
    network_id: types.NetworkId,
    version_major: u16,
    version_minor: u16,
    capabilities: CapabilityFlags = .{},
};

pub const JoinAnnounce = struct {
    network_id: types.NetworkId,
    prefix: types.VinePrefix,
    epoch: types.MembershipEpoch,
};

pub const RouteUpdate = struct {
    network_id: types.NetworkId,
    owner: types.PeerId,
    prefix: types.VinePrefix,
    epoch: types.MembershipEpoch,
};

pub const RouteWithdraw = struct {
    network_id: types.NetworkId,
    owner: types.PeerId,
    prefix: types.VinePrefix,
    epoch: types.MembershipEpoch,
};

pub const Keepalive = struct {
    network_id: types.NetworkId,
    session_id: types.SessionId,
    sent_at_ms: i64,
};

pub const DiagnosticPing = struct {
    network_id: types.NetworkId,
    nonce: u64,
    sent_at_ms: i64,
};

pub const DiagnosticPong = struct {
    network_id: types.NetworkId,
    nonce: u64,
    replied_at_ms: i64,
};

pub const Message = union(MessageTag) {
    hello: Hello,
    join_announce: JoinAnnounce,
    route_update: RouteUpdate,
    route_withdraw: RouteWithdraw,
    keepalive: Keepalive,
    diagnostic_ping: DiagnosticPing,
    diagnostic_pong: DiagnosticPong,
};

pub const ValidationContext = struct {
    network_id: types.NetworkId,
    peer_id: ?types.PeerId = null,
};

pub fn encodeAlloc(allocator: std.mem.Allocator, message: Message) VineError![]u8 {
    var bytes = std.ArrayList(u8){};
    defer bytes.deinit(allocator);

    bytes.append(allocator, @intFromEnum(message)) catch return VineError.MessageTooLarge;
    appendU16(&bytes, allocator, protocol_version_major) catch return VineError.MessageTooLarge;
    appendU16(&bytes, allocator, protocol_version_minor) catch return VineError.MessageTooLarge;

    switch (message) {
        .hello => |m| {
            try appendNetworkId(&bytes, allocator, m.network_id);
            bytes.append(allocator, @bitCast(m.capabilities)) catch return VineError.MessageTooLarge;
            appendU16(&bytes, allocator, m.version_major) catch return VineError.MessageTooLarge;
            appendU16(&bytes, allocator, m.version_minor) catch return VineError.MessageTooLarge;
        },
        .join_announce => |m| {
            try appendNetworkId(&bytes, allocator, m.network_id);
            try appendPrefix(&bytes, allocator, m.prefix);
            appendU64(&bytes, allocator, m.epoch.value) catch return VineError.MessageTooLarge;
        },
        .route_update => |m| {
            try appendNetworkId(&bytes, allocator, m.network_id);
            try appendPeerId(&bytes, allocator, m.owner);
            try appendPrefix(&bytes, allocator, m.prefix);
            appendU64(&bytes, allocator, m.epoch.value) catch return VineError.MessageTooLarge;
        },
        .route_withdraw => |m| {
            try appendNetworkId(&bytes, allocator, m.network_id);
            try appendPeerId(&bytes, allocator, m.owner);
            try appendPrefix(&bytes, allocator, m.prefix);
            appendU64(&bytes, allocator, m.epoch.value) catch return VineError.MessageTooLarge;
        },
        .keepalive => |m| {
            try appendNetworkId(&bytes, allocator, m.network_id);
            appendU64(&bytes, allocator, m.session_id.value) catch return VineError.MessageTooLarge;
            appendI64(&bytes, allocator, m.sent_at_ms) catch return VineError.MessageTooLarge;
        },
        .diagnostic_ping => |m| {
            try appendNetworkId(&bytes, allocator, m.network_id);
            appendU64(&bytes, allocator, m.nonce) catch return VineError.MessageTooLarge;
            appendI64(&bytes, allocator, m.sent_at_ms) catch return VineError.MessageTooLarge;
        },
        .diagnostic_pong => |m| {
            try appendNetworkId(&bytes, allocator, m.network_id);
            appendU64(&bytes, allocator, m.nonce) catch return VineError.MessageTooLarge;
            appendI64(&bytes, allocator, m.replied_at_ms) catch return VineError.MessageTooLarge;
        },
    }

    if (bytes.items.len > max_message_len) return VineError.MessageTooLarge;
    return bytes.toOwnedSlice(allocator) catch return VineError.MessageTooLarge;
}

pub fn decode(data: []const u8) VineError!Message {
    if (data.len < 5 or data.len > max_message_len) return VineError.InvalidControlMessage;

    var cursor: usize = 0;
    const tag = std.meta.intToEnum(MessageTag, data[cursor]) catch return VineError.InvalidControlMessage;
    cursor += 1;

    if (try readU16(data, &cursor) != protocol_version_major) return VineError.VersionMismatch;
    if (try readU16(data, &cursor) != protocol_version_minor) return VineError.VersionMismatch;

    const message = switch (tag) {
        .hello => blk: {
            const network_id = try readNetworkId(data, &cursor);
            if (cursor >= data.len) return VineError.InvalidControlMessage;
            const capabilities: CapabilityFlags = @bitCast(data[cursor]);
            cursor += 1;
            const version_major = try readU16(data, &cursor);
            const version_minor = try readU16(data, &cursor);
            break :blk Message{ .hello = .{
                .network_id = network_id,
                .version_major = version_major,
                .version_minor = version_minor,
                .capabilities = capabilities,
            } };
        },
        .join_announce => .{ .join_announce = .{
            .network_id = try readNetworkId(data, &cursor),
            .prefix = try readPrefix(data, &cursor),
            .epoch = .{ .value = try readU64(data, &cursor) },
        } },
        .route_update => .{ .route_update = .{
            .network_id = try readNetworkId(data, &cursor),
            .owner = try readPeerId(data, &cursor),
            .prefix = try readPrefix(data, &cursor),
            .epoch = .{ .value = try readU64(data, &cursor) },
        } },
        .route_withdraw => .{ .route_withdraw = .{
            .network_id = try readNetworkId(data, &cursor),
            .owner = try readPeerId(data, &cursor),
            .prefix = try readPrefix(data, &cursor),
            .epoch = .{ .value = try readU64(data, &cursor) },
        } },
        .keepalive => .{ .keepalive = .{
            .network_id = try readNetworkId(data, &cursor),
            .session_id = .{ .value = try readU64(data, &cursor) },
            .sent_at_ms = try readI64(data, &cursor),
        } },
        .diagnostic_ping => .{ .diagnostic_ping = .{
            .network_id = try readNetworkId(data, &cursor),
            .nonce = try readU64(data, &cursor),
            .sent_at_ms = try readI64(data, &cursor),
        } },
        .diagnostic_pong => .{ .diagnostic_pong = .{
            .network_id = try readNetworkId(data, &cursor),
            .nonce = try readU64(data, &cursor),
            .replied_at_ms = try readI64(data, &cursor),
        } },
    };

    if (cursor != data.len) return VineError.InvalidControlMessage;
    return message;
}

pub fn fitsSetupMetadata(message: Message) bool {
    return switch (message) {
        .hello, .join_announce => encodedLen(message) <= max_setup_metadata_len,
        else => false,
    };
}

pub fn validate(message: Message, ctx: ValidationContext) VineError!void {
    switch (message) {
        .hello => |m| {
            if (!m.network_id.eql(ctx.network_id)) return VineError.NetworkMismatch;
            if (m.version_major != protocol_version_major) return VineError.VersionMismatch;
        },
        .join_announce => |m| {
            if (!m.network_id.eql(ctx.network_id)) return VineError.NetworkMismatch;
        },
        .route_update => |m| {
            if (!m.network_id.eql(ctx.network_id)) return VineError.NetworkMismatch;
            if (ctx.peer_id) |peer_id| {
                if (!m.owner.eql(peer_id)) return VineError.PeerMismatch;
            }
        },
        .route_withdraw => |m| {
            if (!m.network_id.eql(ctx.network_id)) return VineError.NetworkMismatch;
            if (ctx.peer_id) |peer_id| {
                if (!m.owner.eql(peer_id)) return VineError.PeerMismatch;
            }
        },
        .keepalive => |m| {
            if (!m.network_id.eql(ctx.network_id)) return VineError.NetworkMismatch;
        },
        .diagnostic_ping => |m| {
            if (!m.network_id.eql(ctx.network_id)) return VineError.NetworkMismatch;
        },
        .diagnostic_pong => |m| {
            if (!m.network_id.eql(ctx.network_id)) return VineError.NetworkMismatch;
        },
    }
}

fn appendNetworkId(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, network_id: types.NetworkId) VineError!void {
    bytes.append(allocator, @intCast(network_id.encode().len)) catch return VineError.MessageTooLarge;
    bytes.appendSlice(allocator, network_id.encode()) catch return VineError.MessageTooLarge;
}

fn encodedLen(message: Message) usize {
    return switch (message) {
        .hello => |m| 1 + 2 + 2 + 1 + m.network_id.encode().len + 1 + 2 + 2,
        .join_announce => |m| 1 + 2 + 2 + 1 + m.network_id.encode().len + 5 + 8,
        .route_update => |m| 1 + 2 + 2 + 1 + m.network_id.encode().len + types.peer_id_len + 5 + 8,
        .route_withdraw => |m| 1 + 2 + 2 + 1 + m.network_id.encode().len + types.peer_id_len + 5 + 8,
        .keepalive => |m| 1 + 2 + 2 + 1 + m.network_id.encode().len + 8 + 8,
        .diagnostic_ping => |m| 1 + 2 + 2 + 1 + m.network_id.encode().len + 8 + 8,
        .diagnostic_pong => |m| 1 + 2 + 2 + 1 + m.network_id.encode().len + 8 + 8,
    };
}

fn appendPeerId(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, peer_id: types.PeerId) VineError!void {
    bytes.appendSlice(allocator, peer_id.encode()) catch return VineError.MessageTooLarge;
}

fn appendPrefix(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, prefix: types.VinePrefix) VineError!void {
    bytes.appendSlice(allocator, &prefix.network.octets) catch return VineError.MessageTooLarge;
    bytes.append(allocator, prefix.prefix_len) catch return VineError.MessageTooLarge;
}

fn appendU16(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    try bytes.append(allocator, @intCast(value & 0xff));
    try bytes.append(allocator, @intCast((value >> 8) & 0xff));
}

fn appendU64(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var shift: u6 = 0;
    while (shift < 64) : (shift += 8) {
        try bytes.append(allocator, @intCast((value >> shift) & 0xff));
    }
}

fn appendI64(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i64) !void {
    try appendU64(bytes, allocator, @bitCast(value));
}

fn readU16(data: []const u8, cursor: *usize) VineError!u16 {
    if (cursor.* + 2 > data.len) return VineError.InvalidControlMessage;
    defer cursor.* += 2;
    return @as(u16, data[cursor.*]) | (@as(u16, data[cursor.* + 1]) << 8);
}

fn readU64(data: []const u8, cursor: *usize) VineError!u64 {
    if (cursor.* + 8 > data.len) return VineError.InvalidControlMessage;
    var out: u64 = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        out |= @as(u64, data[cursor.* + i]) << @intCast(i * 8);
    }
    cursor.* += 8;
    return out;
}

fn readI64(data: []const u8, cursor: *usize) VineError!i64 {
    return @bitCast(try readU64(data, cursor));
}

fn readNetworkId(data: []const u8, cursor: *usize) VineError!types.NetworkId {
    if (cursor.* >= data.len) return VineError.InvalidControlMessage;
    const len = data[cursor.*];
    cursor.* += 1;
    if (cursor.* + len > data.len) return VineError.InvalidControlMessage;
    defer cursor.* += len;
    return types.NetworkId.decode(data[cursor.* .. cursor.* + len]);
}

fn readPeerId(data: []const u8, cursor: *usize) VineError!types.PeerId {
    if (cursor.* + types.peer_id_len > data.len) return VineError.InvalidControlMessage;
    defer cursor.* += types.peer_id_len;
    return types.PeerId.decode(data[cursor.* .. cursor.* + types.peer_id_len]);
}

fn readPrefix(data: []const u8, cursor: *usize) VineError!types.VinePrefix {
    if (cursor.* + 5 > data.len) return VineError.InvalidControlMessage;
    const address = types.VineAddress.init(.{
        data[cursor.*],
        data[cursor.* + 1],
        data[cursor.* + 2],
        data[cursor.* + 3],
    });
    cursor.* += 4;
    const prefix_len = data[cursor.*];
    cursor.* += 1;
    return types.VinePrefix.init(address, prefix_len);
}
