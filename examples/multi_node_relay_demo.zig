const std = @import("std");
const libvine = @import("libvine");

fn makeTunName(a: u8, b: u8) [16]u8 {
    return [_]u8{ 'v', 'n', a, b } ++ ([_]u8{0} ** 12);
}

fn makeNode(
    network_id: libvine.core.types.NetworkId,
    tun_name: [16]u8,
    local_address: [4]u8,
    routes: []libvine.core.route_table.RouteEntry,
    sessions: []libvine.core.session_table.ActiveSession,
    memberships: []libvine.core.membership.PeerMembership,
) !libvine.api.node.Node {
    return libvine.api.node.Node.init(.{
        .network_id = network_id,
        .tun = .{
            .ifname = tun_name,
            .local_address = libvine.core.types.VineAddress.init(local_address),
            .prefix_len = 24,
        },
    }, .{
        .routes = routes,
        .sessions = sessions,
        .memberships = memberships,
    });
}

pub fn main() !void {
    const network_id = try libvine.core.types.NetworkId.init("demo");

    const relay_peer = libvine.testing.fixtures.peerId(0x40);
    const alpha_peer = libvine.testing.fixtures.peerId(0x41);
    const beta_peer = libvine.testing.fixtures.peerId(0x42);
    const gamma_peer = libvine.testing.fixtures.peerId(0x43);

    var alpha_routes = [_]libvine.core.route_table.RouteEntry{
        .{
            .prefix = try libvine.testing.fixtures.prefix("10.121.0.0/24"),
            .peer_id = beta_peer,
            .session_id = libvine.core.types.SessionId.init(101),
            .epoch = libvine.core.types.MembershipEpoch.init(1),
            .preference = .direct,
        },
        .{
            .prefix = try libvine.testing.fixtures.prefix("10.122.0.0/24"),
            .peer_id = gamma_peer,
            .session_id = libvine.core.types.SessionId.init(103),
            .epoch = libvine.core.types.MembershipEpoch.init(1),
            .preference = .relay,
        },
    };
    var alpha_sessions = [_]libvine.core.session_table.ActiveSession{
        .{
            .peer_id = beta_peer,
            .session_id = libvine.core.types.SessionId.init(101),
            .preference = .direct,
        },
        .{
            .peer_id = beta_peer,
            .session_id = libvine.core.types.SessionId.init(102),
            .preference = .relay,
        },
        .{
            .peer_id = gamma_peer,
            .session_id = libvine.core.types.SessionId.init(103),
            .preference = .relay,
        },
        .{
            .peer_id = relay_peer,
            .session_id = libvine.core.types.SessionId.init(150),
            .preference = .direct,
        },
    };
    var alpha_memberships = [_]libvine.core.membership.PeerMembership{};

    var beta_routes = [_]libvine.core.route_table.RouteEntry{
        .{
            .prefix = try libvine.testing.fixtures.prefix("10.120.0.0/24"),
            .peer_id = alpha_peer,
            .session_id = libvine.core.types.SessionId.init(201),
            .epoch = libvine.core.types.MembershipEpoch.init(1),
            .preference = .direct,
        },
        .{
            .prefix = try libvine.testing.fixtures.prefix("10.122.0.0/24"),
            .peer_id = gamma_peer,
            .session_id = libvine.core.types.SessionId.init(202),
            .epoch = libvine.core.types.MembershipEpoch.init(1),
            .preference = .direct_after_signaling,
        },
    };
    var beta_sessions = [_]libvine.core.session_table.ActiveSession{
        .{
            .peer_id = alpha_peer,
            .session_id = libvine.core.types.SessionId.init(201),
            .preference = .direct,
        },
        .{
            .peer_id = gamma_peer,
            .session_id = libvine.core.types.SessionId.init(202),
            .preference = .direct_after_signaling,
        },
        .{
            .peer_id = relay_peer,
            .session_id = libvine.core.types.SessionId.init(250),
            .preference = .direct,
        },
    };
    var beta_memberships = [_]libvine.core.membership.PeerMembership{};

    var gamma_routes = [_]libvine.core.route_table.RouteEntry{
        .{
            .prefix = try libvine.testing.fixtures.prefix("10.120.0.0/24"),
            .peer_id = alpha_peer,
            .session_id = libvine.core.types.SessionId.init(301),
            .epoch = libvine.core.types.MembershipEpoch.init(1),
            .preference = .relay,
        },
        .{
            .prefix = try libvine.testing.fixtures.prefix("10.121.0.0/24"),
            .peer_id = beta_peer,
            .session_id = libvine.core.types.SessionId.init(302),
            .epoch = libvine.core.types.MembershipEpoch.init(1),
            .preference = .direct_after_signaling,
        },
    };
    var gamma_sessions = [_]libvine.core.session_table.ActiveSession{
        .{
            .peer_id = alpha_peer,
            .session_id = libvine.core.types.SessionId.init(301),
            .preference = .relay,
        },
        .{
            .peer_id = beta_peer,
            .session_id = libvine.core.types.SessionId.init(302),
            .preference = .direct_after_signaling,
        },
        .{
            .peer_id = relay_peer,
            .session_id = libvine.core.types.SessionId.init(350),
            .preference = .direct,
        },
    };
    var gamma_memberships = [_]libvine.core.membership.PeerMembership{};

    var relay_routes = [_]libvine.core.route_table.RouteEntry{};
    var relay_sessions = [_]libvine.core.session_table.ActiveSession{
        .{
            .peer_id = alpha_peer,
            .session_id = libvine.core.types.SessionId.init(401),
            .preference = .direct,
        },
        .{
            .peer_id = beta_peer,
            .session_id = libvine.core.types.SessionId.init(402),
            .preference = .direct,
        },
        .{
            .peer_id = gamma_peer,
            .session_id = libvine.core.types.SessionId.init(403),
            .preference = .direct,
        },
    };
    var relay_memberships = [_]libvine.core.membership.PeerMembership{};

    var alpha = try makeNode(network_id, makeTunName('a', '0'), .{ 10, 120, 0, 1 }, &alpha_routes, &alpha_sessions, &alpha_memberships);
    var beta = try makeNode(network_id, makeTunName('b', '0'), .{ 10, 121, 0, 1 }, &beta_routes, &beta_sessions, &beta_memberships);
    var gamma = try makeNode(network_id, makeTunName('g', '0'), .{ 10, 122, 0, 1 }, &gamma_routes, &gamma_sessions, &gamma_memberships);
    var relay = try makeNode(network_id, makeTunName('r', '0'), .{ 10, 123, 0, 1 }, &relay_routes, &relay_sessions, &relay_memberships);

    alpha.start();
    beta.start();
    gamma.start();
    relay.start();

    const alpha_to_beta = libvine.testing.fixtures.packet(.{ 10, 120, 0, 1 }, .{ 10, 121, 0, 42 });
    const gamma_to_alpha = libvine.testing.fixtures.packet(.{ 10, 122, 0, 1 }, .{ 10, 120, 0, 9 });

    const direct_session = alpha.sendPacket(&alpha_to_beta).?;
    try std.testing.expectEqual(@as(u64, 101), direct_session.value);

    const direct_beta = gamma.sendPacket(&libvine.testing.fixtures.packet(.{ 10, 122, 0, 1 }, .{ 10, 121, 0, 7 })).?;
    try std.testing.expectEqual(@as(u64, 302), direct_beta.value);

    const relay_session = gamma.sendPacket(&gamma_to_alpha).?;
    try std.testing.expectEqual(@as(u64, 301), relay_session.value);

    try std.testing.expect(alpha.cleanupStaleSession(beta_peer));
    alpha_sessions[0] = .{
        .peer_id = beta_peer,
        .session_id = libvine.core.types.SessionId.init(102),
        .preference = .relay,
    };
    const fallback_session = alpha.sendPacket(&alpha_to_beta).?;

    std.debug.print(
        \\multi-node-relay-demo
        \\  alpha -> beta direct session: {d}
        \\  gamma -> beta signaling-assisted session: {d}
        \\  gamma -> alpha relay session: {d}
        \\  alpha -> beta fallback relay session after loss: {d}
        \\  relay node peer fanout: {d}
        \\
    , .{
        direct_session.value,
        direct_beta.value,
        relay_session.value,
        fallback_session.value,
        relay.session_table.sessions.len,
    });
}
