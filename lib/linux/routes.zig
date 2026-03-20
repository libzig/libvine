const types = @import("../core/types.zig");

pub const InstalledRoute = struct {
    prefix: types.VinePrefix,
    ifname: [16]u8 = [_]u8{0} ** 16,
    active: bool = false,
};
