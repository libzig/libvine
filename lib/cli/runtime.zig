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

const PeerDiagnostics = struct {
    peer_id: core.types.PeerId,
    prefix: core.types.VinePrefix,
    relay_capable: bool,
};

const RouteDiagnostics = struct {
    prefix: core.types.VinePrefix,
    peer_id: core.types.PeerId,
    preference: core.route_table.RouteEntry.Preference,
};

const SessionDiagnostics = struct {
    peer_id: core.types.PeerId,
    session_id: core.types.SessionId,
    mode: core.route_table.RouteEntry.Preference,
    relay_capable: bool,
};

const CounterDiagnostics = struct {
    packets_sent: usize,
    packets_received: usize,
    route_misses: usize,
    session_failures: usize,
    fallback_transitions: usize,
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

pub fn runPeers(args: []const []const u8, default_config_path: []const u8) !void {
    const config_path = try parseConfigPath(args, default_config_path);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime_cfg = try runtime.runtime_config.load(allocator, config_path);
    defer runtime_cfg.deinit(allocator);

    const peers = try buildPeerDiagnostics(allocator, runtime_cfg.enrolled_peers);
    defer allocator.free(peers);
    try printPeers(peers);
}

pub fn runRoutes(args: []const []const u8, default_config_path: []const u8) !void {
    const config_path = try parseConfigPath(args, default_config_path);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime_cfg = try runtime.runtime_config.load(allocator, config_path);
    defer runtime_cfg.deinit(allocator);

    const routes = try buildRouteDiagnostics(allocator, runtime_cfg.enrolled_peers);
    defer allocator.free(routes);
    try printRoutes(routes);
}

pub fn runCounters(args: []const []const u8, default_config_path: []const u8) !void {
    const config_path = try parseConfigPath(args, default_config_path);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const counters = try buildCounterDiagnostics(allocator, config_path);
    try printCounters(counters);
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

    const sessions_view = try buildSessionDiagnostics(allocator, managed_peers, manager);
    defer allocator.free(sessions_view);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    try renderSessions(output.writer(allocator), sessions_view);
    std.debug.print("{s}", .{output.items});
}

fn renderSessions(
    writer: anytype,
    sessions: []const SessionDiagnostics,
) !void {
    try writer.print(
        "vine sessions\ncount={d}\ndirect={d}\nsignaling={d}\nrelay={d}\n",
        .{
            sessions.len,
            countSessionsByPreference(sessions, .direct),
            countSessionsByPreference(sessions, .direct_after_signaling),
            countSessionsByPreference(sessions, .relay),
        },
    );
    for (sessions) |session| {
        try writer.print(
            "peer={f}\nmode={s}\nsession_id={d}\nrelay_capable={any}\n",
            .{ session.peer_id, preferenceLabel(session.mode), session.session_id.value, session.relay_capable },
        );
    }
}

fn buildSessionDiagnostics(
    allocator: std.mem.Allocator,
    peers: []const runtime.session_manager.ManagedPeer,
    manager: runtime.session_manager.SessionManager,
) ![]SessionDiagnostics {
    var sessions = try std.ArrayList(SessionDiagnostics).initCapacity(allocator, peers.len);
    defer sessions.deinit(allocator);
    for (peers) |peer| {
        const preferred = manager.preferredSessionForPeer(peer.peer_id) orelse continue;
        try sessions.append(allocator, .{
            .peer_id = peer.peer_id,
            .session_id = preferred.session_id,
            .mode = preferred.preference,
            .relay_capable = peer.relay_capable,
        });
    }
    return sessions.toOwnedSlice(allocator);
}

fn countSessionsByPreference(
    sessions: []const SessionDiagnostics,
    preference: core.route_table.RouteEntry.Preference,
) usize {
    var count: usize = 0;
    for (sessions) |session| {
        if (session.mode == preference) count += 1;
    }
    return count;
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

fn buildPeerDiagnostics(
    allocator: std.mem.Allocator,
    enrolled_peers: []const runtime.enrollment.EnrollmentState.EnrolledPeer,
) ![]PeerDiagnostics {
    const peers = try allocator.alloc(PeerDiagnostics, enrolled_peers.len);
    for (enrolled_peers, 0..) |peer, i| {
        peers[i] = .{
            .peer_id = peer.peer_id,
            .prefix = peer.prefix,
            .relay_capable = peer.relay_capable,
        };
    }
    return peers;
}

fn printPeers(peers: []const PeerDiagnostics) !void {
    std.debug.print("vine peers\ncount={d}\n", .{peers.len});
    for (peers) |peer| {
        var prefix_buffer: [32]u8 = undefined;
        const prefix_text = try std.fmt.bufPrint(
            &prefix_buffer,
            "{f}/{d}",
            .{ peer.prefix.network, peer.prefix.prefix_len },
        );
        std.debug.print(
            "peer={f}\nprefix={s}\nrelay_capable={any}\n",
            .{ peer.peer_id, prefix_text, peer.relay_capable },
        );
    }
}

fn buildRouteDiagnostics(
    allocator: std.mem.Allocator,
    enrolled_peers: []const runtime.enrollment.EnrollmentState.EnrolledPeer,
) ![]RouteDiagnostics {
    const routes = try allocator.alloc(RouteDiagnostics, enrolled_peers.len);
    for (enrolled_peers, 0..) |peer, i| {
        routes[i] = .{
            .prefix = peer.prefix,
            .peer_id = peer.peer_id,
            .preference = if (peer.relay_capable) .relay else .direct_after_signaling,
        };
    }
    return routes;
}

fn printRoutes(routes: []const RouteDiagnostics) !void {
    std.debug.print("vine routes\ncount={d}\n", .{routes.len});
    for (routes) |route| {
        var prefix_buffer: [32]u8 = undefined;
        const prefix_text = try std.fmt.bufPrint(
            &prefix_buffer,
            "{f}/{d}",
            .{ route.prefix.network, route.prefix.prefix_len },
        );
        std.debug.print(
            "prefix={s}\npeer={f}\npreference={s}\n",
            .{ prefix_text, route.peer_id, preferenceLabel(route.preference) },
        );
    }
}

fn buildCounterDiagnostics(
    allocator: std.mem.Allocator,
    config_path: []const u8,
) !CounterDiagnostics {
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

    const snapshot = node.debugSnapshot();
    return .{
        .packets_sent = snapshot.diagnostics.packets_sent,
        .packets_received = snapshot.diagnostics.packets_received,
        .route_misses = snapshot.diagnostics.route_misses,
        .session_failures = snapshot.diagnostics.session_failures,
        .fallback_transitions = snapshot.diagnostics.fallback_transitions,
    };
}

fn printCounters(counters: CounterDiagnostics) !void {
    std.debug.print(
        "vine counters\npackets_sent={d}\npackets_received={d}\nroute_misses={d}\nsession_failures={d}\nfallback_transitions={d}\n",
        .{
            counters.packets_sent,
            counters.packets_received,
            counters.route_misses,
            counters.session_failures,
            counters.fallback_transitions,
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
    const session_view = try buildSessionDiagnostics(std.testing.allocator, &peers, manager);
    defer std.testing.allocator.free(session_view);

    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(std.testing.allocator);
    try renderSessions(buffer.writer(std.testing.allocator), session_view);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "vine sessions") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "signaling=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "relay=1") != null);
}

test "runtime cli builds session diagnostics from preferred session state" {
    const peers = [_]runtime.session_manager.ManagedPeer{
        .{ .peer_id = core.types.PeerId.init(.{0x95} ** core.types.peer_id_len) },
        .{ .peer_id = core.types.PeerId.init(.{0x96} ** core.types.peer_id_len), .relay_capable = true },
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{ .peer_id = peers[0].peer_id, .session_id = .{ .value = 52 }, .preference = .direct },
        .{ .peer_id = peers[1].peer_id, .session_id = .{ .value = 53 }, .preference = .relay },
    };
    const manager = runtime.session_manager.SessionManager.init(&peers, &sessions);
    const diagnostics = try buildSessionDiagnostics(std.testing.allocator, &peers, manager);
    defer std.testing.allocator.free(diagnostics);

    try std.testing.expectEqual(@as(usize, 2), diagnostics.len);
    try std.testing.expectEqual(@as(u64, 52), diagnostics[0].session_id.value);
    try std.testing.expect(diagnostics[1].relay_capable);
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

test "runtime cli builds peer diagnostics from enrolled peers" {
    const enrolled = [_]runtime.enrollment.EnrollmentState.EnrolledPeer{
        .{
            .peer_id = core.types.PeerId.init(.{0x91} ** core.types.peer_id_len),
            .prefix = try core.types.VinePrefix.parse("10.42.1.0/24"),
        },
        .{
            .peer_id = core.types.PeerId.init(.{0x92} ** core.types.peer_id_len),
            .prefix = try core.types.VinePrefix.parse("10.42.2.0/24"),
            .relay_capable = true,
        },
    };
    const peers = try buildPeerDiagnostics(std.testing.allocator, &enrolled);
    defer std.testing.allocator.free(peers);

    try std.testing.expectEqual(@as(usize, 2), peers.len);
    try std.testing.expect(peers[0].prefix.contains(try core.types.VineAddress.parse("10.42.1.9")));
    try std.testing.expect(peers[1].relay_capable);
}

test "runtime cli builds route diagnostics from enrolled peers" {
    const enrolled = [_]runtime.enrollment.EnrollmentState.EnrolledPeer{
        .{
            .peer_id = core.types.PeerId.init(.{0x93} ** core.types.peer_id_len),
            .prefix = try core.types.VinePrefix.parse("10.42.3.0/24"),
        },
        .{
            .peer_id = core.types.PeerId.init(.{0x94} ** core.types.peer_id_len),
            .prefix = try core.types.VinePrefix.parse("10.42.4.0/24"),
            .relay_capable = true,
        },
    };
    const routes = try buildRouteDiagnostics(std.testing.allocator, &enrolled);
    defer std.testing.allocator.free(routes);

    try std.testing.expectEqual(@as(usize, 2), routes.len);
    try std.testing.expectEqual(core.route_table.RouteEntry.Preference.direct_after_signaling, routes[0].preference);
    try std.testing.expectEqual(core.route_table.RouteEntry.Preference.relay, routes[1].preference);
}

test "runtime cli exposes node diagnostics counters" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity", .{root});
    defer std.testing.allocator.free(identity_path);
    _ = try @import("../config/identity_store.zig").generateAndWrite(identity_path);

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
    , .{identity_path});
    defer std.testing.allocator.free(config_body);
    try tmp.dir.writeFile(.{ .sub_path = "vine.toml", .data = config_body });

    const config_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/vine.toml", .{root});
    defer std.testing.allocator.free(config_path);

    const counters = try buildCounterDiagnostics(std.testing.allocator, config_path);
    try std.testing.expectEqual(@as(usize, 0), counters.packets_sent);
    try std.testing.expectEqual(@as(usize, 0), counters.fallback_transitions);
}
