const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../context.zig");

const request_user_http = @import("../http/request_user.zig");

const response_http = @import("../http/response.zig");

const login_service = @import("../services/login.zig");

const login_api = @import("../api/login.zig");
const LoginRequest = login_api.LoginRequest;
const LoginResponse = login_api.LoginResponse;

pub const LoginEndpoint = @This();

path: []const u8 = "/login",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_console,

pub fn post(
    _: *LoginEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.request,
) !void {
    r.setHeader("Content-Type", "application/json") catch {};

    const request_body = r.body orelse return error.InvalidRequest;
    const parsed = try std.json.parseFromSlice(
        LoginRequest,
        arena,
        request_body,
        .{},
    );

    const login_result = try login_service.login(
        &ctx.io,
        arena,
        &ctx.db,
        parsed.value.email,
        parsed.value.password,
    );

    const response: LoginResponse = switch (login_result) {
        .success => |user_id| blk: {
            try request_user_http.setSessionForAccount(
                ctx.io,
                arena,
                r,
                user_id,
            );
            break :blk LoginResponse{
                .ok = true,
                .data = .{
                    .success = true,
                    .session_token = r.getCookie("session_token"),
                },
            };
        },
        .failure => .{
            .ok = true,
            .data = .{
                .success = false,
                .session_token = null,
            },
        },
    };

    try response_http.stringifyAndSendResponse(
        LoginResponse,
        arena,
        r,
        response,
    );
}
