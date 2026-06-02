const std = @import("std");
const sqlite = @import("sqlite");

const Allocator = std.mem.Allocator;

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
