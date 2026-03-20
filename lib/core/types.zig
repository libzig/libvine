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
