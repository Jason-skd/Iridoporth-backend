const std = @import("std");

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const Allocator = std.mem.Allocator;

const current_schema_version = 2;

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

        try migrateToV1(db);
        _ = try db.pragma(void, .{}, "user_version", "1");

        try db.exec("COMMIT", .{}, .{});
    }

    if (version < 2) {
        try db.exec("BEGIN IMMEDIATE", .{}, .{});
        errdefer db.exec("ROLLBACK", .{}, .{}) catch {};

        try migrateToV2(db);
        _ = try db.pragma(void, .{}, "user_version", "2");

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

fn migrateToV2(db: *sqlite.Db) !void {
    try db.execMulti(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  kind TEXT NOT NULL CHECK (kind IN ('anonymous', 'account')),
        \\  role TEXT NOT NULL CHECK (role IN ('admin', 'user')),
        \\  name TEXT,
        \\  email TEXT,
        \\  created_at INTEGER NOT NULL,
        \\  updated_at INTEGER NOT NULL,
        \\  last_seen_at INTEGER NOT NULL,
        \\  disabled_at INTEGER
        \\
        \\  CHECK (
        \\      (kind = 'anonymous' AND name IS NULL AND email IS NULL)
        \\      OR
        \\      (kind = 'account' AND name IS NOT NULL AND email IS NOT NULL)
        \\  )
        \\);
        \\
        \\CREATE UNIQUE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;
    , .{});
    try db.execMulti(
        \\CREATE TABLE IF NOT EXISTS user_password_credentials (
        \\  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        \\  password_hash TEXT
        \\  changed_at INTEGER NOT NULL
        \\);
    , .{});
    try db.execMulti(
        \\CREATE TABLE IF NOT EXISTS user_sessions (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        \\  method TEXT NOT NULL CHECK (method IN ('anonymous_cookie', 'password_login')),
        \\  token_hash TEXT NOT NULL,
        \\  created_at INTEGER NOT NULL,
        \\  expires_at INTEGER NOT NULL,
        \\  last_used_at INTEGER NOT NULL,
        \\  revoked_at INTEGER
        \\);
        \\
        \\CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
        \\CREATE INDEX idx_user_sessions_token_hash ON user_sessions(token_hash);
    , .{});
}
