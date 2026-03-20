const std = @import("std");
const types = @import("../core/types.zig");

pub const ParseError = error{
    InvalidConfig,
};

pub const FileConfig = struct {
    pub const NodeSection = struct {
        name: []const u8 = "",
        network_id: []const u8 = "",
        identity_path: []const u8 = "",
    };

    pub const TunSection = struct {
        name: []const u8 = "",
        address: []const u8 = "",
        prefix_len: u8 = 0,
        mtu: u16 = 1400,
    };

    pub const BootstrapPeer = struct {
        peer_id: []const u8 = "",
        address: []const u8 = "",
    };

    pub const AllowedPeer = struct {
        peer_id: []const u8 = "",
        prefix: []const u8 = "",
        relay_capable: bool = false,
    };

    pub const PolicySection = struct {
        strict_allowlist: bool = true,
        allow_relay: bool = true,
        allow_signaling_upgrade: bool = true,
    };

    raw: []const u8,
    node: NodeSection = .{},
    tun: TunSection = .{},
    bootstrap_peers: []const BootstrapPeer = &.{},
    allowed_peers: []const AllowedPeer = &.{},
    policy: PolicySection = .{},

    pub fn deinit(self: *FileConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.bootstrap_peers);
        allocator.free(self.allowed_peers);
        self.* = init(self.raw);
    }
};

pub fn init(raw: []const u8) FileConfig {
    return .{ .raw = raw };
}

const Section = enum {
    root,
    node,
    tun,
    bootstrap_peers,
    allowed_peers,
};

pub fn parse(allocator: std.mem.Allocator, raw: []const u8) (ParseError || std.mem.Allocator.Error)!FileConfig {
    var cfg = init(raw);
    var section: Section = .root;
    var bootstrap_peers = try std.ArrayList(FileConfig.BootstrapPeer).initCapacity(allocator, 0);
    errdefer bootstrap_peers.deinit(allocator);
    var allowed_peers = try std.ArrayList(FileConfig.AllowedPeer).initCapacity(allocator, 0);
    errdefer allowed_peers.deinit(allocator);

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        const trimmed = trimLine(line);
        if (trimmed.len == 0) continue;

        if (isSectionHeader(trimmed)) {
            section = parseSection(trimmed) orelse return ParseError.InvalidConfig;
            switch (section) {
                .bootstrap_peers => try bootstrap_peers.append(allocator, .{}),
                .allowed_peers => try allowed_peers.append(allocator, .{}),
                else => {},
            }
            continue;
        }

        const key, const value = parseAssignment(trimmed) orelse return ParseError.InvalidConfig;
        switch (section) {
            .node => try applyNodeField(&cfg.node, key, value),
            .tun => try applyTunField(&cfg.tun, key, value),
            .bootstrap_peers => {
                if (bootstrap_peers.items.len == 0) return ParseError.InvalidConfig;
                try applyBootstrapPeerField(&bootstrap_peers.items[bootstrap_peers.items.len - 1], key, value);
            },
            .allowed_peers => {
                if (allowed_peers.items.len == 0) return ParseError.InvalidConfig;
                try applyAllowedPeerField(&allowed_peers.items[allowed_peers.items.len - 1], key, value);
            },
            .root => return ParseError.InvalidConfig,
        }
    }

    cfg.bootstrap_peers = try bootstrap_peers.toOwnedSlice(allocator);
    cfg.allowed_peers = try allowed_peers.toOwnedSlice(allocator);
    return cfg;
}

fn trimLine(line: []const u8) []const u8 {
    var parts = std.mem.splitScalar(u8, line, '#');
    const without_comment = parts.first();
    return std.mem.trim(u8, without_comment, " \t\r");
}

fn isSectionHeader(line: []const u8) bool {
    return line.len >= 3 and line[0] == '[' and line[line.len - 1] == ']';
}

fn parseSection(line: []const u8) ?Section {
    if (std.mem.eql(u8, line, "[node]")) return .node;
    if (std.mem.eql(u8, line, "[tun]")) return .tun;
    if (std.mem.eql(u8, line, "[[bootstrap_peers]]")) return .bootstrap_peers;
    if (std.mem.eql(u8, line, "[[allowed_peers]]")) return .allowed_peers;
    return null;
}

fn parseAssignment(line: []const u8) ?struct { []const u8, []const u8 } {
    var parts = std.mem.splitScalar(u8, line, '=');
    const key = std.mem.trim(u8, parts.next() orelse return null, " \t");
    const value = std.mem.trim(u8, parts.next() orelse return null, " \t");
    if (key.len == 0 or value.len == 0 or parts.next() != null) return null;
    return .{ key, value };
}

fn applyNodeField(node: *FileConfig.NodeSection, key: []const u8, value: []const u8) ParseError!void {
    const text = parseString(value) orelse return ParseError.InvalidConfig;

    if (std.mem.eql(u8, key, "name")) {
        node.name = text;
        return;
    }
    if (std.mem.eql(u8, key, "network_id")) {
        node.network_id = text;
        return;
    }
    if (std.mem.eql(u8, key, "identity_path")) {
        node.identity_path = text;
        return;
    }

    return ParseError.InvalidConfig;
}

