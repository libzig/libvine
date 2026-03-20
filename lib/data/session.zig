const frame = @import("frame.zig");
const types = @import("../core/types.zig");

pub const Session = struct {
    session_id: types.SessionId,
    control_mode: frame.CarriageMode = .reliable_control_stream,
    data_mode: frame.CarriageMode = .packet_data_path,

    pub fn init(session_id: types.SessionId) Session {
        return .{ .session_id = session_id };
    }
};
