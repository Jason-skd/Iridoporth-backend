const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../context.zig");

const api_error = @import("../http/api_error.zig");
const APIError = api_error.Error;

const request_user_http = @import("../http/request_user.zig");

const response_http = @import("../http/response.zig");

const user_service = @import("../services/user.zig");

const account_api = @import("../api/account.zig");
const ChangePasswordRequest = account_api.ChangePasswordRequest;
const ChangePasswordResponse = account_api.ChangePasswordResponse;

const validation_domain = @import("../domain/validation.zig");

pub const AccountEndpoint = @This();

path: []const u8 = "/api/v1/account/password",
error_strategy: zap.Endpoint.ErrorStrategy = .raise,

pub fn put(
    _: *AccountEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    r.parseCookies(false);

    const user_id = (try request_user_http.getUserIdOrNull(
        arena,
        &ctx.db,
        r,
        ctx.production_mode,
    )) orelse return APIError.APIUnauthenticated;

    const request_body = r.body orelse return APIError.APIInvalidRequest;
    const parsed = std.json.parseFromSlice(
        ChangePasswordRequest,
        arena,
        request_body,
        .{},
    ) catch {
        return APIError.APIInvalidRequest;
    };
    switch (validation_domain.validatePassword(parsed.value.new_password)) {
        .ok => {},
        else => return APIError.APIInvalidRequest,
    }

    user_service.changePassword(
        ctx.io,
        arena,
        &ctx.db,
        user_id,
        parsed.value.current_password,
        parsed.value.new_password,
    ) catch |err| switch (err) {
        user_service.PasswordError.InvalidCurrent => return APIError.APIUnauthenticated,
        user_service.PasswordError.UserNotFound => return APIError.APIUserNotFound,
        else => return err,
    };

    const response: ChangePasswordResponse = .{ .data = .{} };
    try response_http.stringifyAndSendResponse(
        ChangePasswordResponse,
        arena,
        r,
        std.http.Status.ok,
        response,
    );
}