fn applyTunField(tun: *FileConfig.TunSection, key: []const u8, value: []const u8) ParseError!void {
    if (std.mem.eql(u8, key, "name")) {
        tun.name = parseString(value) orelse return ParseError.InvalidConfig;
        return;
    }
    if (std.mem.eql(u8, key, "address")) {
        tun.address = parseString(value) orelse return ParseError.InvalidConfig;
        return;
    }
    if (std.mem.eql(u8, key, "prefix_len")) {
        tun.prefix_len = std.fmt.parseInt(u8, value, 10) catch return ParseError.InvalidConfig;
        return;
    }
    if (std.mem.eql(u8, key, "mtu")) {
        tun.mtu = std.fmt.parseInt(u16, value, 10) catch return ParseError.InvalidConfig;
        return;
    }

    return ParseError.InvalidConfig;
}

fn applyBootstrapPeerField(peer: *FileConfig.BootstrapPeer, key: []const u8, value: []const u8) ParseError!void {
    const text = parseString(value) orelse return ParseError.InvalidConfig;

    if (std.mem.eql(u8, key, "peer_id")) {
        peer.peer_id = text;
        return;
    }
    if (std.mem.eql(u8, key, "address")) {
        peer.address = text;
        return;
    }

    return ParseError.InvalidConfig;
}

fn applyAllowedPeerField(peer: *FileConfig.AllowedPeer, key: []const u8, value: []const u8) ParseError!void {
    const text = parseString(value) orelse return ParseError.InvalidConfig;

    if (std.mem.eql(u8, key, "peer_id")) {
        peer.peer_id = text;
        return;
    }
    if (std.mem.eql(u8, key, "prefix")) {
        peer.prefix = text;
        return;
    }

    return ParseError.InvalidConfig;
}

fn parseString(value: []const u8) ?[]const u8 {
    if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') return null;
    return value[1 .. value.len - 1];
}

test "file config module exists" {
    const cfg = init("network_id = demo");
    try std.testing.expectEqualStrings("network_id = demo", cfg.raw);
}

test "file config schema captures top level sections" {
    const cfg = FileConfig{
        .raw = "",
        .node = .{
            .name = "alpha",
            .network_id = "home-net",
            .identity_path = "/var/lib/libvine/identity",
        },
        .tun = .{
            .name = "vine0",
            .address = "10.42.0.1",
            .prefix_len = 24,
            .mtu = 1400,
        },
        .bootstrap_peers = &.{.{ .peer_id = "peer-a", .address = "udp://198.51.100.10:4100" }},
        .allowed_peers = &.{.{ .peer_id = "peer-b", .prefix = "10.42.1.0/24", .relay_capable = true }},
    };

    try std.testing.expectEqualStrings("alpha", cfg.node.name);
    try std.testing.expectEqual(@as(u8, 24), cfg.tun.prefix_len);
    try std.testing.expectEqual(@as(usize, 1), cfg.bootstrap_peers.len);
    try std.testing.expectEqual(@as(usize, 1), cfg.allowed_peers.len);
    try std.testing.expect(cfg.policy.strict_allowlist);
    _ = types;
}

test "parse reads node name network id and identity path" {
    const raw =
        \\[node]
        \\name = "alpha"
        \\network_id = "home-net"
        \\identity_path = "/var/lib/libvine/identity"
    ;

    var cfg = try parse(std.testing.allocator, raw);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("alpha", cfg.node.name);
    try std.testing.expectEqualStrings("home-net", cfg.node.network_id);
    try std.testing.expectEqualStrings("/var/lib/libvine/identity", cfg.node.identity_path);
}

test "parse reads tun interface parameters" {
    const raw =
        \\[tun]
        \\name = "vine0"
        \\address = "10.42.0.1"
        \\prefix_len = 24
        \\mtu = 1380
    ;

    var cfg = try parse(std.testing.allocator, raw);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("vine0", cfg.tun.name);
    try std.testing.expectEqualStrings("10.42.0.1", cfg.tun.address);
    try std.testing.expectEqual(@as(u8, 24), cfg.tun.prefix_len);
    try std.testing.expectEqual(@as(u16, 1380), cfg.tun.mtu);
}

test "parse reads bootstrap peer records" {
    const raw =
        \\[[bootstrap_peers]]
        \\peer_id = "peer-a"
        \\address = "udp://198.51.100.10:4100"
        \\
        \\[[bootstrap_peers]]
        \\peer_id = "peer-b"
        \\address = "udp://198.51.100.11:4100"
    ;

    var cfg = try parse(std.testing.allocator, raw);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), cfg.bootstrap_peers.len);
    try std.testing.expectEqualStrings("peer-a", cfg.bootstrap_peers[0].peer_id);
    try std.testing.expectEqualStrings("udp://198.51.100.11:4100", cfg.bootstrap_peers[1].address);
}

test "parse reads allowed peer records with prefix ownership" {
    const raw =
        \\[[allowed_peers]]
        \\peer_id = "peer-a"
        \\prefix = "10.42.1.0/24"
        \\
        \\[[allowed_peers]]
        \\peer_id = "peer-b"
        \\prefix = "10.42.2.0/24"
    ;

    var cfg = try parse(std.testing.allocator, raw);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), cfg.allowed_peers.len);
    try std.testing.expectEqualStrings("peer-a", cfg.allowed_peers[0].peer_id);
    try std.testing.expectEqualStrings("10.42.2.0/24", cfg.allowed_peers[1].prefix);
    try std.testing.expect(!cfg.allowed_peers[0].relay_capable);
}
