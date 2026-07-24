const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const sqlite_adapter = @import("../db/sqlite.zig");

const flight_log_domain = @import("../domain/flight_log.zig");
const FlightLogListItem = flight_log_domain.FlightLogListItem;
const FlightLogAdminListItem = flight_log_domain.FlightLogAdminListItem;

pub fn listAll(allocator: Allocator, db: *Db, viewer_user_id: ?i64) ![]FlightLogListItem {
    const query = (
        \\WITH params(viewer_user_id) AS (
        \\  SELECT :viewer_user_id{?i64}
        \\)
        \\SELECT
        \\  e.entry_id,
        \\  e.content,
        \\  e.response,
        \\  e.responded_at,
        \\  CASE
        \\    WHEN u.kind = 'anonymous' THEN 'Anonymous'
        \\    ELSE u.name
        \\  END AS callsign,
        \\  e.created_at,
        \\  CASE
        \\    WHEN p.viewer_user_id IS NOT NULL AND e.creator_user_id = p.viewer_user_id THEN 1
        \\    ELSE 0
        \\  END AS created_by_this_user,
        \\  COUNT(l.user_id) AS likes,
        \\  CASE
        \\    WHEN p.viewer_user_id IS NULL THEN 0
        \\    WHEN EXISTS (
        \\      SELECT 1
        \\      FROM flight_log_entry_likes mine
        \\      WHERE mine.entry_id = e.entry_id AND mine.user_id = p.viewer_user_id
        \\    ) THEN 1 
        \\    ELSE 0
        \\  END AS liked_by_this_user
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
        entry_id: i64,
        content: []const u8,
        response: ?[]const u8,
        responded_at: ?i64,
        callsign: []const u8,
        created_at: i64,
        created_by_this_user: bool,
        likes: i64,
        liked_by_this_user: bool,
    };
    const rows: []Row = try stmt.all(Row, allocator, .{}, .{
        .viewer_user_id = viewer_user_id,
    });

    const list = try allocator.alloc(FlightLogListItem, rows.len);
    for (0.., rows) |i, row| {
        list[i] = FlightLogListItem{
            .id = row.entry_id,
            .content = row.content,
            .response = flight_log_domain.FlightLogResponse.fromDb(
                row.response,
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

pub fn listAllForAdmin(allocator: Allocator, db: *Db, viewer_user_id: ?i64) ![]FlightLogAdminListItem {
    const query = (
        \\WITH params(viewer_user_id) AS (
        \\  SELECT :viewer_user_id{?i64}
        \\)
        \\SELECT
        \\  e.entry_id,
        \\  e.content,
        \\  e.response,
        \\  e.responded_at,
        \\  e.deleted_at,
        \\  e.hidden_at,
        \\  CASE
        \\    WHEN u.kind = 'anonymous' THEN 'Anonymous'
        \\    ELSE u.name
        \\  END AS callsign,
        \\  e.created_at,
        \\  CASE
        \\    WHEN p.viewer_user_id IS NOT NULL AND e.creator_user_id = p.viewer_user_id THEN 1
        \\    ELSE 0
        \\  END AS created_by_this_user,
        \\  COUNT(l.user_id) AS likes,
        \\  CASE
        \\    WHEN p.viewer_user_id IS NULL THEN 0
        \\    WHEN EXISTS (
        \\      SELECT 1
        \\      FROM flight_log_entry_likes mine
        \\      WHERE mine.entry_id = e.entry_id AND mine.user_id = p.viewer_user_id
        \\    ) THEN 1
        \\    ELSE 0
        \\  END AS liked_by_this_user
        \\FROM flight_log_entries e
        \\CROSS JOIN params p
        \\JOIN users u ON u.user_id = e.creator_user_id
        \\LEFT JOIN flight_log_entry_likes l ON l.entry_id = e.entry_id
        \\GROUP BY e.entry_id
        \\ORDER BY e.entry_id DESC
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const Row = struct {
        entry_id: i64,
        content: []const u8,
        response: ?[]const u8,
        responded_at: ?i64,
        deleted_at: ?i64,
        hidden_at: ?i64,
        callsign: []const u8,
        created_at: i64,
        created_by_this_user: bool,
        likes: i64,
        liked_by_this_user: bool,
    };
    const rows: []Row = try stmt.all(Row, allocator, .{}, .{
        .viewer_user_id = viewer_user_id,
    });

    const list = try allocator.alloc(FlightLogAdminListItem, rows.len);
    for (0.., rows) |i, row| {
        list[i] = FlightLogAdminListItem{
            .id = row.entry_id,
            .content = row.content,
            .response = flight_log_domain.FlightLogResponse.fromDb(
                row.response,
                row.responded_at,
            ),
            .callsign = row.callsign,
            .created_at = row.created_at,
            .created_by_this_user = row.created_by_this_user,
            .likes = row.likes,
            .liked_by_this_user = row.liked_by_this_user,
            .deleted_at = row.deleted_at,
            .hidden_at = row.hidden_at,
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
    })) orelse return sqlite_adapter.InsertReturningError.InsertDidNotReturnRow;

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
) !bool {
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

    return db.rowsAffected() != 0;
}

pub fn clearResponse(
    db: *Db,
    entry_id: i64,
) !bool {
    const query = (
        \\UPDATE flight_log_entries
        \\SET response = NULL, responded_at = NULL
        \\WHERE entry_id = :entry_id{i64}
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .entry_id = entry_id,
    });

    return db.rowsAffected() != 0;
}

pub fn delete(io: std.Io, db: *Db, entry_id: i64, viewer_user_id: i64) !bool {
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
        .viewer_user_id = viewer_user_id,
    });

    return db.rowsAffected() != 0;
}

pub fn hide(io: std.Io, db: *Db, entry_id: i64) !bool {
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

    return db.rowsAffected() != 0;
}

pub fn unhide(db: *Db, entry_id: i64) !bool {
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

    return db.rowsAffected() != 0;
}

pub fn like(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    entry_id: i64,
    viewer_user_id: i64,
) !bool {
    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    // use INSERT ... SELECT ... FROM not INSERT ... VALUES to avoid SQL error
    const query = (
        \\INSERT INTO flight_log_entry_likes(entry_id, user_id, created_at)
        \\SELECT entry_id, :viewer_user_id{i64}, :created_at{i64}
        \\FROM flight_log_entries
        \\WHERE entry_id = :entry_id{i64}
        \\  AND deleted_at IS NULL
        \\  AND hidden_at IS NULL
        \\ON CONFLICT(entry_id, user_id) DO NOTHING
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .entry_id = entry_id,
        .viewer_user_id = viewer_user_id,
        .created_at = created_at,
    });

    if (db.rowsAffected() != 0) {
        return true;
    }

    const check_query = (
        \\SELECT 1 AS entry_exists
        \\FROM flight_log_entries
        \\WHERE entry_id = :entry_id{i64}
        \\  AND deleted_at IS NULL
        \\  AND hidden_at IS NULL
    );

    var check_stmt = try db.prepare(check_query);
    defer check_stmt.deinit();

    const Row = struct { entry_exists: bool }; // no use, but corresponds to the query result, adapter requires
    return (try check_stmt.oneAlloc(Row, allocator, .{}, .{
        .entry_id = entry_id,
    })) != null;
}

