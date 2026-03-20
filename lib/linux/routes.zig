const types = @import("../core/types.zig");

pub const InstalledRoute = struct {
    prefix: types.VinePrefix,
    ifname: [16]u8 = [_]u8{0} ** 16,
    active: bool = false,
};

pub fn install(route: *InstalledRoute, prefix: types.VinePrefix, ifname: [16]u8) void {
    route.prefix = prefix;
    route.ifname = ifname;
    route.active = true;
}

pub fn withdraw(route: *InstalledRoute) void {
    route.active = false;
}
