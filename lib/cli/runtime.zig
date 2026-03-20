const std = @import("std");
const api = @import("../api/api.zig");
const core = @import("../core/core.zig");
const runtime = @import("../runtime/runtime.zig");

pub fn runUp(args: []const []const u8, default_config_path: []const u8) !void {
    const config_path = try parseConfigPath(args, default_config_path);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime_cfg = try runtime.runtime_config.load(allocator, config_path);
    defer runtime_cfg.deinit(allocator);

    const routes = try allocator.alloc(core.route_table.RouteEntry, core.types.max_route_table_entries);
    defer allocator.free(routes);
    const sessions = try allocator.alloc(core.session_table.ActiveSession, 32);
    defer allocator.free(sessions);
    const memberships = try allocator.alloc(core.membership.PeerMembership, core.types.max_prefix_count);
    defer allocator.free(memberships);

    var node = try api.node.Node.init(runtime_cfg.node_config, .{
        .routes = routes,
        .sessions = sessions,
        .memberships = memberships,
    });
    node.start();
    defer node.stop();

    var prefix_buffer: [32]u8 = undefined;
    const prefix_text = try std.fmt.bufPrint(
        &prefix_buffer,
        "{f}/{d}",
        .{ runtime_cfg.local_membership.prefix.network, runtime_cfg.local_membership.prefix.prefix_len },
    );

    std.debug.print(
        "vine up\npeer_id={f}\nprefix={s}\n",
        .{ node.local_peer_id, prefix_text },
    );
}

fn parseConfigPath(args: []const []const u8, default_config_path: []const u8) ![]const u8 {
    var config_path = default_config_path;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-c") or std.mem.eql(u8, args[i], "--config")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            config_path = args[i];
            continue;
        }
        return error.InvalidArguments;
    }
    return config_path;
}

test "runtime cli up config path defaults and overrides" {
    try std.testing.expectEqualStrings(
        "/etc/libvine/vine.toml",
        try parseConfigPath(&.{}, "/etc/libvine/vine.toml"),
    );
    try std.testing.expectEqualStrings(
        "/tmp/vine.toml",
        try parseConfigPath(&.{ "-c", "/tmp/vine.toml" }, "/etc/libvine/vine.toml"),
    );
}