pub fn unlike(
    allocator: Allocator,
    db: *Db,
    entry_id: i64,
    viewer_user_id: i64,
) !bool {
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

    if (db.rowsAffected() != 0) {
        return true;
    }

    const check_query = (
        \\SELECT 1 AS entry_exists
        \\FROM flight_log_entries
        \\WHERE entry_id = :entry_id{i64}
        \\  AND deleted_at IS NULL
        \\  AND hidden_at IS NULL
    );

    var check_stmt = try db.prepare(check_query);
    defer check_stmt.deinit();

    const Row = struct { entry_exists: bool };
    return (try check_stmt.oneAlloc(Row, allocator, .{}, .{
        .entry_id = entry_id,
    })) != null;
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
    defer db.deinit();

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

test "listAllForAdmin returns all entries including hidden and deleted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.deinit();

    try seedFlightLogListData(&db);

    const entries = try listAllForAdmin(
        arena.allocator(),
        &db,
        2,
    );

    try std.testing.expectEqual(@as(usize, 4), entries.len);

    // entries[0] == id 4 (hidden)
    try std.testing.expectEqual(@as(i64, 4), entries[0].id);
    try std.testing.expectEqual(@as(?i64, 401), entries[0].hidden_at);
    try std.testing.expectEqual(@as(?i64, null), entries[0].deleted_at);

    // entries[1] == id 3 (deleted)
    try std.testing.expectEqual(@as(i64, 3), entries[1].id);
    try std.testing.expectEqual(@as(?i64, 301), entries[1].deleted_at);
    try std.testing.expectEqual(@as(?i64, null), entries[1].hidden_at);

    // visible entries carry null state
    try std.testing.expectEqual(@as(?i64, null), entries[2].deleted_at);
    try std.testing.expectEqual(@as(?i64, null), entries[2].hidden_at);
    try std.testing.expectEqual(@as(?i64, null), entries[3].deleted_at);
    try std.testing.expectEqual(@as(?i64, null), entries[3].hidden_at);
}

test "insert create entry and could be retrieved by listAll" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.deinit();

    try seedFlightLogListData(&db);

    const anonymous_content = "Anonymous entry";
    const anonymous_creator_user_id: i64 = 1;
    var result = try insert(
        std.testing.io,
        arena.allocator(),
        &db,
        anonymous_content,
        anonymous_creator_user_id,
    );

    try std.testing.expectEqual(@as(i64, 5), result.id);

    var entries = try listAll(
        arena.allocator(),
        &db,
        anonymous_creator_user_id,
    );
    var new_entry = entries[0];
    try std.testing.expectEqual(result.id, new_entry.id);
    try std.testing.expectEqualStrings(anonymous_content, new_entry.content);
    try std.testing.expectEqualStrings("Anonymous", new_entry.callsign);
    try std.testing.expectEqual(@as(i64, result.created_at), new_entry.created_at);
    try std.testing.expect(new_entry.created_by_this_user);

    const account_content = "Account entry";
    const account_creator_user_id: i64 = 2;
    result = try insert(
        std.testing.io,
        arena.allocator(),
        &db,
        account_content,
        account_creator_user_id,
    );

    entries = try listAll(
        arena.allocator(),
        &db,
        account_creator_user_id,
    );
    new_entry = entries[0];
    try std.testing.expectEqual(result.id, new_entry.id);
    try std.testing.expectEqualStrings("Maverick", new_entry.callsign);
}

