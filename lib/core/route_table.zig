const types = @import("types.zig");
const VineError = @import("../common/error.zig").VineError;

pub const RouteEntry = struct {
    pub const Preference = enum(u8) {
        relay = 1,
        direct_after_signaling = 2,
        direct = 3,
    };

    prefix: types.VinePrefix,
    peer_id: types.PeerId,
    session_id: ?types.SessionId = null,
    epoch: types.MembershipEpoch,
    preference: Preference = .relay,
    generation: u64 = 0,
    tombstone: bool = false,
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
                if (entry.epoch.value < existing.epoch.value or entry.generation < existing.generation) {
                    return VineError.RouteConflict;
                }
                existing.* = entry;
                return;
            }
        }
        return VineError.RouteNotFound;
    }

    pub fn lookup(self: RouteTable, address: types.VineAddress) ?RouteEntry {
        var selected: ?RouteEntry = null;
        for (self.entries) |entry| {
            if (!entry.prefix.contains(address)) continue;

            if (selected == null or @intFromEnum(entry.preference) > @intFromEnum(selected.?.preference)) {
                selected = entry;
            }
        }
        return selected;
    }

    pub fn withdraw(self: *RouteTable, prefix: types.VinePrefix) bool {
        for (self.entries, 0..) |*entry, idx| {
            if (entry.prefix.network.eql(prefix.network) and entry.prefix.prefix_len == prefix.prefix_len) {
                self.entries[idx].session_id = null;
                self.entries[idx].tombstone = true;
                return true;
            }
        }
        return false;
    }
};
