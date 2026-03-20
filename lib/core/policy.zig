const membership = @import("membership.zig");
const types = @import("types.zig");
const std = @import("std");

pub const AdmissionPolicy = struct {
    allowed_peers: []const types.PeerId = &.{},

    pub fn allows(self: AdmissionPolicy, peer_id: types.PeerId) bool {
        for (self.allowed_peers) |allowed| {
            if (allowed.eql(peer_id)) return true;
        }
        return false;
    }
};

pub const PrefixPolicy = struct {
    allow_primary_only: bool = true,

    pub fn allows(self: PrefixPolicy, record: membership.PeerMembership) bool {
        _ = record;
        return self.allow_primary_only;
    }

    pub fn conflicts(
        _: PrefixPolicy,
        incoming: membership.PeerMembership,
        existing: membership.PeerMembership,
    ) bool {
        if (incoming.peer_id.eql(existing.peer_id)) return false;

        return incoming.prefix.contains(existing.prefix.network) or
            existing.prefix.contains(incoming.prefix.network);
    }
};

test "AdmissionPolicy only allows configured peers" {
    const peer_a = types.PeerId.init(.{1} ** types.peer_id_len);
    const peer_b = types.PeerId.init(.{2} ** types.peer_id_len);
    const admission = AdmissionPolicy{
        .allowed_peers = &.{peer_a},
    };

    try std.testing.expect(admission.allows(peer_a));
    try std.testing.expect(!admission.allows(peer_b));
}

test "PrefixPolicy detects overlapping peer prefixes" {
    const flags = membership.PeerPolicyFlags{};
    const peer_a = membership.PeerMembership{
        .peer_id = types.PeerId.init(.{1} ** types.peer_id_len),
        .prefix = try types.VinePrefix.parse("10.0.0.0/24"),
        .epoch = types.MembershipEpoch.init(1),
        .flags = flags,
        .announced_at_ms = 1,
    };
    const peer_b = membership.PeerMembership{
        .peer_id = types.PeerId.init(.{2} ** types.peer_id_len),
        .prefix = try types.VinePrefix.parse("10.0.0.0/25"),
        .epoch = types.MembershipEpoch.init(1),
        .flags = flags,
        .announced_at_ms = 1,
    };

    const prefix_policy = PrefixPolicy{};
    try std.testing.expect(prefix_policy.allows(peer_a));
    try std.testing.expect(prefix_policy.conflicts(peer_a, peer_b));
}
