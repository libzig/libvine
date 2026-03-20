const api = @import("../api/api.zig");
const linux = @import("../linux/linux.zig");

pub const TunRuntime = struct {
    node: *api.node.Node,
    installed_routes: []linux.routes.InstalledRoute,

    pub fn init(node: *api.node.Node, installed_routes: []linux.routes.InstalledRoute) TunRuntime {
        return .{
            .node = node,
            .installed_routes = installed_routes,
        };
    }
};

test "tun runtime captures node and route installation storage" {
    const std = @import("std");
    const core = @import("../core/core.zig");

    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{};
    var installed = [_]linux.routes.InstalledRoute{
        .{ .prefix = try core.types.VinePrefix.parse("10.42.1.0/24") },
    };

    var node = try api.node.Node.init(.{
        .network_id = try core.types.NetworkId.init("home-net"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'i', 'n', 'e', '0', 0 } ++ ([_]u8{0} ** 10),
            .local_address = try core.types.VineAddress.parse("10.42.0.1"),
            .prefix_len = 24,
            .mtu = 1400,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });

    const runtime = TunRuntime.init(&node, &installed);
    try std.testing.expectEqual(@as(usize, 1), runtime.installed_routes.len);
    try std.testing.expectEqual(@as(i32, 1), runtime.node.tun.fd);
}
