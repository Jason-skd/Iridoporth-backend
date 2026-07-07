const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const user_session_domain = @import("../domain/user_session.zig");
const UserSession = user_session_domain.UserSession;

const user_service = @import("./user.zig");

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

pub fn insert(db: *Db, io: std.Io, allocator: Allocator, content: []const u8, token: []const u8) !struct { id: i64, created_at: i64 } {
    const callsign = try getCallsignFromToken(db, allocator, token);

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

pub fn getTokenForNewUser(io: std.Io, db: *Db, allocator: Allocator) ![]const u8 {
    const user = try user_service.createUser(io, db, allocator, .anonymous, .user);

    const session_token = try user_session_domain.generateSessionToken(io);
    const token_hash = user_session_domain.hashSessionToken(session_token[0..]);
    const expires_at = std.Io.Timestamp.now(io, .real).toSeconds() + 60 * 60 * 24 * 91; // 91 days from now
    _ = try user_service.createSession(io, db, allocator, user.id, .anonymous_cookie, token_hash[0..], expires_at);

    return session_token;
}

fn getCallsignFromToken(db: *Db, allocator: Allocator, token: []const u8) !?[]const u8 {
    const token_hash = user_session_domain.hashSessionToken(token);

    const user_session: UserSession = try user_service.findUserSessionByTokenHash(db, allocator, token_hash) orelse return error.InvalidSessionToken;

    const user = try user_service.findUserById(db, allocator, user_session.user_id) orelse return error.UserNotFound;

    return switch (user.kind) {
        .anonymous => null,
        .account => |account| account.name,
    };
}

// const test_alloc = std.testing.allocator;
// const test_io = std.testing.io;

// const schema =
//     \\CREATE TABLE flight_log_entries (
//     \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
//     \\    content TEXT NOT NULL,
//     \\    callsign TEXT,
//     \\    created_at INTEGER NOT NULL
//     \\);
// ;

// fn freshDb() !Db {
//     var db = try Db.init(.{
//         .mode = .Memory,
//         .open_flags = .{ .write = true, .create = true },
//     });
//     errdefer db.deinit();
//     try db.execMulti(schema, .{});
//     return db;
// }

// test "listAll returns rows in id DESC order" {
//     var db = try freshDb();
//     defer db.deinit();

//     var arena = std.heap.ArenaAllocator.init(test_alloc);
//     defer arena.deinit();

//     _ = try insert(&db, test_io, "first", "AAA");
//     _ = try insert(&db, test_io, "second", null);
//     _ = try insert(&db, test_io, "third", "BBB");

//     const entries = try listAll(&db, arena.allocator());

//     try std.testing.expectEqual(@as(usize, 3), entries.len);
//     try std.testing.expectEqualStrings("third", entries[0].content);
//     try std.testing.expectEqualStrings("second", entries[1].content);
//     try std.testing.expectEqualStrings("first", entries[2].content);
// }

// test "listAll returns empty slice when table is empty" {
//     var db = try freshDb();
//     defer db.deinit();

//     var arena = std.heap.ArenaAllocator.init(test_alloc);
//     defer arena.deinit();

//     const entries = try listAll(&db, arena.allocator());
//     try std.testing.expectEqual(@as(usize, 0), entries.len);
// }

// test "listAll preserves null callsign" {
//     var db = try freshDb();
//     defer db.deinit();

//     var arena = std.heap.ArenaAllocator.init(test_alloc);
//     defer arena.deinit();

//     _ = try insert(&db, test_io, "no-callsign", null);
//     _ = try insert(&db, test_io, "with-callsign", "ALPHA");

//     const entries = try listAll(&db, arena.allocator());

//     try std.testing.expectEqual(@as(usize, 2), entries.len);
//     try std.testing.expect(entries[0].callsign != null);
//     try std.testing.expect(entries[1].callsign == null);
// }

// test "insert returns monotonically increasing ids and non-zero created_at" {
//     var db = try freshDb();
//     defer db.deinit();

//     const a = try insert(&db, test_io, "x", null);
//     const b = try insert(&db, test_io, "y", null);

//     try std.testing.expect(b.id > a.id);
//     try std.testing.expect(a.created_at > 0);
//     try std.testing.expect(b.created_at >= a.created_at);
// }
