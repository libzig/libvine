const config = @import("config.zig");
const core = @import("../core/core.zig");
const integration = @import("../integration/integration.zig");
const linux = @import("../linux/linux.zig");

pub const Node = struct {
    config: config.NodeConfig,
    local_membership: ?core.membership.LocalMembership = null,
    route_table: core.route_table.RouteTable,
    session_table: core.session_table.SessionTable,
    mesh: integration.libmesh_adapter.LibmeshAdapter = integration.libmesh_adapter.LibmeshAdapter.init(),
    tun: linux.tun.TunDevice,
};

test "node runtime api exposes core runtime state" {
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};

    const node = Node{
        .config = .{
            .network_id = try core.types.NetworkId.init("devnet"),
            .tun = .{
                .ifname = [_]u8{ 'v', 'n', '0', 0 } ++ ([_]u8{0} ** 12),
                .local_address = core.types.VineAddress.init(.{ 10, 60, 0, 1 }),
                .prefix_len = 24,
            },
        },
        .route_table = core.route_table.RouteTable.init(&routes),
        .session_table = core.session_table.SessionTable.init(&sessions),
        .tun = .{ .fd = 1 },
    };

    try @import("std").testing.expectEqual(@as(usize, 0), node.route_table.entries.len);
    try @import("std").testing.expectEqual(@as(i32, 1), node.tun.fd);
}
