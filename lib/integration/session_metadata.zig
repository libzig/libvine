const types = @import("../core/types.zig");

pub const FeatureFlags = packed struct(u8) {
    supports_relay: bool = true,
    supports_diagnostics: bool = false,
    reserved: u6 = 0,
};

pub const SessionMetadata = struct {
    network_id: types.NetworkId,
    prefix: types.VinePrefix,
    transport_version_major: u16,
    transport_version_minor: u16,
    features: FeatureFlags = .{},
};
