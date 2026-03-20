const types = @import("types.zig");
const VineError = @import("../common/error.zig").VineError;

pub const RouteEntry = struct {
    prefix: types.VinePrefix,
    peer_id: types.PeerId,
    session_id: ?types.SessionId = null,
    epoch: types.MembershipEpoch,
};

pub const RouteTable = struct {
    entries: []RouteEntry,

    pub fn init(entries: []RouteEntry) RouteTable {
        return .{ .entries = entries };
    }

    pub fn upsert(self: *RouteTable, entry: RouteEntry) VineError!void {
        for (self.entries) |*existing| {
            if (existing.prefix.network.eql(entry.prefix.network) and
                existing.prefix.prefix_len == entry.prefix.prefix_len)
            {
                existing.* = entry;
                return;
            }
        }
        return VineError.RouteNotFound;
    }

    pub fn lookup(self: RouteTable, address: types.VineAddress) ?RouteEntry {
        for (self.entries) |entry| {
            if (entry.prefix.contains(address)) return entry;
        }
        return null;
    }

    pub fn withdraw(self: *RouteTable, prefix: types.VinePrefix) bool {
        for (self.entries, 0..) |*entry, idx| {
            if (entry.prefix.network.eql(prefix.network) and entry.prefix.prefix_len == prefix.prefix_len) {
                self.entries[idx].session_id = null;
                return true;
            }
        }
        return false;
    }
};
