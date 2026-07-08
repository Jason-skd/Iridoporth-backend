const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

pub fn setPasswordHash(io: std.Io, db: *Db, user_id: i64, password_hash: []const u8) !void {
    const now = std.Io.Timestamp.now(io, .real);
    const changed_at = now.toSeconds();

    const query = (
        \\INSERT INTO user_password_credentials (user_id, password_hash, changed_at)
        \\SELECT user_id, :password_hash{[]const u8}, :changed_at{i64}
        \\FROM users
        \\WHERE user_id = :user_id{i64}
        \\  AND kind = 'account'
        \\  AND disabled_at IS NULL
        \\ON CONFLICT(user_id) DO UPDATE SET
        \\  password_hash = excluded.password_hash,
        \\  changed_at = excluded.changed_at
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .password_hash = password_hash,
        .changed_at = changed_at,
        .user_id = user_id,
    });

    if (db.rowsAffected() == 0) {
        return error.UserNotFoundOrNotAccount;
    }
}

pub fn findPasswordHashByUserId(db: *Db, allocator: Allocator, user_id: i64) !?[]const u8 {
    const query = (
        \\SELECT password_hash
        \\FROM user_password_credentials
        \\WHERE user_id = :user_id{i64}
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    return try stmt.oneAlloc([]const u8, allocator, .{}, .{ .user_id = user_id });
}
