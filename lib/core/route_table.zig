const types = @import("types.zig");
const VineError = @import("../common/error.zig").VineError;
const std = @import("std");

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

test "route table prefers direct routes during lookup" {
    var entries = [_]RouteEntry{
        .{
            .prefix = try types.VinePrefix.parse("10.0.0.0/24"),
            .peer_id = types.PeerId.init(.{1} ** types.peer_id_len),
            .session_id = types.SessionId.init(1),
            .epoch = types.MembershipEpoch.init(1),
            .preference = .relay,
        },
        .{
            .prefix = try types.VinePrefix.parse("10.0.0.0/24"),
            .peer_id = types.PeerId.init(.{2} ** types.peer_id_len),
            .session_id = types.SessionId.init(2),
            .epoch = types.MembershipEpoch.init(1),
            .preference = .direct,
        },
    };
    const table = RouteTable.init(&entries);

    const selected = table.lookup(try types.VineAddress.parse("10.0.0.42")).?;
    try std.testing.expectEqual(RouteEntry.Preference.direct, selected.preference);
    try std.testing.expect(selected.peer_id.eql(types.PeerId.init(.{2} ** types.peer_id_len)));
}

test "route table rejects stale epochs and generations" {
    var entries = [_]RouteEntry{
        .{
            .prefix = try types.VinePrefix.parse("10.0.1.0/24"),
            .peer_id = types.PeerId.init(.{3} ** types.peer_id_len),
            .session_id = types.SessionId.init(1),
            .epoch = types.MembershipEpoch.init(5),
            .preference = .direct,
            .generation = 8,
        },
    };
    var table = RouteTable.init(&entries);

    try std.testing.expectError(VineError.RouteConflict, table.upsert(.{
        .prefix = try types.VinePrefix.parse("10.0.1.0/24"),
        .peer_id = types.PeerId.init(.{4} ** types.peer_id_len),
        .session_id = types.SessionId.init(2),
        .epoch = types.MembershipEpoch.init(4),
        .preference = .relay,
        .generation = 7,
    }));
}

test "route table withdraw marks tombstones" {
    var entries = [_]RouteEntry{
        .{
            .prefix = try types.VinePrefix.parse("10.0.2.0/24"),
            .peer_id = types.PeerId.init(.{5} ** types.peer_id_len),
            .session_id = types.SessionId.init(3),
            .epoch = types.MembershipEpoch.init(2),
            .preference = .direct_after_signaling,
        },
    };
    var table = RouteTable.init(&entries);

    try std.testing.expect(table.withdraw(try types.VinePrefix.parse("10.0.2.0/24")));
    try std.testing.expect(table.entries[0].tombstone);
    try std.testing.expectEqual(@as(?types.SessionId, null), table.entries[0].session_id);
}

test "route table updates matching prefixes" {
    var entries = [_]RouteEntry{
        .{
            .prefix = try types.VinePrefix.parse("10.0.3.0/24"),
            .peer_id = types.PeerId.init(.{6} ** types.peer_id_len),
            .session_id = types.SessionId.init(4),
            .epoch = types.MembershipEpoch.init(1),
            .preference = .relay,
            .generation = 1,
        },
    };
    var table = RouteTable.init(&entries);

    try table.upsert(.{
        .prefix = try types.VinePrefix.parse("10.0.3.0/24"),
        .peer_id = types.PeerId.init(.{7} ** types.peer_id_len),
        .session_id = types.SessionId.init(5),
        .epoch = types.MembershipEpoch.init(2),
        .preference = .direct_after_signaling,
        .generation = 2,
    });

    const selected = table.lookup(try types.VineAddress.parse("10.0.3.7")).?;
    try std.testing.expect(selected.peer_id.eql(types.PeerId.init(.{7} ** types.peer_id_len)));
    try std.testing.expectEqual(RouteEntry.Preference.direct_after_signaling, selected.preference);
}
