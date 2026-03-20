const std = @import("std");
const VineError = @import("../common/error.zig").VineError;

pub const max_network_id_len: usize = 64;
pub const peer_id_len: usize = 32;
pub const max_control_payload_len: usize = 4 * 1024;
pub const max_data_payload_len: usize = 64 * 1024;
pub const max_prefix_count: usize = 256;
pub const max_route_table_entries: usize = 1024;

pub const NetworkId = struct {
    bytes: [max_network_id_len]u8 = [_]u8{0} ** max_network_id_len,
    len: u8 = 0,

    pub fn init(value: []const u8) VineError!NetworkId {
        if (value.len == 0 or value.len > max_network_id_len) return VineError.InvalidNetworkId;

        var id = NetworkId{};
        @memcpy(id.bytes[0..value.len], value);
        id.len = @intCast(value.len);
        return id;
    }

    pub fn decode(value: []const u8) VineError!NetworkId {
        return init(value);
    }

    pub fn encode(self: NetworkId) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(self: NetworkId, other: NetworkId) bool {
        return std.mem.eql(u8, self.encode(), other.encode());
    }
};

pub const VineAddress = struct {
    octets: [4]u8,

    pub fn init(octets: [4]u8) VineAddress {
        return .{ .octets = octets };
    }

    pub fn parse(text: []const u8) VineError!VineAddress {
        var iter = std.mem.splitScalar(u8, text, '.');
        var octets: [4]u8 = undefined;
        var index: usize = 0;

        while (iter.next()) |part| {
            if (index >= 4 or part.len == 0) return VineError.InvalidVineAddress;
            octets[index] = std.fmt.parseInt(u8, part, 10) catch return VineError.InvalidVineAddress;
            index += 1;
        }

        if (index != 4) return VineError.InvalidVineAddress;
        return init(octets);
    }

    pub fn eql(self: VineAddress, other: VineAddress) bool {
        return std.mem.eql(u8, &self.octets, &other.octets);
    }

    pub fn format(self: VineAddress, writer: anytype) !void {
        try writer.print("{d}.{d}.{d}.{d}", .{
            self.octets[0],
            self.octets[1],
            self.octets[2],
            self.octets[3],
        });
    }
};

pub const VinePrefix = struct {
    network: VineAddress,
    prefix_len: u8,

    pub fn init(address: VineAddress, prefix_len: u8) VineError!VinePrefix {
        if (prefix_len > 32) return VineError.InvalidVinePrefix;
        return .{
            .network = masked(address, prefix_len),
            .prefix_len = prefix_len,
        };
    }

    pub fn parse(text: []const u8) VineError!VinePrefix {
        var iter = std.mem.splitScalar(u8, text, '/');
        const address_text = iter.next() orelse return VineError.InvalidVinePrefix;
        const prefix_text = iter.next() orelse return VineError.InvalidVinePrefix;
        if (iter.next() != null) return VineError.InvalidVinePrefix;

        return init(
            try VineAddress.parse(address_text),
            std.fmt.parseInt(u8, prefix_text, 10) catch return VineError.InvalidVinePrefix,
        );
    }

    pub fn contains(self: VinePrefix, address: VineAddress) bool {
        return self.network.eql(masked(address, self.prefix_len));
    }

    fn masked(address: VineAddress, prefix_len: u8) VineAddress {
        var out = address;
        var remaining = prefix_len;

        for (&out.octets) |*octet| {
            if (remaining >= 8) {
                remaining -= 8;
                continue;
            }
            if (remaining == 0) {
                octet.* = 0;
                continue;
            }

            const shift: u3 = @intCast(8 - remaining);
            const mask: u8 = @as(u8, 0xff) << shift;
            octet.* &= mask;
            remaining = 0;
        }

        return out;
    }
};

pub const PeerId = struct {
    bytes: [peer_id_len]u8,

    pub fn init(bytes: [peer_id_len]u8) PeerId {
        return .{ .bytes = bytes };
    }

    pub fn decode(bytes: []const u8) VineError!PeerId {
        if (bytes.len != peer_id_len) return VineError.InvalidPeerId;

        var out: [peer_id_len]u8 = undefined;
        @memcpy(&out, bytes);
        return init(out);
    }

    pub fn encode(self: PeerId) []const u8 {
        return &self.bytes;
    }

    pub fn eql(self: PeerId, other: PeerId) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn format(self: PeerId, writer: anytype) !void {
        for (self.bytes) |byte| {
            try writer.print("{x:0>2}", .{byte});
        }
    }
};

pub const MembershipEpoch = struct {
    value: u64,

    pub fn init(value: u64) MembershipEpoch {
        return .{ .value = value };
    }

    pub fn next(self: MembershipEpoch) VineError!MembershipEpoch {
        if (self.value == std.math.maxInt(u64)) return VineError.InvalidMembershipEpoch;
        return init(self.value + 1);
    }

    pub fn eql(self: MembershipEpoch, other: MembershipEpoch) bool {
        return self.value == other.value;
    }
};

