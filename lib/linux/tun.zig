const VineError = @import("../common/error.zig").VineError;

pub const TunDevice = struct {
    fd: i32 = -1,
    ifname: [16]u8 = [_]u8{0} ** 16,

    pub fn open() VineError!TunDevice {
        return .{ .fd = 1 };
    }

    pub fn configure(self: *TunDevice, request: IfReq) void {
        self.ifname = request.name;
    }
};

pub const IfReq = struct {
    name: [16]u8 = [_]u8{0} ** 16,
    flags: u16 = 0,
};

pub fn mapOpenError(errno: u16) VineError {
    return switch (errno) {
        2 => VineError.LinuxUnavailable,
        13 => VineError.LinuxPermissionDenied,
        else => VineError.LinuxUnavailable,
    };
}
