const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const Context = @import("../context.zig");

const user_session_domain = @import("../domain/user_session.zig");
const SessionTokenRandomHex = user_session_domain.SessionTokenRandomHex;

const user_repository = @import("../repositories/user.zig");

const user_session_repository = @import("../repositories/user_session.zig");

pub const SessionContext = struct {
    user_id: i64,
    new_session_token: ?SessionTokenRandomHex,
};

pub fn requireOrCreateAnonymous(ctx: *Context, allocator: Allocator, r: zap.Request) !SessionContext {
    const token: []const u8 = (try r.getCookieStr(allocator, "iridoporth_session")) orelse return createAnonymousSession(ctx.io, allocator, &ctx.db);
    const user_id = try findUserId(allocator, &ctx.db, token);
    return .{
        .user_id = user_id,
        .new_session_token = null,
    };
}

pub fn getUserIdOrNull(ctx: *Context, allocator: Allocator, r: zap.Request) !?i64 {
    const token: []const u8 = (try r.getCookieStr(allocator, "iridoporth_session")) orelse return null;
    const user_id = try findUserId(allocator, &ctx.db, token);
    return user_id;
}

fn createAnonymousSession(io: std.Io, allocator: Allocator, db: *Db) !SessionContext {
    const new_user = try user_repository.createAnonymousUser(io, allocator, db);
    const user_id = new_user.id;

    const new_session_token = try user_session_domain.generateSessionToken(io);
    const token_hash = user_session_domain.hashSessionToken(new_session_token[0..]);

    const now = std.Io.Timestamp.now(io, .real);
    const expires_at = now.toSeconds() + (60 * 60 * 24 * 91); // 91 days from now
    _ = try user_session_repository.createSession(io, db, allocator, user_id, .anonymous_cookie, token_hash[0..], expires_at);

    return .{
        .user_id = user_id,
        .new_session_token = new_session_token,
    };
}

fn findUserId(allocator: Allocator, db: *Db, token: []const u8) !i64 {
    const token_hash = user_session_domain.hashSessionToken(token);

    const session = try (user_session_repository.findUserSessionByTokenHash(db, allocator, token_hash[0..])) orelse return error.InvalidSessionToken;
    return session.user_id;
}
