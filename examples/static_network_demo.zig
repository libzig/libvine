const std = @import("std");
const libvine = @import("libvine");

pub fn main() !void {
    var node_a_routes = [_]libvine.core.route_table.RouteEntry{};
    var node_a_sessions = [_]libvine.core.session_table.ActiveSession{};
    var node_a_memberships = [_]libvine.core.membership.PeerMembership{};

    var node_b_routes = [_]libvine.core.route_table.RouteEntry{};
    var node_b_sessions = [_]libvine.core.session_table.ActiveSession{};
    var node_b_memberships = [_]libvine.core.membership.PeerMembership{};

    var node_a = try libvine.api.node.Node.init(.{
        .network_id = try libvine.core.types.NetworkId.init("demo"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'a', 0 } ++ ([_]u8{0} ** 12),
            .local_address = libvine.core.types.VineAddress.init(.{ 10, 70, 0, 1 }),
            .prefix_len = 24,
        },
        .bootstrap_peers = &.{.{
            .peer_id = libvine.core.types.PeerId.init(.{0x22} ** libvine.core.types.peer_id_len),
            .address = "static://node-b",
        }},
    }, .{
        .routes = &node_a_routes,
        .sessions = &node_a_sessions,
        .memberships = &node_a_memberships,
    });

    var node_b = try libvine.api.node.Node.init(.{
        .network_id = try libvine.core.types.NetworkId.init("demo"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'b', 0 } ++ ([_]u8{0} ** 12),
            .local_address = libvine.core.types.VineAddress.init(.{ 10, 71, 0, 1 }),
            .prefix_len = 24,
        },
        .seed_records = &.{.{
            .peer_id = node_a.local_peer_id,
            .published_prefix = node_a.local_membership.?.prefix,
        }},
    }, .{
        .routes = &node_b_routes,
        .sessions = &node_b_sessions,
        .memberships = &node_b_memberships,
    });

    node_a.start();
    node_b.start();
    _ = node_a.bootstrap();
    _ = node_b.bootstrap();

    std.debug.print(
        "static-network-demo: node-a={f} node-b={f}\n",
        .{ node_a.local_peer_id, node_b.local_peer_id },
    );
}
