const std = @import("std");
const sqlite = @import("sqlite");

const Allocator = std.mem.Allocator;

const current_schema_version = 1;

pub const Database = struct {
    db: sqlite.Db,

    pub fn init(path: [:0]const u8) !Database {
        var db = try sqlite.Db.init(.{
            .mode = .{ .File = path },
            .open_flags = .{
                .write = true,
                .create = true,
            },
            .threading_mode = .Serialized,
        });
        errdefer db.deinit();

        try applyPragmas(&db);
        try migrate(&db);

        return .{
            .db = db,
        };
    }

    pub fn deinit(self: *Database) void {
        self.db.deinit();
    }
};

fn applyPragmas(db: *sqlite.Db) !void {
    _ = try db.pragma([128:0]u8, .{}, "journal_mode", "wal");
    _ = try db.pragma(void, .{}, "busy_timeout", "3000");
    _ = try db.pragma(void, .{}, "synchronous", "NORMAL");
}

fn migrate(db: *sqlite.Db) !void {
    const version = (try db.pragma(usize, .{}, "user_version", null)) orelse 0;

    if (version > current_schema_version) {
        return error.DatabaseSchemaTooNew;
    }

    if (version < 1) {
        try db.exec("BEGIN IMMEDIATE", .{}, .{});
        errdefer db.exec("ROLLBACK", .{}, .{}) catch {};

        try migrateToV1(db);
        _ = try db.pragma(void, .{}, "user_version", "1");

        try db.exec("COMMIT", .{}, .{});
    }
}

fn migrateToV1(db: *sqlite.Db) !void {
    try db.execMulti(
        \\CREATE TABLE IF NOT EXISTS flight_log_entries (
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    content TEXT NOT NULL,
        \\    callsign TEXT,
        \\    created_at INTEGER NOT NULL
        \\);
        \\
        \\CREATE INDEX IF NOT EXISTS idx_flight_log_entries_created_at
        \\ON flight_log_entries(created_at DESC, id DESC);
    , .{});
}
