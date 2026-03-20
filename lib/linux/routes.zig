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

test "route install and withdraw target the tun interface" {
    var route = InstalledRoute{
        .prefix = try types.VinePrefix.parse("10.9.0.0/24"),
    };
    var ifname: [16]u8 = [_]u8{0} ** 16;
    ifname[0] = 'v';
    ifname[1] = 'n';
    ifname[2] = '0';

    install(&route, try types.VinePrefix.parse("10.9.1.0/24"), ifname);
    try @import("std").testing.expect(route.active);
    try @import("std").testing.expectEqual(@as(u8, 'v'), route.ifname[0]);
    try @import("std").testing.expect(route.prefix.network.eql(types.VineAddress.init(.{ 10, 9, 1, 0 })));

    withdraw(&route);
    try @import("std").testing.expect(!route.active);
}
