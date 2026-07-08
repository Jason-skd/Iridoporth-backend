const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const flight_log_domain = @import("../domain/flight_log.zig");
const FlightLogEntry = flight_log_domain.FlightLogEntry;

pub fn listAll(allocator: Allocator, db: *Db) ![]FlightLogEntry {
    const query = (
        \\SELECT id, content, creator_user_id, created_at
        \\FROM flight_log_entries
        \\ORDER BY id DESC
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    return stmt.all(FlightLogEntry, allocator, .{}, .{});
}

pub fn insert(io: std.Io, allocator: Allocator, db: *Db, content: []const u8, creator_user_id: i64) !struct { id: i64, created_at: i64 } {
    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    const query = (
        \\INSERT INTO flight_log_entries(content, creator_user_id, created_at)
        \\VALUES (:content{[]const u8}, :creator_user_id{i64}, :created_at{i64})
        \\RETURNING entry_id
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const Row = struct { id: i64 };

    const row = (try stmt.oneAlloc(Row, allocator, .{}, .{
        .content = content,
        .creator_user_id = creator_user_id,
        .created_at = created_at,
    })) orelse return error.InsertDidNotReturnRow;

    return .{
        .id = row.id,
        .created_at = created_at,
    };
}
