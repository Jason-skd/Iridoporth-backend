const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const user_session_domain = @import("../domain/user_session.zig");
const SessionMethod = user_session_domain.Method;
const SessionTokenRandomHex = user_session_domain.SessionTokenRandomHex;

const user_repository = @import("../repositories/user.zig");

const user_session_repository = @import("../repositories/user_session.zig");

const SessionContext = struct {
    user_id: i64,
    new_session_token: SessionTokenRandomHex,
};

pub fn createAnonymousSession(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    max_age_s: i32,
) !SessionContext {
    const new_user = try user_repository.createAnonymousUser(
        io,
        allocator,
        db,
    );
    const user_id = new_user.id;

    const new_session_token = try createSession(
        io,
        allocator,
        db,
        user_id,
        .anonymous_cookie,
        max_age_s,
    );

    return .{
        .user_id = user_id,
        .new_session_token = new_session_token,
    };
}

pub fn createSession(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    user_id: i64,
    method: SessionMethod,
    max_age_s: i32,
) !SessionTokenRandomHex {
    const new_session_token = try user_session_domain.generateSessionToken(io);
    const token_hash = user_session_domain.hashSessionToken(new_session_token[0..]);

    const now = std.Io.Timestamp.now(io, .real);
    const expires_at = now.toSeconds() + max_age_s;
    _ = try user_session_repository.createSession(
        io,
        db,
        allocator,
        user_id,
        method,
        token_hash[0..],
        expires_at,
    );

    return new_session_token;
}

pub fn findUserId(allocator: Allocator, db: *Db, token: []const u8) !?i64 {
    const token_hash = user_session_domain.hashSessionToken(token);

    const session = try (user_session_repository.findUserSessionByTokenHash(
        db,
        allocator,
        token_hash[0..],
    )) orelse return null;
    return session.user_id;
}
