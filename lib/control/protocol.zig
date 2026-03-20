const types = @import("../core/types.zig");

pub const protocol_version_major: u16 = 0;
pub const protocol_version_minor: u16 = 1;
pub const max_message_len: usize = types.max_control_payload_len;

pub const MessageTag = enum(u8) {
    hello = 1,
    join_announce = 2,
    route_update = 3,
    route_withdraw = 4,
    keepalive = 5,
    diagnostic_ping = 6,
    diagnostic_pong = 7,
};

pub const CapabilityFlags = packed struct(u8) {
    relay_capable: bool = false,
    direct_capable: bool = true,
    diagnostic_capable: bool = false,
    reserved: u5 = 0,
};

pub const Hello = struct {
    network_id: types.NetworkId,
    version_major: u16,
    version_minor: u16,
    capabilities: CapabilityFlags = .{},
};

pub const JoinAnnounce = struct {
    network_id: types.NetworkId,
    prefix: types.VinePrefix,
    epoch: types.MembershipEpoch,
};

pub const RouteUpdate = struct {
    network_id: types.NetworkId,
    owner: types.PeerId,
    prefix: types.VinePrefix,
    epoch: types.MembershipEpoch,
};

pub const RouteWithdraw = struct {
    network_id: types.NetworkId,
    owner: types.PeerId,
    prefix: types.VinePrefix,
    epoch: types.MembershipEpoch,
};

pub const Keepalive = struct {
    network_id: types.NetworkId,
    session_id: types.SessionId,
    sent_at_ms: i64,
};

pub const DiagnosticPing = struct {
    network_id: types.NetworkId,
    nonce: u64,
    sent_at_ms: i64,
};

pub const DiagnosticPong = struct {
    network_id: types.NetworkId,
    nonce: u64,
    replied_at_ms: i64,
};
