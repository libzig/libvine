const types = @import("../core/types.zig");

pub const LinkState = struct {
    ifname: [16]u8 = [_]u8{0} ** 16,
    address: ?types.VineAddress = null,
    prefix_len: ?u8 = null,
    up: bool = false,
};
