const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

pub const Entry = struct { id: i64, content: []const u8, callsign: ?[]const u8, created_at: i64 };

pub fn listAll(db: *Db, allocator: Allocator) ![]Entry {
    const query = (
        \\SELECT id, content, callsign, created_at
        \\FROM flight_log_entries
        \\ORDER BY id DESC
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const rows = try stmt.all(Entry, allocator, .{}, .{});

    return rows;
}

pub fn insert(db: *Db, io: std.Io, content: []const u8, callsign: ?[]const u8) !struct { id: i64, created_at: i64 } {
    const query = (
        \\INSERT INTO flight_log_entries(content, callsign, created_at)
        \\VALUES (?, ?, ?)
        \\RETURNING id
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    const Row = struct { id: i64 };

    const row = (try stmt.one(Row, .{}, .{
        .content = content,
        .callsign = callsign,
        .created_at = created_at,
    })) orelse return error.InsertDidNotReturnRow;

    return .{ .id = row.id, .created_at = created_at };
}

const test_alloc = std.testing.allocator;
const test_io = std.testing.io;

const schema =
    \\CREATE TABLE flight_log_entries (
    \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    content TEXT NOT NULL,
    \\    callsign TEXT,
    \\    created_at INTEGER NOT NULL
    \\);
;

fn freshDb() !Db {
    var db = try Db.init(.{
        .mode = .Memory,
        .open_flags = .{ .write = true, .create = true },
    });
    errdefer db.deinit();
    try db.execMulti(schema, .{});
    return db;
}

test "listAll returns rows in id DESC order" {
    var db = try freshDb();
    defer db.deinit();

    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();

    _ = try insert(&db, test_io, "first", "AAA");
    _ = try insert(&db, test_io, "second", null);
    _ = try insert(&db, test_io, "third", "BBB");

    const entries = try listAll(&db, arena.allocator());

    try std.testing.expectEqual(@as(usize, 3), entries.len);
    try std.testing.expectEqualStrings("third", entries[0].content);
    try std.testing.expectEqualStrings("second", entries[1].content);
    try std.testing.expectEqualStrings("first", entries[2].content);
}

test "listAll returns empty slice when table is empty" {
    var db = try freshDb();
    defer db.deinit();

    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();

    const entries = try listAll(&db, arena.allocator());
    try std.testing.expectEqual(@as(usize, 0), entries.len);
}

test "listAll preserves null callsign" {
    var db = try freshDb();
    defer db.deinit();

    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();

    _ = try insert(&db, test_io, "no-callsign", null);
    _ = try insert(&db, test_io, "with-callsign", "ALPHA");

    const entries = try listAll(&db, arena.allocator());

    try std.testing.expectEqual(@as(usize, 2), entries.len);
    try std.testing.expect(entries[0].callsign != null);
    try std.testing.expect(entries[1].callsign == null);
}

test "insert returns monotonically increasing ids and non-zero created_at" {
    var db = try freshDb();
    defer db.deinit();

    const a = try insert(&db, test_io, "x", null);
    const b = try insert(&db, test_io, "y", null);

    try std.testing.expect(b.id > a.id);
    try std.testing.expect(a.created_at > 0);
    try std.testing.expect(b.created_at >= a.created_at);
}
