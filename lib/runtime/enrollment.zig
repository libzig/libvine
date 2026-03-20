const std = @import("std");
const core = @import("../core/core.zig");

pub const EnrollmentState = struct {
    local_membership: core.membership.LocalMembership,
    admission_policy: core.policy.AdmissionPolicy,
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
    };

    try std.testing.expect(state.admission_policy.allows(peer));
    try std.testing.expect(state.local_membership.prefix.contains(core.types.VineAddress.init(.{ 10, 42, 0, 7 })));
}
