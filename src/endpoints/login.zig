const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../context.zig");

const api_error = @import("../http/api_error.zig");
const APIError = api_error.Error;

const request_user_http = @import("../http/request_user.zig");

const response_http = @import("../http/response.zig");

const login_service = @import("../services/login.zig");

const login_api = @import("../api/login.zig");
const LoginRequest = login_api.LoginRequest;
const LoginResponse = login_api.LoginResponse;

pub const LoginEndpoint = @This();

path: []const u8 = "/login",
error_strategy: zap.Endpoint.ErrorStrategy = .raise,

pub fn post(
    _: *LoginEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    const request_body = r.body orelse return APIError.APIInvalidRequest;
    const parsed = std.json.parseFromSlice(
        LoginRequest,
        arena,
        request_body,
        .{},
    ) catch {
        return APIError.APIInvalidRequest;
    };

    const login_result = try login_service.login(
        ctx.io,
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
                &ctx.db,
                r,
                user_id,
            );
            break :blk LoginResponse{
                .ok = true,
                .data = .{
                    .success = true,
                },
            };
        },
        .failure => .{
            .ok = true,
            .data = .{
                .success = false,
            },
        },
    };

    try response_http.stringifyAndSendResponse(
        LoginResponse,
        arena,
        r,
        std.http.Status.ok,
        response,
    );
}