pub const SessionId = struct {
    value: u64,

    pub fn init(value: u64) SessionId {
        return .{ .value = value };
    }

    pub fn next(self: SessionId) VineError!SessionId {
        if (self.value == std.math.maxInt(u64)) return VineError.InvalidSessionId;
        return init(self.value + 1);
    }

    pub fn eql(self: SessionId, other: SessionId) bool {
        return self.value == other.value;
    }
};

pub const PacketKind = enum(u8) {
    control = 1,
    data = 2,
    keepalive = 3,
    diagnostic = 4,
};

test "NetworkId encode decode and equality" {
    const a = try NetworkId.init("devnet");
    const b = try NetworkId.decode("devnet");
    const c = try NetworkId.init("othernet");

    try std.testing.expectEqualStrings("devnet", a.encode());
    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
    try std.testing.expectError(VineError.InvalidNetworkId, NetworkId.init(""));
}

test "VineAddress parses formats and compares" {
    const address = try VineAddress.parse("10.42.0.7");
    const expected = VineAddress.init(.{ 10, 42, 0, 7 });

    try std.testing.expect(address.eql(expected));

    var buffer: [32]u8 = undefined;
    const text = try std.fmt.bufPrint(&buffer, "{f}", .{address});
    try std.testing.expectEqualStrings("10.42.0.7", text);
    try std.testing.expectError(VineError.InvalidVineAddress, VineAddress.parse("10.42.0"));
    try std.testing.expectError(VineError.InvalidVineAddress, VineAddress.parse("999.1.1.1"));
}

test "VinePrefix parses normalizes and contains addresses" {
    const prefix = try VinePrefix.parse("10.42.0.99/24");

    try std.testing.expectEqual(@as(u8, 24), prefix.prefix_len);
    try std.testing.expect(prefix.network.eql(VineAddress.init(.{ 10, 42, 0, 0 })));
    try std.testing.expect(prefix.contains(try VineAddress.parse("10.42.0.7")));
    try std.testing.expect(!prefix.contains(try VineAddress.parse("10.42.1.7")));
    try std.testing.expectError(VineError.InvalidVinePrefix, VinePrefix.parse("10.42.0.0/33"));
}

test "PeerId validates byte length and formatting" {
    const bytes = [_]u8{0xaa} ** peer_id_len;
    const peer = PeerId.init(bytes);
    const decoded = try PeerId.decode(&bytes);

    try std.testing.expect(peer.eql(decoded));

    var buffer: [peer_id_len * 2]u8 = undefined;
    const text = try std.fmt.bufPrint(&buffer, "{f}", .{peer});
    try std.testing.expectEqual(@as(usize, peer_id_len * 2), text.len);
    try std.testing.expectError(VineError.InvalidPeerId, PeerId.decode("short"));
}

test "MembershipEpoch and SessionId increment and validate bounds" {
    const epoch = MembershipEpoch.init(7);
    const next_epoch = try epoch.next();
    try std.testing.expect(epoch.eql(MembershipEpoch.init(7)));
    try std.testing.expect(next_epoch.eql(MembershipEpoch.init(8)));
    try std.testing.expectError(
        VineError.InvalidMembershipEpoch,
        MembershipEpoch.init(std.math.maxInt(u64)).next(),
    );

    const session = SessionId.init(11);
    const next_session = try session.next();
    try std.testing.expect(session.eql(SessionId.init(11)));
    try std.testing.expect(next_session.eql(SessionId.init(12)));
    try std.testing.expectError(
        VineError.InvalidSessionId,
        SessionId.init(std.math.maxInt(u64)).next(),
    );
}

test "PacketKind and shared limits stay stable" {
    try std.testing.expectEqual(PacketKind.control, @as(PacketKind, .control));
    try std.testing.expectEqual(PacketKind.data, @as(PacketKind, .data));
    try std.testing.expectEqual(PacketKind.keepalive, @as(PacketKind, .keepalive));
    try std.testing.expectEqual(PacketKind.diagnostic, @as(PacketKind, .diagnostic));

    try std.testing.expectEqual(@as(usize, 64), max_network_id_len);
    try std.testing.expectEqual(@as(usize, 32), peer_id_len);
    try std.testing.expectEqual(@as(usize, 4 * 1024), max_control_payload_len);
    try std.testing.expectEqual(@as(usize, 64 * 1024), max_data_payload_len);
    try std.testing.expectEqual(@as(usize, 256), max_prefix_count);
    try std.testing.expectEqual(@as(usize, 1024), max_route_table_entries);
}
