pub const VineError = error{
    InvalidNetworkId,
    InvalidVineAddress,
    InvalidVinePrefix,
    InvalidPeerId,
    InvalidMembershipEpoch,
    InvalidSessionId,
    InvalidControlMessage,
    ParseFailure,
    MessageTooLarge,
    VersionMismatch,
    NetworkMismatch,
    PeerMismatch,
    RouteNotFound,
    RouteConflict,
    PolicyDenied,
    TransportUnavailable,
    TransportClosed,
    LinuxUnavailable,
    LinuxPermissionDenied,
};

pub const FailureDomain = enum {
    parsing,
    routing,
    policy,
    transport,
    linux,
};

pub fn mapFailure(domain: FailureDomain) VineError {
    return switch (domain) {
        .parsing => VineError.ParseFailure,
        .routing => VineError.RouteNotFound,
        .policy => VineError.PolicyDenied,
        .transport => VineError.TransportUnavailable,
        .linux => VineError.LinuxUnavailable,
    };
}
