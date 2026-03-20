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
