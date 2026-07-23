const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../../context.zig");

const flight_log_repository = @import("../../repositories/flight_log.zig");

const request_user_http = @import("../../http/request_user.zig");

const api_error = @import("../../http/api_error.zig");
const APIError = api_error.Error;

const response_http = @import("../../http/response.zig");

const flight_log_api = @import("../../api/flight_log.zig");
const FlightLogActionResponse = flight_log_api.FlightLogActionResponse;

const FlightLogEndpoint = @import("dispatcher.zig");

pub const Params = struct {
    entry_id: i64,
};

pub fn post(
    _: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
    params: Params,
) !void {
    r.parseCookies(false);
    const viewer_user_id: i64 = try request_user_http.requireUserIdOrCreateAnonymous(
        ctx.io,
        arena,
        &ctx.db,
        r,
    );

    const success = try flight_log_repository.like(
        ctx.io,
        ctx.allocator,
        &ctx.db,
        params.entry_id,
        viewer_user_id,
    );
    if (!success) {
        return APIError.ApiFlightLogNotFound;
    }

    const response = FlightLogActionResponse{
        .data = .{},
    };

    try response_http.stringifyAndSendResponse(
        FlightLogActionResponse,
        arena,
        r,
        std.http.Status.ok,
        response,
    );
}

pub fn delete(
    _: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
    params: Params,
) !void {
    r.parseCookies(false);
    const viewer_user_id: i64 = try request_user_http.requireUserIdOrCreateAnonymous(
        ctx.io,
        arena,
        &ctx.db,
        r,
    );

    const success = try flight_log_repository.unlike(
        ctx.allocator,
        &ctx.db,
        params.entry_id,
        viewer_user_id,
    );
    if (!success) {
        return APIError.ApiFlightLogNotFound;
    }

    const response = FlightLogActionResponse{
        .data = .{},
    };

    try response_http.stringifyAndSendResponse(
        FlightLogActionResponse,
        arena,
        r,
        std.http.Status.ok,
        response,
    );
}
