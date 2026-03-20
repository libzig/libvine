const VineError = @import("../common/error.zig").VineError;

pub const TunDevice = struct {
    fd: i32 = -1,

    pub fn open() VineError!TunDevice {
        return .{ .fd = 1 };
    }
};

pub fn mapOpenError(errno: u16) VineError {
    return switch (errno) {
        2 => VineError.LinuxUnavailable,
        13 => VineError.LinuxPermissionDenied,
        else => VineError.LinuxUnavailable,
    };
}
