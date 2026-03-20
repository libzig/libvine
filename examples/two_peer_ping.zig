const std = @import("std");
const libvine = @import("libvine");

pub fn main() !void {
    const peer_b = libvine.core.types.PeerId.init(.{0x33} ** libvine.core.types.peer_id_len);

    var routes = [_]libvine.core.route_table.RouteEntry{
        .{
            .prefix = try libvine.core.types.VinePrefix.parse("10.80.0.0/24"),
            .peer_id = peer_b,
            .session_id = libvine.core.types.SessionId.init(1),
            .epoch = libvine.core.types.MembershipEpoch.init(1),
            .preference = .direct,
        },
    };
    var sessions = [_]libvine.core.session_table.ActiveSession{
        .{
            .peer_id = peer_b,
            .session_id = libvine.core.types.SessionId.init(1),
            .preference = .direct,
        },
    };
    var memberships = [_]libvine.core.membership.PeerMembership{};

    var node = try libvine.api.node.Node.init(.{
        .network_id = try libvine.core.types.NetworkId.init("demo"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'p', 0 } ++ ([_]u8{0} ** 12),
            .local_address = libvine.core.types.VineAddress.init(.{ 10, 79, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });
    node.start();

    const ping_packet = [_]u8{
        0x45, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00,
        10, 79, 0, 1,
        10, 80, 0, 42,
    } ++ ([_]u8{0} ** 4);

    const forwarder = libvine.core.forwarder.Forwarder{
        .routes = &node.route_table,
        .sessions = &node.session_table,
        .tun = &node.tun,
        .local_peer_id = node.local_peer_id,
    };

    const session = forwarder.forwardOutbound(&ping_packet).?;
    const delivered = forwarder.forwardInbound(peer_b, &ping_packet);

    std.debug.print(
        "two-peer-ping: session={d} delivered={any}\n",
        .{ session.session_id.value, delivered },
    );
}
