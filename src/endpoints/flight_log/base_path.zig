const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../../context.zig");

const api_error = @import("../../http/api_error.zig");
const APIError = api_error.Error;

const request_user_http = @import("../../http/request_user.zig");

const response_http = @import("../../http/response.zig");

const flight_log_repository = @import("../../repositories/flight_log.zig");

const flight_log_service = @import("../../services/flight_log.zig");

const flight_log_api = @import("../../api/flight_log.zig");
const FlightLogListResponse = flight_log_api.FlightLogListResponse;
const FlightLogPostRequest = flight_log_api.FlightLogPostRequest;
const FlightLogPostResponse = flight_log_api.FlightLogPostResponse;

const validation_domain = @import("../../domain/validation.zig");

const FlightLogEndpoint = @import("dispatcher.zig");

pub fn get(
    _: *FlightLogEndpoint,
    arena: std.mem.Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    r.parseCookies(false);
    const viewer_user_id: ?i64 = try request_user_http.getUserIdOrNull(
        arena,
        &ctx.db,
        r,
        ctx.production_mode,
    );

    const entries = try flight_log_service.listAll(
        arena,
        &ctx.db,
        viewer_user_id,
    );

    const response = FlightLogListResponse{
        .ok = true,
        .data = .{
            .entries = entries,
        },
    };

    try response_http.stringifyAndSendResponse(
        FlightLogListResponse,
        arena,
        r,
        std.http.Status.ok,
        response,
    );
}

pub fn post(
    _: *FlightLogEndpoint,
    arena: std.mem.Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    r.parseCookies(false);

    const request_body = r.body orelse return APIError.APIInvalidRequest;
    const parsed = std.json.parseFromSlice(
        FlightLogPostRequest,
        arena,
        request_body,
        .{},
    ) catch {
        return APIError.APIInvalidRequest;
    };

    const creator_user_id: i64 = try request_user_http.requireUserIdOrCreateAnonymous(
        ctx.io,
        arena,
        &ctx.db,
        r,
        ctx.production_mode,
    );

    const content = switch (validation_domain.sanitizeContent(parsed.value.content)) {
        .ok => |trimmed| trimmed,
        else => return APIError.APIInvalidRequest,
    };

    const result = try flight_log_repository.insert(
        ctx.io,
        arena,
        &ctx.db,
        content,
        creator_user_id,
    );

    const response = FlightLogPostResponse{
        .ok = true,
        .data = .{
            .id = result.id,
            .created_at = result.created_at,
        },
    };

    try response_http.stringifyAndSendResponse(
        FlightLogPostResponse,
        arena,
        r,
        std.http.Status.ok,
        response,
    );
}
