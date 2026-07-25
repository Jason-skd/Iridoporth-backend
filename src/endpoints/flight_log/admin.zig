const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../../context.zig");

const request_user_http = @import("../../http/request_user.zig");

const response_http = @import("../../http/response.zig");

const flight_log_service = @import("../../services/flight_log.zig");

const flight_log_api = @import("../../api/flight_log.zig");
const FlightLogAdminListResponse = flight_log_api.FlightLogAdminListResponse;

const FlightLogEndpoint = @import("dispatcher.zig");

pub fn get(
    _: *FlightLogEndpoint,
    arena: std.mem.Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    r.parseCookies(false);
    const admin_user_id = try request_user_http.requireAdmin(
        arena,
        &ctx.db,
        r,
        ctx.production_mode,
    );

    const entries = try flight_log_service.listAllForAdmin(
        arena,
        &ctx.db,
        admin_user_id,
    );

    const response = FlightLogAdminListResponse{
        .data = .{
            .entries = entries,
        },
    };

    try response_http.stringifyAndSendResponse(
        FlightLogAdminListResponse,
        arena,
        r,
        std.http.Status.ok,
        response,
    );
}
