const std = @import("std");

const zap = @import("zap");

const Context = @import("../context.zig");

const session_middleware = @import("../middleware/session.zig");
const SessionContext = session_middleware.SessionContext;

const flight_log_repository = @import("../repositories/flight_log.zig");

const flight_log_service = @import("../services/flight_log.zig");

const flight_log_api = @import("../api/flight_log.zig");
const FlightLogListResponse = flight_log_api.FlightLogListResponse;
const FlightLogPostRequest = flight_log_api.FlightLogPostRequest;
const FlightLogPostResponse = flight_log_api.FlightLogPostResponse;

const FlightLogEndpoint = @This();

path: []const u8 = "/api/v1/flight-log",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_console,

pub fn get(_: *FlightLogEndpoint, arena: std.mem.Allocator, ctx: *Context, r: zap.Request) !void {
    r.parseCookies(false);
    const viewer_user_id: ?i64 = try session_middleware.getUserIdOrNull(ctx, arena, r);

    r.setHeader("Content-Type", "application/json") catch {};

    const entries = try flight_log_service.listAll(arena, &ctx.db, viewer_user_id);

    const response = FlightLogListResponse{
        .ok = true,
        .data = .{
            .entries = entries,
        },
    };

    const body = try std.json.Stringify.valueAlloc(arena, response, .{});
    try r.sendBody(body);
}

pub fn post(_: *FlightLogEndpoint, arena: std.mem.Allocator, ctx: *Context, r: zap.Request) !void {
    r.parseCookies(false);
    const creator_user_id: i64 = try session_middleware.requireUserIdOrCreateAnonymous(ctx, arena, r);

    r.setHeader("Content-Type", "application/json") catch {};

    const request_body = r.body orelse return error.InvalidRequest;
    const parsed = try std.json.parseFromSlice(FlightLogPostRequest, arena, request_body, .{});

    const result = try flight_log_repository.insert(ctx.io, arena, &ctx.db, parsed.value.content, creator_user_id);

    const response = FlightLogPostResponse{
        .ok = true,
        .data = .{
            .id = result.id,
            .created_at = result.created_at,
        },
    };

    const reponse_body = try std.json.Stringify.valueAlloc(arena, response, .{});
    try r.sendBody(reponse_body);
}
