const sqlite = @import("sqlite");
const Db = sqlite.Db;

pub fn migrateToV1(db: *Db) !void {
    try db.execMulti(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  user_id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  kind TEXT NOT NULL CHECK (kind IN ('anonymous', 'account')),
        \\  role TEXT NOT NULL CHECK (role IN ('admin', 'user')),
        \\  name TEXT,
        \\  email TEXT,
        \\  created_at INTEGER NOT NULL,
        \\  updated_at INTEGER NOT NULL,
        \\  last_seen_at INTEGER NOT NULL,
        \\  disabled_at INTEGER,
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
        \\  user_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
        \\  password_hash TEXT NOT NULL,
        \\  changed_at INTEGER NOT NULL
        \\);
    , .{});
    try db.execMulti(
        \\CREATE TABLE IF NOT EXISTS user_sessions (
        \\  session_id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
        \\  method TEXT NOT NULL CHECK (method IN ('anonymous_cookie', 'password_login')),
        \\  token_hash TEXT NOT NULL ,
        \\  created_at INTEGER NOT NULL,
        \\  expires_at INTEGER NOT NULL,
        \\  last_used_at INTEGER NOT NULL,
        \\  revoked_at INTEGER
        \\);
        \\
        \\CREATE UNIQUE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
        \\CREATE UNIQUE INDEX idx_user_sessions_token_hash ON user_sessions(token_hash);
    , .{});
    try db.execMulti(
        \\CREATE TABLE IF NOT EXISTS flight_log_entries (
        \\  entry_id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  content TEXT NOT NULL,
        \\  response TEXT,
        \\  responded_at INTEGER,
        \\  creator_user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
        \\  created_at INTEGER NOT NULL,
        \\  deleted_at INTEGER,
        \\  hidden_at INTEGER
        \\);
    , .{});
    try db.execMulti(
        \\CREATE TABLE IF NOT EXISTS flight_log_entry_likes (
        \\  entry_id INTEGER NOT NULL REFERENCES flight_log_entries(entry_id) ON DELETE CASCADE,
        \\  user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
        \\  created_at INTEGER NOT NULL,
        \\
        \\  PRIMARY KEY (entry_id, user_id)
        \\);
        \\
        \\CREATE INDEX idx_flight_log_entry_likes_user_id ON flight_log_entry_likes(user_id);
    , .{});
}
