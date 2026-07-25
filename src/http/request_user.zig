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

const user_domain = @import("../domain/user.zig");
const User = user_domain.User;
const UserRole = user_domain.Role;

const user_repository = @import("../repositories/user.zig");

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
    production_mode: bool,
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

    return createAnonymousUserIdAndSetSession(io, allocator, db, r, production_mode);
}

pub fn getUserIdOrNull(
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
    production_mode: bool,
) !?i64 {
    const token: []const u8 = try r.getCookieStr(
        allocator,
        session_cookie_name,
    ) orelse return null;

    const user_id = try user_session_service.findUserId(
        allocator,
        db,
        token,
    ) orelse {
        try clearSessionToken(r, production_mode);
        return null;
    };

    return user_id;
}

pub fn requireAdmin(
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
    production_mode: bool,
) !i64 {
    const token: []const u8 = (try r.getCookieStr(
        allocator,
        session_cookie_name,
    )) orelse return APIError.APIUnauthenticated;

    const user_id = (try user_session_service.findUserId(
        allocator,
        db,
        token,
    )) orelse {
        try clearSessionToken(r, production_mode);
        return APIError.APIUnauthenticated;
    };

    const is_admin = user_service.isAdmin(
        allocator,
        db,
        user_id,
    ) catch |err| switch (err) {
        user_service.AuthorizationError.UserNotFound => {
            try clearSessionToken(r, production_mode);
            return APIError.APIUserNotFound;
        },
        else => return err,
    };

    if (!is_admin) {
        return APIError.APIForbidden;
    }

    return user_id;
}

pub const AccountSession = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    role: UserRole,

    pub fn fromUser(user: User) ?AccountSession {
        return switch (user.kind) {
            .anonymous => null,
            .account => |acct| .{
                .id = user.id,
                .name = acct.name,
                .email = acct.email,
                .role = user.role,
            },
        };
    }
};

pub fn requireAccount(
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
    production_mode: bool,
) !AccountSession {
    const token: []const u8 = (try r.getCookieStr(
        allocator,
        session_cookie_name,
    )) orelse return APIError.APIUnauthenticated;

    const user_id = (try user_session_service.findUserId(
        allocator,
        db,
        token,
    )) orelse {
        try clearSessionToken(r, production_mode);
        return APIError.APIUnauthenticated;
    };

    const user = (try user_repository.findUserById(
        allocator,
        db,
        user_id,
    )) orelse {
        try clearSessionToken(r, production_mode);
        return APIError.APIUserNotFound;
    };

    return AccountSession.fromUser(user) orelse return APIError.APIForbidden;
}

pub fn setSessionForAccount(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
    user_id: i64,
    production_mode: bool,
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
        production_mode,
    );
}

pub fn clearSessionToken(r: zap.Request, production_mode: bool) !void {
    try r.setCookie(.{
        .name = session_cookie_name,
        .value = "",
        .path = "/",
        .max_age_s = 0,
        .http_only = true,
        .secure = production_mode,
        .same_site = if (production_mode) .Strict else .Lax,
    });
}

fn setSessionToken(
    r: zap.Request,
    new_token: SessionTokenRandomHex,
    max_age_s: i32,
    production_mode: bool,
) !void {
    try r.setCookie(.{
        .name = session_cookie_name,
        .value = new_token[0..],
        .path = "/",
        .max_age_s = max_age_s,
        .http_only = true,
        .secure = production_mode,
        .same_site = if (production_mode) .Strict else .Lax,
    });
}

fn createAnonymousUserIdAndSetSession(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
    production_mode: bool,
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
        production_mode,
    );
    return session_context.user_id;
}

test "AccountSession.fromUser projects an account user" {
    const user: User = .{
        .id = 42,
        .kind = .{ .account = .{ .email = "a@b.com", .name = "Alice" } },
        .role = .admin,
        .created_at = 0,
        .updated_at = 0,
        .last_seen_at = 0,
        .disabled_at = null,
    };
    const acct = AccountSession.fromUser(user) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i64, 42), acct.id);
    try std.testing.expectEqualStrings("a@b.com", acct.email);
    try std.testing.expectEqualStrings("Alice", acct.name);
    try std.testing.expect(acct.role == .admin);
}

test "AccountSession.fromUser returns null for an anonymous user" {
    const user: User = .{
        .id = 7,
        .kind = .anonymous,
        .role = .user,
        .created_at = 0,
        .updated_at = 0,
        .last_seen_at = 0,
        .disabled_at = null,
    };
    try std.testing.expect(AccountSession.fromUser(user) == null);
}
