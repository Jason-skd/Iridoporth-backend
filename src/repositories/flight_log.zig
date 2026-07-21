const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const sqlite_adapter = @import("../db/sqlite.zig");

const flight_log_domain = @import("../domain/flight_log.zig");
const FlightLogListItem = flight_log_domain.FlightLogListItem;

pub fn listAll(allocator: Allocator, db: *Db, viewer_user_id: ?i64) ![]FlightLogListItem {
    const query = (
        \\WITH params(viwer_user_id) AS (
        \\  SELECT :viewer_user_id{?i64}
        \\)
        \\SELECT
        \\  e.entry_id,
        \\  e.content,
        \\  e.response,
        \\  e.responded_at,
        \\  e.creator_user_id,
        \\CASE
        \\  WHEN u.kind = 'anonymous' THEN 'Anonymous'
        \\  ELSE u.name
        \\END AS callsign,
        \\e.created_at,
        \\COUNT(l.user_id) AS likes,
        \\CASE
        \\  WHEN p.viewer_user_id IS NULL THEN 0
        \\  WHEN EXISTS (
        \\    SELECT 1
        \\    FROM flight_log_entry_likes mine
        \\    WHERE mine.entry_id = e.entry_id AND mine.user_id = p.viewer_user_id
        \\  ) THEN 1 
        \\  ELSE 0
        \\END AS liked_by_this_user,
        \\CASE
        \\  WHEN p.viewer_user_id IS NOT NULL AND e.creator_user_id = p.viewer_user_id THEN 1
        \\  ELSE 0
        \\END AS created_by_this_user,
        \\FROM flight_log_entries e
        \\CROSS JOIN params p
        \\JOIN users u ON u.user_id = e.creator_user_id
        \\LEFT JOIN flight_log_entry_likes l ON l.entry_id = e.entry_id
        \\WHERE e.deleted_at IS NULL AND e.hidden_at IS NULL
        \\GROUP BY e.entry_id
        \\ORDER BY e.entry_id DESC
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const Row = struct {
        id: i64,
        content: []const u8,
        response: ?[]const u8,
        responded_at: ?i64,
        callsign: []const u8,
        created_by_this_user: bool,
        created_at: i64,
        likes: i64,
        liked_by_this_user: bool,
    };
    const rows: []Row = try stmt.all(Row, allocator, .{}, .{
        .viewer_user_id = viewer_user_id,
    });

    const list = try allocator.alloc(FlightLogListItem, rows.len);
    for (0.., rows) |i, row| {
        list[i] = FlightLogListItem{
            .id = row.id,
            .content = row.content,
            .response = flight_log_domain.FlightLogResponse.fromDb(
                row.content,
                row.responded_at,
            ),
            .callsign = row.callsign,
            .created_at = row.created_at,
            .created_by_this_user = row.created_by_this_user,
            .likes = row.likes,
            .liked_by_this_user = row.liked_by_this_user,
        };
    }

    return list;
}

pub fn insert(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    content: []const u8,
    creator_user_id: i64,
) !struct { id: i64, created_at: i64 } {
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

pub fn respond(
    io: std.Io,
    db: *Db,
    entry_id: i64,
    response_content: []const u8,
) !void {
    const now = std.Io.Timestamp.now(io, .real);
    const responded_at = now.toSeconds();

    const query = (
        \\UPDATE flight_log_entries
        \\SET response = :response_content{[]const u8}, responded_at = :responded_at{i64}
        \\WHERE entry_id = :entry_id{i64}
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .response_content = response_content,
        .responded_at = responded_at,
        .entry_id = entry_id,
    });

    if (db.rowsAffected() == 0) {
        return error.EntryNotFound;
    }
}

pub fn delete(io: std.Io, db: *Db, entry_id: i64, action_user_id: i64) !void {
    const now = std.Io.Timestamp.now(io, .real);
    const deleted_at = now.toSeconds();

    const query = (
        \\UPDATE flight_log_entries
        \\SET deleted_at = :deleted_at{i64}
        \\WHERE entry_id = :entry_id{i64} AND creator_user_id = :viewer_user_id{i64}
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .deleted_at = deleted_at,
        .entry_id = entry_id,
        .viewer_user_id = action_user_id,
    });

    if (db.rowsAffected() == 0) {
        return error.EntryNotFoundOrNotOwnedByUser;
    }
}

pub fn hide(io: std.Io, db: *Db, entry_id: i64) !void {
    const now = std.Io.Timestamp.now(io, .real);
    const hidden_at = now.toSeconds();

    const query = (
        \\UPDATE flight_log_entries
        \\SET hidden_at = :hidden_at{i64}
        \\WHERE entry_id = :entry_id{i64}
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .hidden_at = hidden_at,
        .entry_id = entry_id,
    });

    if (db.rowsAffected() == 0) {
        return error.EntryNotFound;
    }
}