test "respond returns whether an entry exists and overwrites previous response" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.deinit();

    try seedFlightLogListData(&db);

    try std.testing.expect(try respond(
        std.testing.io,
        &db,
        1,
        "Cleared for landing",
    ));

    var entries = try listAll(
        arena.allocator(),
        &db,
        null,
    );
    const responded_entry = entries[1];
    try std.testing.expectEqual(
        flight_log_domain.FlightLogResponseTag.Response,
        std.meta.activeTag(responded_entry.response),
    );
    try std.testing.expectEqualStrings(
        "Cleared for landing",
        responded_entry.response.Response.content,
    );

    try std.testing.expect(try respond(
        std.testing.io,
        &db,
        1,
        "Roger, runway 09",
    ));

    entries = try listAll(
        arena.allocator(),
        &db,
        null,
    );
    const overwritten_entry = entries[1];
    try std.testing.expectEqualStrings(
        "Roger, runway 09",
        overwritten_entry.response.Response.content,
    );

    try std.testing.expect(!try respond(
        std.testing.io,
        &db,
        99,
        "No entry",
    ));
}

test "clearResponse returns whether an entry exists and is idempotent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.deinit();

    try seedFlightLogListData(&db);

    // Entry 2 already has a response in seed data.
    try std.testing.expect(try clearResponse(&db, 2));

    const entries_after_clear = try listAll(
        arena.allocator(),
        &db,
        null,
    );
    const cleared_entry = entries_after_clear[1];
    try std.testing.expectEqual(
        flight_log_domain.FlightLogResponseTag.None,
        std.meta.activeTag(cleared_entry.response),
    );

    // Clearing an entry that already has no response still succeeds.
    try std.testing.expect(try clearResponse(&db, 1));

    try std.testing.expect(!try clearResponse(&db, 99));
}

test "delete removes entry and guest can't remove owner's entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.deinit();

    try seedFlightLogListData(&db);

    try std.testing.expect(try delete(
        std.testing.io,
        &db,
        1,
        1,
    ));
    const entries = try listAll(
        arena.allocator(),
        &db,
        1,
    );
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqual(@as(i64, 2), entries[0].id);

    try std.testing.expect(!try delete(
        std.testing.io,
        &db,
        2,
        1,
    ));
}

test "like and unlike are idempotent for visible entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.deinit();

    try seedFlightLogListData(&db);

    try std.testing.expect(try like(
        std.testing.io,
        arena.allocator(),
        &db,
        2,
        1,
    ));
    try std.testing.expect(try like(
        std.testing.io,
        arena.allocator(),
        &db,
        2,
        1,
    ));

    const entries = try listAll(
        arena.allocator(),
        &db,
        1,
    );

    const liked_entry = entries[0];
    try std.testing.expectEqual(@as(i64, 1), liked_entry.likes);
    try std.testing.expect(liked_entry.liked_by_this_user);

    try std.testing.expect(try unlike(
        arena.allocator(),
        &db,
        2,
        1,
    ));
    try std.testing.expect(try unlike(
        arena.allocator(),
        &db,
        2,
        1,
    ));

    const unliked_entries = try listAll(
        arena.allocator(),
        &db,
        1,
    );
    const unliked_entry = unliked_entries[0];
    try std.testing.expectEqual(@as(i64, 0), unliked_entry.likes);
    try std.testing.expect(!unliked_entry.liked_by_this_user);

    try std.testing.expect(!try like(
        std.testing.io,
        arena.allocator(),
        &db,
        99,
        1,
    ));
    try std.testing.expect(!try unlike(
        arena.allocator(),
        &db,
        99,
        1,
    ));
}

test "hide and unhide return whether an entry exists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.deinit();

    try seedFlightLogListData(&db);

    try std.testing.expect(try hide(std.testing.io, &db, 1));
    const hidden_entries = try listAll(
        arena.allocator(),
        &db,
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), hidden_entries.len);
    try std.testing.expectEqual(@as(i64, 2), hidden_entries[0].id);

    try std.testing.expect(try unhide(&db, 1));
    const visible_entries = try listAll(
        arena.allocator(),
        &db,
        null,
    );
    try std.testing.expectEqual(@as(usize, 2), visible_entries.len);

    try std.testing.expect(!try hide(std.testing.io, &db, 99));
    try std.testing.expect(!try unhide(&db, 99));
}
