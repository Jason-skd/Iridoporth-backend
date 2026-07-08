const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const migrations = @import("migrations.zig");

const current_schema_version = 1;

pub fn init(path: [:0]const u8) !Db {
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

    return db;
}

fn applyPragmas(db: *sqlite.Db) !void {
    _ = try db.pragma([128:0]u8, .{}, "journal_mode", "wal");
    _ = try db.pragma(void, .{}, "busy_timeout", "3000");
    _ = try db.pragma(void, .{}, "synchronous", "NORMAL");
    _ = try db.pragma(void, .{}, "foreign_keys", "ON");
}

fn migrate(db: *sqlite.Db) !void {
    const version = (try db.pragma(usize, .{}, "user_version", null)) orelse 0;

    if (version > current_schema_version) {
        return error.DatabaseSchemaTooNew;
    }

    if (version < 1) {
        try db.exec("BEGIN IMMEDIATE", .{}, .{});
        errdefer db.exec("ROLLBACK", .{}, .{}) catch {};

        try migrations.migrateToV1(db);
        _ = try db.pragma(void, .{}, "user_version", "1");

        try db.exec("COMMIT", .{}, .{});
    }
}
