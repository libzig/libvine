const std = @import("std");

pub const api = @import("api/api.zig");
pub const common = @import("common/common.zig");
pub const control = @import("control/control.zig");
pub const core = @import("core/core.zig");
pub const data = @import("data/data.zig");
pub const integration = @import("integration/integration.zig");
pub const linux = @import("linux/linux.zig");
pub const testing = @import("testing/testing.zig");

// Downstream packages such as libboid can use this as the public package
// compatibility marker while the API surface is still in early MVP development.
pub const version = std.SemanticVersion.parse("0.0.1") catch unreachable;

test {
    _ = api;
    _ = common;
    _ = control;
    _ = core;
    _ = data;
    _ = integration;
    _ = linux;
    _ = testing;
    _ = version;
}
