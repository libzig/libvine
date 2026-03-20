const std = @import("std");
const core = @import("../core/core.zig");

pub const EnrollmentState = struct {
    pub const EnrolledPeer = struct {
        peer_id: core.types.PeerId,
        prefix: core.types.VinePrefix,
        relay_capable: bool = false,
    };

    local_membership: core.membership.LocalMembership,
    admission_policy: core.policy.AdmissionPolicy,
    enrolled_peers: []const EnrolledPeer = &.{},

    pub fn allowsPeer(self: EnrollmentState, peer_id: core.types.PeerId) bool {
        return self.admission_policy.allows(peer_id);
    }

    pub fn ownedPrefixFor(self: EnrollmentState, peer_id: core.types.PeerId) ?core.types.VinePrefix {
        for (self.enrolled_peers) |peer| {
            if (peer.peer_id.eql(peer_id)) return peer.prefix;
        }
        return null;
    }

    pub fn advertiseLocalMembership(self: EnrollmentState) core.membership.LocalMembership {
        return self.local_membership;
    }

    pub fn refreshRemoteMembership(
        self: EnrollmentState,
        memberships: []core.membership.PeerMembership,
        record: core.membership.PeerMembership,
    ) bool {
        _ = self;
        for (memberships) |*existing| {
            if (existing.peer_id.eql(record.peer_id)) {
                existing.* = record;
                return true;
            }
        }
        for (memberships) |*existing| {
            if (existing.epoch.value == 0 and existing.announced_at_ms == 0) {
                existing.* = record;
                return true;
            }
        }
        return false;
    }

    pub fn withdrawRemoteMembership(self: EnrollmentState, memberships: []core.membership.PeerMembership, peer_id: core.types.PeerId) bool {
        _ = self;
        for (memberships) |*membership| {
            if (membership.peer_id.eql(peer_id)) {
                membership.expires_at_ms = 0;
                return true;
            }
        }
        return false;
    }
};

