const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

pub const Entry = struct { id: i64, content: []const u8, callsign: ?[]const u8, created_at: i64 };

pub fn listAll(db: *Db, allocator: Allocator) ![]Entry {
    const query = (
        \\SELECT id, content, callsign, created_at
        \\FROM flight_log_entries
        \\ORDER BY created_at DESC, id DESC
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const rows = try stmt.all(Entry, allocator, .{}, .{});

    return rows;
}

pub fn insert(db: *Db, io: std.Io, content: []const u8, callsign: ?[]const u8) !struct { id: i64, created_at: i64 } {
    const query = (
        \\INSERT INTO flight_log_entries(content, callsign, created_at) VALUES (?, ?, ?)
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    try stmt.exec(.{}, .{
        .content = content,
        .callsign = callsign,
        .created_at = created_at,
    });

    const id = db.getLastInsertRowID();

    return .{ .id = id, .created_at = created_at };
}
