const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const Context = @import("../context.zig");

const user_session_domain = @import("../domain/user_session.zig");
const SessionTokenRandomHex = user_session_domain.SessionTokenRandomHex;

const user_session_service = @import("../services/user_session.zig");

const user_service = @import("../services/user.zig");

const api_error = @import("./api_error.zig");
const APIError = api_error.Error;

const session_cookie_name = "session_token";
const cookie_session_max_age_s = 60 * 60 * 24 * 91; // 91 days, a season
const password_session_max_age_s = 60 * 60 * 24; // 1 day

pub fn requireUserIdOrCreateAnonymous(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
) !i64 {
    const token_cookie: ?[]const u8 = try r.getCookieStr(allocator, session_cookie_name);

    if (token_cookie) |token| {
        if (try user_session_service.findUserId(
            allocator,
            db,
            token,
        )) |user_id| {
            return user_id;
        }
    }

    return createAnonymousUserIdAndSetSession(io, allocator, db, r);
}

pub fn getUserIdOrNull(allocator: Allocator, db: *Db, r: zap.Request) !?i64 {
    const token: []const u8 = try r.getCookieStr(
        allocator,
        session_cookie_name,
    ) orelse return null;

    const user_id = try user_session_service.findUserId(
        allocator,
        db,
        token,
    ) orelse {
        try clearSessionToken(r);
        return null;
    };

    return user_id;
}

pub fn requireAdmin(allocator: Allocator, db: *Db, r: zap.Request) !i64 {
    const token: []const u8 = (try r.getCookieStr(
        allocator,
        session_cookie_name,
    )) orelse return APIError.APIUnauthenticated;

    const user_id = (try user_session_service.findUserId(
        allocator,
        db,
        token,
    )) orelse {
        try clearSessionToken(r);
        return APIError.APIUnauthenticated;
    };

    const is_admin = user_service.isAdmin(
        allocator,
        db,
        user_id,
    ) catch |err| switch (err) {
        user_service.AuthorizationError.UserNotFound => {
            try clearSessionToken(r);
            return APIError.APIUserNotFound;
        },
        else => return err,
    };

    if (!is_admin) {
        return APIError.APIForbidden;
    }

    return user_id;
}

pub fn setSessionForAccount(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
    user_id: i64,
) !void {
    const new_session_token = try user_session_service.createSession(
        io,
        allocator,
        db,
        user_id,
        .password_login,
        password_session_max_age_s,
    );
    try setSessionToken(
        r,
        new_session_token,
        password_session_max_age_s,
    );
}

pub fn clearSessionToken(r: zap.Request) !void {
    try r.setCookie(.{
        .name = session_cookie_name,
        .value = "",
        .path = "/",
        .max_age_s = 0,
        .http_only = true,
        .secure = false, // TODO: set to true in production
        .same_site = .Lax, // TODO: set to .Strict in production
    });
}

fn setSessionToken(r: zap.Request, new_token: SessionTokenRandomHex, max_age_s: i32) !void {
    try r.setCookie(.{
        .name = session_cookie_name,
        .value = new_token[0..],
        .path = "/",
        .max_age_s = max_age_s,
        .http_only = true,
        .secure = false, // TODO: set to true in production
        .same_site = .Lax, // TODO: set to .Strict in production
    });
}

fn createAnonymousUserIdAndSetSession(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
) !i64 {
    const session_context = try user_session_service.createAnonymousSession(
        io,
        allocator,
        db,
        cookie_session_max_age_s,
    );
    try setSessionToken(
        r,
        session_context.new_session_token,
        cookie_session_max_age_s,
    );
    return session_context.user_id;
}