test "enrollment state captures local membership and admission policy" {
    const peer = core.types.PeerId.init(.{0x44} ** core.types.peer_id_len);
    const state = EnrollmentState{
        .local_membership = .{
            .network_id = try core.types.NetworkId.init("devnet"),
            .peer_id = peer,
            .prefix = try core.types.VinePrefix.parse("10.42.0.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .attached_at_ms = 0,
        },
        .admission_policy = .{
            .allowed_peers = &.{peer},
        },
        .enrolled_peers = &.{},
    };

    try std.testing.expect(state.admission_policy.allows(peer));
    try std.testing.expect(state.local_membership.prefix.contains(core.types.VineAddress.init(.{ 10, 42, 0, 7 })));
}

test "enrollment state enforces allowlist by peer id" {
    const peer_a = core.types.PeerId.init(.{0x11} ** core.types.peer_id_len);
    const peer_b = core.types.PeerId.init(.{0x22} ** core.types.peer_id_len);
    const state = EnrollmentState{
        .local_membership = .{
            .network_id = try core.types.NetworkId.init("devnet"),
            .peer_id = peer_a,
            .prefix = try core.types.VinePrefix.parse("10.42.0.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .attached_at_ms = 0,
        },
        .admission_policy = .{
            .allowed_peers = &.{peer_a},
        },
        .enrolled_peers = &.{},
    };

    try std.testing.expect(state.allowsPeer(peer_a));
    try std.testing.expect(!state.allowsPeer(peer_b));
}

test "enrollment state binds one configured prefix per allowed peer" {
    const peer_a = core.types.PeerId.init(.{0x11} ** core.types.peer_id_len);
    const peer_b = core.types.PeerId.init(.{0x22} ** core.types.peer_id_len);
    const state = EnrollmentState{
        .local_membership = .{
            .network_id = try core.types.NetworkId.init("devnet"),
            .peer_id = peer_a,
            .prefix = try core.types.VinePrefix.parse("10.42.0.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .attached_at_ms = 0,
        },
        .admission_policy = .{
            .allowed_peers = &.{ peer_a, peer_b },
        },
        .enrolled_peers = &.{
            .{ .peer_id = peer_b, .prefix = try core.types.VinePrefix.parse("10.42.1.0/24") },
        },
    };

    try std.testing.expect(state.ownedPrefixFor(peer_b) != null);
    try std.testing.expect(state.ownedPrefixFor(peer_b).?.contains(core.types.VineAddress.init(.{ 10, 42, 1, 99 })));
    try std.testing.expect(state.ownedPrefixFor(peer_a) == null);
}

test "enrollment state advertises local membership on startup" {
    const peer = core.types.PeerId.init(.{0x33} ** core.types.peer_id_len);
    const state = EnrollmentState{
        .local_membership = .{
            .network_id = try core.types.NetworkId.init("devnet"),
            .peer_id = peer,
            .prefix = try core.types.VinePrefix.parse("10.42.0.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .attached_at_ms = 0,
        },
        .admission_policy = .{ .allowed_peers = &.{peer} },
        .enrolled_peers = &.{},
    };

    const advertised = state.advertiseLocalMembership();
    try std.testing.expect(advertised.peer_id.eql(peer));
    try std.testing.expect(advertised.prefix.contains(core.types.VineAddress.init(.{ 10, 42, 0, 9 })));
}

test "enrollment state refreshes remote memberships from control plane updates" {
    const peer_a = core.types.PeerId.init(.{0x11} ** core.types.peer_id_len);
    const peer_b = core.types.PeerId.init(.{0x22} ** core.types.peer_id_len);
    var memberships = [_]core.membership.PeerMembership{
        .{
            .peer_id = peer_a,
            .prefix = try core.types.VinePrefix.parse("10.42.1.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .announced_at_ms = 1,
        },
        std.mem.zeroes(core.membership.PeerMembership),
    };
    const state = EnrollmentState{
        .local_membership = .{
            .network_id = try core.types.NetworkId.init("devnet"),
            .peer_id = peer_a,
            .prefix = try core.types.VinePrefix.parse("10.42.0.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .attached_at_ms = 0,
        },
        .admission_policy = .{ .allowed_peers = &.{ peer_a, peer_b } },
        .enrolled_peers = &.{},
    };

    try std.testing.expect(state.refreshRemoteMembership(&memberships, .{
        .peer_id = peer_a,
        .prefix = try core.types.VinePrefix.parse("10.42.1.0/24"),
        .epoch = core.types.MembershipEpoch.init(2),
        .announced_at_ms = 2,
    }));
    try std.testing.expectEqual(@as(u64, 2), memberships[0].epoch.value);

    try std.testing.expect(state.refreshRemoteMembership(&memberships, .{
        .peer_id = peer_b,
        .prefix = try core.types.VinePrefix.parse("10.42.2.0/24"),
        .epoch = core.types.MembershipEpoch.init(1),
        .announced_at_ms = 3,
    }));
    try std.testing.expect(memberships[1].peer_id.eql(peer_b));
}

test "enrollment state withdraws remote membership cleanly" {
    const peer = core.types.PeerId.init(.{0x66} ** core.types.peer_id_len);
    var memberships = [_]core.membership.PeerMembership{
        .{
            .peer_id = peer,
            .prefix = try core.types.VinePrefix.parse("10.42.6.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .announced_at_ms = 1,
            .expires_at_ms = 999,
        },
    };
    const state = EnrollmentState{
        .local_membership = .{
            .network_id = try core.types.NetworkId.init("devnet"),
            .peer_id = peer,
            .prefix = try core.types.VinePrefix.parse("10.42.0.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .attached_at_ms = 0,
        },
        .admission_policy = .{ .allowed_peers = &.{peer} },
        .enrolled_peers = &.{},
    };

    try std.testing.expect(state.withdrawRemoteMembership(&memberships, peer));
    try std.testing.expectEqual(@as(?i64, 0), memberships[0].expires_at_ms);
}
