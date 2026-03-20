const api = @import("../api/api.zig");
const core = @import("../core/core.zig");
const linux = @import("../linux/linux.zig");
const enrollment = @import("enrollment.zig");

pub const TunRuntime = struct {
    pub const DropReason = enum {
        unknown_route,
        no_session,
        unauthorized_peer,
    };

    node: *api.node.Node,
    installed_routes: []linux.routes.InstalledRoute,
    last_sent_packet: []const u8 = &.{},
    last_session: ?core.session_table.ActiveSession = null,
    last_drop: ?DropReason = null,

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

    pub fn readPacketFromTun(self: *TunRuntime) ?[]const u8 {
        return self.node.tun.readPacket();
    }

    pub fn routePacket(self: *TunRuntime, packet: []const u8) ?core.route_table.RouteEntry {
        const forwarder = core.forwarder.Forwarder{
            .routes = &self.node.route_table,
            .sessions = &self.node.session_table,
            .tun = &self.node.tun,
            .local_peer_id = self.node.local_peer_id,
        };
        return forwarder.lookupDestination(packet);
    }

    pub fn sendPacketOverPreferredSession(self: *TunRuntime, packet: []const u8) ?core.session_table.ActiveSession {
        const session_id = self.node.sendPacket(packet) orelse return null;
        const session = self.node.session_table.bySessionId(session_id) orelse return null;
        self.last_sent_packet = packet;
        self.last_session = session;
        self.last_drop = null;
        return session;
    }

    pub fn receivePacketFromSession(self: *TunRuntime, peer_id: core.types.PeerId, packet: []const u8) bool {
        return self.node.receivePacket(peer_id, packet);
    }

    pub fn dispatchPacket(self: *TunRuntime, packet: []const u8) ?core.session_table.ActiveSession {
        if (self.routePacket(packet) == null) {
            self.last_drop = .unknown_route;
            return null;
        }
        const session = self.sendPacketOverPreferredSession(packet) orelse {
            self.last_drop = .no_session;
            return null;
        };
        return session;
    }
};

test "tun runtime captures node and route installation storage" {
    const std = @import("std");

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

test "tun runtime reads packets from tun and routes by overlay destination" {
    const std = @import("std");

    var routes = [_]core.route_table.RouteEntry{
        .{
            .prefix = try core.types.VinePrefix.parse("10.42.9.0/24"),
            .peer_id = core.types.PeerId.init(.{0x33} ** core.types.peer_id_len),
            .session_id = null,
            .epoch = .{ .value = 1 },
            .preference = .relay,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{};
    var installed = [_]linux.routes.InstalledRoute{};

    var node = try api.node.Node.init(.{
        .network_id = try core.types.NetworkId.init("home-net"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'i', 'n', 'e', '3', 0 } ++ ([_]u8{0} ** 10),
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
    const packet = [_]u8{
        0x45, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00,
        10, 42, 0, 1,
        10, 42, 9, 7,
    } ++ ([_]u8{0} ** 4);
    runtime.node.tun.loadReadBuffer(&packet);

    try std.testing.expectEqualSlices(u8, &packet, runtime.readPacketFromTun().?);
    try std.testing.expect(runtime.routePacket(&packet).?.peer_id.eql(core.types.PeerId.init(.{0x33} ** core.types.peer_id_len)));
}

test "tun runtime sends packets over the preferred session" {
    const std = @import("std");

    const peer = core.types.PeerId.init(.{0x44} ** core.types.peer_id_len);
    var routes = [_]core.route_table.RouteEntry{
        .{
            .prefix = try core.types.VinePrefix.parse("10.42.10.0/24"),
            .peer_id = peer,
            .session_id = .{ .value = 51 },
            .epoch = .{ .value = 1 },
            .preference = .direct,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer,
            .session_id = .{ .value = 51 },
            .preference = .direct,
        },
    };
    var memberships = [_]core.membership.PeerMembership{};
    var installed = [_]linux.routes.InstalledRoute{};

    var node = try api.node.Node.init(.{
        .network_id = try core.types.NetworkId.init("home-net"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'i', 'n', 'e', '4', 0 } ++ ([_]u8{0} ** 10),
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
    const packet = [_]u8{
        0x45, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00,
        10, 42, 0, 1,
        10, 42, 10, 7,
    } ++ ([_]u8{0} ** 4);

    try std.testing.expectEqual(@as(u64, 51), runtime.sendPacketOverPreferredSession(&packet).?.session_id.value);
    try std.testing.expectEqualSlices(u8, &packet, runtime.last_sent_packet);
    try std.testing.expectEqual(@as(u64, 51), runtime.last_session.?.session_id.value);
}

test "tun runtime receives packets from sessions and injects them into tun" {
    const std = @import("std");

    const peer = core.types.PeerId.init(.{0x55} ** core.types.peer_id_len);
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer,
            .session_id = .{ .value = 61 },
            .preference = .direct,
        },
    };
    var memberships = [_]core.membership.PeerMembership{};
    var installed = [_]linux.routes.InstalledRoute{};

    var node = try api.node.Node.init(.{
        .network_id = try core.types.NetworkId.init("home-net"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'i', 'n', 'e', '5', 0 } ++ ([_]u8{0} ** 10),
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
    const packet = [_]u8{
        0x45, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00,
        10, 42, 1, 7,
        10, 42, 0, 1,
    } ++ ([_]u8{0} ** 4);

    try std.testing.expect(runtime.receivePacketFromSession(peer, &packet));
    try std.testing.expectEqualSlices(u8, &packet, runtime.node.tun.tx_buffer);
}

test "tun runtime drops packets for unknown routes" {
    const std = @import("std");

    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{};
    var installed = [_]linux.routes.InstalledRoute{};

    var node = try api.node.Node.init(.{
        .network_id = try core.types.NetworkId.init("home-net"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'i', 'n', 'e', '6', 0 } ++ ([_]u8{0} ** 10),
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
    const packet = [_]u8{
        0x45, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00,
        10, 42, 0, 1,
        10, 99, 0, 7,
    } ++ ([_]u8{0} ** 4);

    try std.testing.expect(runtime.dispatchPacket(&packet) == null);
    try std.testing.expectEqual(TunRuntime.DropReason.unknown_route, runtime.last_drop.?);
}