pub fn unhide(db: *Db, entry_id: i64) !void {
    const query = (
        \\UPDATE flight_log_entries
        \\SET hidden_at = NULL
        \\WHERE entry_id = :entry_id{i64}
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .entry_id = entry_id,
    });

    if (db.rowsAffected() == 0) {
        return error.EntryNotFound;
    }
}

pub fn like(db: *Db, entry_id: i64, viewer_user_id: i64) !void {
    const query = (
        \\INSERT OR IGNORE INTO flight_log_entry_likes(entry_id, user_id)
        \\VALUES (:entry_id{i64}, :viewer_user_id{i64})
        \\ON CONFLICT(entry_id, user_id) DO NOTHING
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .entry_id = entry_id,
        .viewer_user_id = viewer_user_id,
    });

    if (db.rowsAffected() == 0) {
        return error.EntryNotFoundOrAlreadyLiked;
    }
}

pub fn unlike(db: *Db, entry_id: i64, viewer_user_id: i64) !void {
    const query = (
        \\DELETE FROM flight_log_entry_likes
        \\WHERE entry_id = :entry_id{i64} AND user_id = :viewer_user_id{i64}
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .entry_id = entry_id,
        .viewer_user_id = viewer_user_id,
    });

    if (db.rowsAffected() == 0) {
        return error.EntryNotFoundOrNotLiked;
    }
}

fn seedFlightLogListData(db: *Db) !void {
    try db.execMulti(
        \\INSERT INTO users(user_id, kind, role, name, email, created_at, updated_at, last_seen_at)
        \\VALUES
        \\  (1, 'anonymous', 'user', NULL, NULL, 10, 10, 10),
        \\  (2, 'account', 'user', 'Maverick', 'maverick@example.com', 20, 20, 20);
        \\
        \\INSERT INTO flight_log_entries(entry_id, content, response, responded_at, creator_user_id, created_at, deleted_at, hidden_at)
        \\VALUES
        \\  (1, 'Pattern entry', NULL, NULL, 1, 100, NULL, NULL),
        \\  (2, 'Holding short final', 'Copy that', 250, 2, 200, NULL, NULL),
        \\  (3, 'Deleted entry', NULL, NULL, 1, 300, 301, NULL),
        \\  (4, 'Hidden entry', NULL, NULL, 1, 400, NULL, 401);
        \\
        \\INSERT INTO flight_log_entry_likes(entry_id, user_id, created_at)
        \\VALUES (1, 2, 150);
    , .{});
}

test "listAll returns visible entries with viewer state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.init();

    try seedFlightLogListData(&db);

    const viewer_user_id: i64 = 2;
    const entries = try listAll(
        arena.allocator(),
        &db,
        viewer_user_id,
    );

    try std.testing.expectEqual(@as(usize, 2), entries.len);

    const first_entry = entries[0];
    try std.testing.expectEqual(@as(i64, 2), first_entry.id);
    try std.testing.expectEqualStrings(
        "Holding short final",
        first_entry.content,
    );
    try std.testing.expectEqualStrings("Maverick", first_entry.callsign);
    try std.testing.expect(first_entry.created_by_this_user);
    try std.testing.expectEqual(@as(i64, 200), first_entry.created_at);
    try std.testing.expectEqual(@as(i64, 0), first_entry.likes);
    try std.testing.expect(!first_entry.liked_by_this_user);
    try std.testing.expectEqual(
        flight_log_domain.FlightLogResponseTag.Response,
        std.meta.activeTag(first_entry.response),
    );
    try std.testing.expectEqualStrings(
        "Copy that",
        first_entry.response.Response.content,
    );
    try std.testing.expectEqual(
        @as(i64, 250),
        first_entry.response.Response.responded_at,
    );

    const second_entry = entries[1];
    try std.testing.expectEqual(@as(i64, 1), second_entry.id);
    try std.testing.expectEqualStrings(
        "Pattern entry",
        second_entry.content,
    );
    try std.testing.expectEqualStrings(
        "Anonymous",
        second_entry.callsign,
    );
    try std.testing.expect(!second_entry.created_by_this_user);
    try std.testing.expectEqual(@as(i64, 100), second_entry.created_at);
    try std.testing.expectEqual(@as(i64, 1), second_entry.likes);
    try std.testing.expect(second_entry.liked_by_this_user);
    try std.testing.expectEqual(
        flight_log_domain.FlightLogResponseTag.None,
        std.meta.activeTag(second_entry.response),
    );
}
