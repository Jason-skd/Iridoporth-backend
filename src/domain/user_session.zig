const std = @import("std");
const Allocator = std.mem.Allocator;

const session_token_random_bytes_len = 32;
pub const SessionTokenRandomHex: type = [session_token_random_bytes_len * 2]u8;

const session_token_hash_bytes_len = std.crypto.hash.sha2.Sha256.digest_length;
pub const SessionTokenHashHex: type = [session_token_hash_bytes_len * 2]u8;

pub const UserSession = struct {
    id: i64,
    user_id: i64,
    method: Method,
    created_at: i64,
    expires_at: i64,
    last_used_at: i64,
    revoked_at: ?i64,
};

pub const UserSessionDraft = struct {
    user_id: i64,
    method: Method,
    token_hash: []const u8,
    created_at: i64,
    expires_at: i64,
    last_used_at: i64,
    revoked_at: ?i64,

    pub fn init(user_id: i64, method: Method, token_hash: []const u8, now: i64, expires_at: i64) UserSessionDraft {
        return .{
            .user_id = user_id,
            .method = method,
            .token_hash = token_hash,
            .created_at = now,
            .expires_at = expires_at,
            .last_used_at = now,
            .revoked_at = null,
        };
    }
};

pub const Method = enum {
    anonymous_cookie,
    password_login,

    const BaseType = []const u8;
    const default = .anonymous_cookie;
};

pub fn generateSessionToken(io: std.Io) std.Io.RandomSecureError!SessionTokenRandomHex {
    var random_bytes: [session_token_random_bytes_len]u8 = undefined;
    try io.randomSecure(&random_bytes);

    return std.fmt.bytesToHex(random_bytes, .lower);
}

pub fn hashSessionToken(token: []const u8) SessionTokenHashHex {
    var digest: [session_token_hash_bytes_len]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &digest, .{});

    return std.fmt.bytesToHex(digest, .lower);
}
