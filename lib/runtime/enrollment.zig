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
