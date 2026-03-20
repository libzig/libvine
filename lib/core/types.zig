const std = @import("std");

pub const NetworkId = struct {
    bytes: [64]u8 = [_]u8{0} ** 64,
    len: u8 = 0,

    pub fn init(value: []const u8) !NetworkId {
        if (value.len == 0 or value.len > 64) return error.InvalidNetworkId;

        var id = NetworkId{};
        @memcpy(id.bytes[0..value.len], value);
        id.len = @intCast(value.len);
        return id;
    }

    pub fn decode(value: []const u8) !NetworkId {
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

    pub fn parse(text: []const u8) !VineAddress {
        var iter = std.mem.splitScalar(u8, text, '.');
        var octets: [4]u8 = undefined;
        var index: usize = 0;

        while (iter.next()) |part| {
            if (index >= 4 or part.len == 0) return error.InvalidVineAddress;
            octets[index] = try std.fmt.parseInt(u8, part, 10);
            index += 1;
        }

        if (index != 4) return error.InvalidVineAddress;
        return init(octets);
    }

    pub fn eql(self: VineAddress, other: VineAddress) bool {
        return std.mem.eql(u8, &self.octets, &other.octets);
    }

    pub fn format(
        self: VineAddress,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
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

    pub fn init(address: VineAddress, prefix_len: u8) !VinePrefix {
        if (prefix_len > 32) return error.InvalidVinePrefix;
        return .{
            .network = masked(address, prefix_len),
            .prefix_len = prefix_len,
        };
    }

    pub fn parse(text: []const u8) !VinePrefix {
        var iter = std.mem.splitScalar(u8, text, '/');
        const address_text = iter.next() orelse return error.InvalidVinePrefix;
        const prefix_text = iter.next() orelse return error.InvalidVinePrefix;
        if (iter.next() != null) return error.InvalidVinePrefix;

        return init(
            try VineAddress.parse(address_text),
            try std.fmt.parseInt(u8, prefix_text, 10),
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
    bytes: [32]u8,

    pub fn init(bytes: [32]u8) PeerId {
        return .{ .bytes = bytes };
    }

    pub fn decode(bytes: []const u8) !PeerId {
        if (bytes.len != 32) return error.InvalidPeerId;

        var out: [32]u8 = undefined;
        @memcpy(&out, bytes);
        return init(out);
    }

    pub fn encode(self: PeerId) []const u8 {
        return &self.bytes;
    }

    pub fn eql(self: PeerId, other: PeerId) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn format(
        self: PeerId,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{}", .{std.fmt.fmtSliceHexLower(&self.bytes)});
    }
};

pub const MembershipEpoch = struct {
    value: u64,

    pub fn init(value: u64) MembershipEpoch {
        return .{ .value = value };
    }

    pub fn next(self: MembershipEpoch) !MembershipEpoch {
        if (self.value == std.math.maxInt(u64)) return error.InvalidMembershipEpoch;
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

    pub fn next(self: SessionId) !SessionId {
        if (self.value == std.math.maxInt(u64)) return error.InvalidSessionId;
        return init(self.value + 1);
    }

    pub fn eql(self: SessionId, other: SessionId) bool {
        return self.value == other.value;
    }
};
