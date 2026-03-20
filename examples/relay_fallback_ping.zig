const std = @import("std");
const libvine = @import("libvine");

pub fn main() !void {
    const peer = libvine.core.types.PeerId.init(.{0x44} ** libvine.core.types.peer_id_len);

    var routes = [_]libvine.core.route_table.RouteEntry{
        .{
            .prefix = try libvine.core.types.VinePrefix.parse("10.90.0.0/24"),
            .peer_id = peer,
            .session_id = libvine.core.types.SessionId.init(2),
            .epoch = libvine.core.types.MembershipEpoch.init(1),
            .preference = .direct,
        },
    };
    var sessions = [_]libvine.core.session_table.ActiveSession{
        .{
            .peer_id = peer,
            .session_id = libvine.core.types.SessionId.init(2),
            .preference = .direct,
        },
        .{
            .peer_id = peer,
            .session_id = libvine.core.types.SessionId.init(3),
            .preference = .relay,
        },
    };
    var memberships = [_]libvine.core.membership.PeerMembership{};

    var node = try libvine.api.node.Node.init(.{
        .network_id = try libvine.core.types.NetworkId.init("demo"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'r', 0 } ++ ([_]u8{0} ** 12),
            .local_address = libvine.core.types.VineAddress.init(.{ 10, 89, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });
    node.start();

    const packet = [_]u8{
        0x45, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00,
        10, 89, 0, 1,
        10, 90, 0, 7,
    } ++ ([_]u8{0} ** 4);

    var forwarder = libvine.core.forwarder.Forwarder{
        .routes = &node.route_table,
        .sessions = &node.session_table,
        .tun = &node.tun,
        .local_peer_id = node.local_peer_id,
    };

    const before = forwarder.forwardOutbound(&packet).?;
    _ = forwarder.cleanupStaleSession(peer);
    const fallback = node.session_table.fallbackToRelay(peer).?;

    std.debug.print(
        "relay-fallback-ping: direct={d} relay={d}\n",
        .{ before.session_id.value, fallback.session_id.value },
    );
}
