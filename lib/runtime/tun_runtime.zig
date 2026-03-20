const api = @import("../api/api.zig");
const linux = @import("../linux/linux.zig");
const enrollment = @import("enrollment.zig");

pub const TunRuntime = struct {
    node: *api.node.Node,
    installed_routes: []linux.routes.InstalledRoute,

    pub fn init(node: *api.node.Node, installed_routes: []linux.routes.InstalledRoute) TunRuntime {
        return .{
            .node = node,
            .installed_routes = installed_routes,
        };
    }

    pub fn openAndConfigureTun(self: *TunRuntime) !void {
        if (self.node.tun.fd < 0) {
            self.node.tun = try linux.tun.TunDevice.open();
        }
        self.node.tun.applyConfig(self.node.config.tun);
    }

    pub fn installConfiguredRoutes(self: *TunRuntime, peers: []const enrollment.EnrollmentState.EnrolledPeer) usize {
        var installed_count: usize = 0;
        for (peers, 0..) |peer, index| {
            if (index >= self.installed_routes.len or index >= self.node.route_table.entries.len) break;
            linux.routes.install(&self.installed_routes[index], peer.prefix, self.node.tun.ifname);
            self.node.route_table.entries[index] = .{
                .prefix = peer.prefix,
                .peer_id = peer.peer_id,
                .session_id = null,
                .epoch = .{ .value = 1 },
                .preference = .relay,
            };
            installed_count += 1;
        }
        return installed_count;
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

test "tun runtime opens and configures tun from node config" {
    const std = @import("std");
    const core = @import("../core/core.zig");

    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{};
    var installed = [_]linux.routes.InstalledRoute{};

    var node = try api.node.Node.init(.{
        .network_id = try core.types.NetworkId.init("home-net"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'i', 'n', 'e', '1', 0 } ++ ([_]u8{0} ** 10),
            .local_address = try core.types.VineAddress.parse("10.42.0.2"),
            .prefix_len = 24,
            .mtu = 1420,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });
    node.tun.close();

    var runtime = TunRuntime.init(&node, &installed);
    try runtime.openAndConfigureTun();

    try std.testing.expectEqual(@as(i32, 1), runtime.node.tun.fd);
    try std.testing.expectEqual(@as(u16, 1420), runtime.node.tun.config.?.mtu);
    try std.testing.expectEqual(@as(u8, 'v'), runtime.node.tun.ifname[0]);
}

test "tun runtime installs local routes for configured remote prefixes" {
    const std = @import("std");
    const core = @import("../core/core.zig");

    var routes = [_]core.route_table.RouteEntry{
        undefined,
        undefined,
    };
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{};
    var installed = [_]linux.routes.InstalledRoute{
        .{ .prefix = try core.types.VinePrefix.parse("10.0.0.0/24") },
        .{ .prefix = try core.types.VinePrefix.parse("10.0.0.0/24") },
    };

    var node = try api.node.Node.init(.{
        .network_id = try core.types.NetworkId.init("home-net"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'i', 'n', 'e', '2', 0 } ++ ([_]u8{0} ** 10),
            .local_address = try core.types.VineAddress.parse("10.42.0.1"),
            .prefix_len = 24,
            .mtu = 1400,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });
    var runtime = TunRuntime.init(&node, &installed);

    const peers = [_]enrollment.EnrollmentState.EnrolledPeer{
        .{
            .peer_id = core.types.PeerId.init(.{0x11} ** core.types.peer_id_len),
            .prefix = try core.types.VinePrefix.parse("10.42.1.0/24"),
        },
        .{
            .peer_id = core.types.PeerId.init(.{0x22} ** core.types.peer_id_len),
            .prefix = try core.types.VinePrefix.parse("10.42.2.0/24"),
            .relay_capable = true,
        },
    };

    try std.testing.expectEqual(@as(usize, 2), runtime.installConfiguredRoutes(&peers));
    try std.testing.expect(runtime.installed_routes[0].active);
    try std.testing.expect(runtime.installed_routes[1].active);
    try std.testing.expect(runtime.node.route_table.entries[0].prefix.contains(try core.types.VineAddress.parse("10.42.1.7")));
    try std.testing.expect(runtime.node.route_table.entries[1].peer_id.eql(peers[1].peer_id));
}
