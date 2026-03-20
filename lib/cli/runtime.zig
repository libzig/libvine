const std = @import("std");
const api = @import("../api/api.zig");
const core = @import("../core/core.zig");
const daemon = @import("../daemon/runtime.zig");
const integration = @import("../integration/integration.zig");
const runtime = @import("../runtime/runtime.zig");

const DiagnosticsSnapshot = struct {
    daemon_phase: daemon.DaemonPhase,
    daemon_pid: ?std.process.Child.Id,
    network_id: core.types.NetworkId,
    local_peer_id: core.types.PeerId,
    local_prefix: core.types.VinePrefix,
    peer_count: usize,
    bootstrap_count: usize,
};

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

pub fn runDown(args: []const []const u8, pidfile_path: []const u8) !void {
    if (args.len != 0) return error.InvalidArguments;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const pid = daemon.readPidFile(allocator, pidfile_path) catch {
        std.debug.print("vine down\nphase=stopped\n", .{});
        return;
    };

    daemon.requestShutdown(pid) catch |err| switch (err) {
        error.ProcessNotFound => {},
        else => return err,
    };
    std.fs.deleteFileAbsolute(pidfile_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    std.debug.print("vine down\npid={d}\n", .{pid});
}

pub fn runStatus(args: []const []const u8, default_config_path: []const u8, state_path: []const u8) !void {
    const config_path = try parseConfigPath(args, default_config_path);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const snapshot = try buildDiagnosticsSnapshot(allocator, config_path, state_path);
    try printStatus(snapshot);
}

pub fn runSessions(args: []const []const u8, default_config_path: []const u8) !void {
    const config_path = try parseConfigPath(args, default_config_path);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime_cfg = try runtime.runtime_config.load(allocator, config_path);
    defer runtime_cfg.deinit(allocator);

    const managed_peers = try allocator.alloc(runtime.session_manager.ManagedPeer, runtime_cfg.enrolled_peers.len);
    defer allocator.free(managed_peers);
    for (runtime_cfg.enrolled_peers, 0..) |peer, i| {
        managed_peers[i] = .{
            .peer_id = peer.peer_id,
            .relay_capable = peer.relay_capable,
        };
    }

    const session_capacity = @max(runtime_cfg.enrolled_peers.len, 1);
    const session_buffer = try allocator.alloc(core.session_table.ActiveSession, session_capacity);
    defer allocator.free(session_buffer);
    for (session_buffer) |*session| {
        session.* = .{
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .session_id = .{ .value = 0 },
            .preference = .relay,
        };
    }

    const candidates = try allocator.alloc(integration.libmesh_adapter.CandidatePeer, runtime_cfg.enrolled_peers.len);
    defer allocator.free(candidates);
    const plans = try allocator.alloc(integration.libmesh_adapter.ReachabilityPlan, runtime_cfg.enrolled_peers.len);
    defer allocator.free(plans);
    for (runtime_cfg.enrolled_peers, 0..) |peer, i| {
        const candidate = integration.libmesh_adapter.CandidatePeer{
            .peer_id = peer.peer_id,
            .node_id = @import("libmesh").Foundation.NodeId.fromPublicKey(peer.peer_id.bytes),
        };
        candidates[i] = candidate;
        plans[i] = if (peer.relay_capable and runtime_cfg.node_config.policy.allow_relay)
            .{ .relay = candidate }
        else if (runtime_cfg.node_config.policy.allow_signaling_upgrade)
            .{ .signaling_then_direct = candidate }
        else
            .{ .direct = candidate };
    }

    var manager = runtime.session_manager.SessionManager.withMesh(
        managed_peers,
        session_buffer,
        integration.libmesh_adapter.LibmeshAdapter.withReachability(candidates, plans),
    );
    _ = manager.connectConfiguredPeers();

    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    try renderSessions(output.writer(allocator), managed_peers, manager);
    std.debug.print("{s}", .{output.items});
}

fn renderSessions(
    writer: anytype,
    peers: []const runtime.session_manager.ManagedPeer,
    manager: runtime.session_manager.SessionManager,
) !void {
    try writer.print(
        "vine sessions\ncount={d}\ndirect={d}\nsignaling={d}\nrelay={d}\n",
        .{
            peers.len,
            manager.directSessionCount(),
            manager.signalingSessionCount(),
            manager.relaySessionCount(),
        },
    );
    for (peers) |peer| {
        const session = manager.preferredSessionForPeer(peer.peer_id) orelse continue;
        try writer.print(
            "peer={f}\nmode={s}\nsession_id={d}\nrelay_capable={any}\n",
            .{ peer.peer_id, preferenceLabel(session.preference), session.session_id.value, peer.relay_capable },
        );
    }
}

fn buildDiagnosticsSnapshot(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    state_path: []const u8,
) !DiagnosticsSnapshot {
    var runtime_cfg = try runtime.runtime_config.load(allocator, config_path);
    defer runtime_cfg.deinit(allocator);

    const daemon_snapshot = daemon.readStateFile(allocator, state_path) catch daemon.Snapshot{
        .phase = .stopped,
        .config_path = null,
        .pid = null,
    };
    defer if (daemon_snapshot.config_path != null) {
        var mutable = daemon_snapshot;
        daemon.deinitSnapshot(allocator, &mutable);
    };

    return .{
        .daemon_phase = daemon_snapshot.phase,
        .daemon_pid = daemon_snapshot.pid,
        .network_id = runtime_cfg.node_config.network_id,
        .local_peer_id = runtime_cfg.local_membership.peer_id,
        .local_prefix = runtime_cfg.local_membership.prefix,
        .peer_count = runtime_cfg.enrolled_peers.len,
        .bootstrap_count = runtime_cfg.startup_bootstrap_peers.len,
    };
}

fn printStatus(snapshot: DiagnosticsSnapshot) !void {
    var prefix_buffer: [32]u8 = undefined;
    const prefix_text = try std.fmt.bufPrint(
        &prefix_buffer,
        "{f}/{d}",
        .{ snapshot.local_prefix.network, snapshot.local_prefix.prefix_len },
    );
    std.debug.print(
        "vine status\nphase={s}\npid={?d}\nnetwork_id={s}\npeer_id={f}\nprefix={s}\npeers={d}\nbootstrap_peers={d}\n",
        .{
            @tagName(snapshot.daemon_phase),
            snapshot.daemon_pid,
            snapshot.network_id.encode(),
            snapshot.local_peer_id,
            prefix_text,
            snapshot.peer_count,
            snapshot.bootstrap_count,
        },
    );
}

fn preferenceLabel(preference: core.route_table.RouteEntry.Preference) []const u8 {
    return switch (preference) {
        .direct => "direct",
        .direct_after_signaling => "signaling_then_direct",
        .relay => "relay",
    };
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

test "runtime cli down rejects unexpected arguments" {
    try std.testing.expectError(error.InvalidArguments, runDown(&.{ "--now" }, "/run/libvine/vine.pid"));
}

test "runtime cli renders session state through vine sessions" {
    const peers = [_]runtime.session_manager.ManagedPeer{
        .{
            .peer_id = core.types.PeerId.init(.{0x82} ** core.types.peer_id_len),
            .relay_capable = false,
        },
        .{
            .peer_id = core.types.PeerId.init(.{0x83} ** core.types.peer_id_len),
            .relay_capable = true,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peers[0].peer_id,
            .session_id = .{ .value = 41 },
            .preference = .direct_after_signaling,
        },
        .{
            .peer_id = peers[1].peer_id,
            .session_id = .{ .value = 42 },
            .preference = .relay,
        },
    };
    const manager = runtime.session_manager.SessionManager.init(&peers, &sessions);

    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(std.testing.allocator);
    try renderSessions(buffer.writer(std.testing.allocator), &peers, manager);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "vine sessions") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "signaling=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "relay=1") != null);
}

test "runtime cli builds status diagnostics snapshot" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity", .{root});
    defer std.testing.allocator.free(identity_path);
    const stored = try @import("../config/identity_store.zig").generateAndWrite(identity_path);

    const config_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/vine.toml", .{root});
    defer std.testing.allocator.free(config_path);
    const state_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/state.txt", .{root});
    defer std.testing.allocator.free(state_path);
    try tmp.dir.writeFile(.{
        .sub_path = "state.txt",
        .data = "phase=running\npid=4242\nconfig_path=/etc/libvine/vine.toml\n",
    });

    const config_body = try std.fmt.allocPrint(
        std.testing.allocator,
        \\[node]
        \\name = "alpha"
        \\network_id = "home-net"
        \\identity_path = "{s}"
        \\
        \\[tun]
        \\name = "vine0"
        \\address = "10.42.0.1"
        \\prefix_len = 24
        \\mtu = 1400
        \\
        \\[[bootstrap_peers]]
        \\peer_id = "{f}"
        \\address = "udp://198.51.100.10:4100"
        \\
        \\[[allowed_peers]]
        \\peer_id = "{f}"
        \\prefix = "10.42.1.0/24"
        \\relay_capable = true
        \\
        \\[policy]
        \\strict_allowlist = true
        \\allow_relay = true
        \\allow_signaling_upgrade = true
    , .{ identity_path, stored.bound.peer_id, stored.bound.peer_id });
    defer std.testing.allocator.free(config_body);
    try tmp.dir.writeFile(.{ .sub_path = "vine.toml", .data = config_body });

    const snapshot = try buildDiagnosticsSnapshot(std.testing.allocator, config_path, state_path);
    try std.testing.expectEqual(daemon.DaemonPhase.running, snapshot.daemon_phase);
    try std.testing.expectEqual(@as(?std.process.Child.Id, 4242), snapshot.daemon_pid);
    try std.testing.expect(snapshot.local_peer_id.eql(stored.bound.peer_id));
    try std.testing.expectEqual(@as(usize, 1), snapshot.peer_count);
    try std.testing.expectEqual(@as(usize, 1), snapshot.bootstrap_count);
}
