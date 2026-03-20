const std = @import("std");
const api = @import("../api/api.zig");

pub const RuntimeConfig = struct {
    node_config: api.config.NodeConfig,
};

test "runtime config module captures a node config translation target" {
    const cfg = RuntimeConfig{
        .node_config = .{
            .network_id = try @import("../core/types.zig").NetworkId.init("devnet"),
            .tun = .{
                .ifname = [_]u8{ 'v', 'n', '0', 0 } ++ ([_]u8{0} ** 12),
                .local_address = @import("../core/types.zig").VineAddress.init(.{ 10, 42, 0, 1 }),
                .prefix_len = 24,
            },
        },
    };

    try std.testing.expectEqualStrings("devnet", cfg.node_config.network_id.encode());
}
