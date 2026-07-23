const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../../context.zig");

const flight_log_repository = @import("../../repositories/flight_log.zig");

const api_error = @import("../../http/api_error.zig");
const APIError = api_error.Error;

const request_user_http = @import("../../http/request_user.zig");

const response_http = @import("../../http/response.zig");

const flight_log_api = @import("../../api/flight_log.zig");
const FlightLogPatchRequest = flight_log_api.FlightLogPatchRequest;
const FlightLogActionResponse = flight_log_api.FlightLogActionResponse;

const FlightLogEndpoint = @import("dispatcher.zig");

pub const Params = struct {
    entry_id: i64,
};

const PatchAction = enum {
    delete,
    hide,
    unhide,
};

fn parseAction(request: FlightLogPatchRequest) APIError!PatchAction {
    if (request.is_deleted != null and request.is_hidden != null) {
        return APIError.APIInvalidRequest;
    }

    if (request.is_deleted) |is_deleted| {
        if (!is_deleted) {
            return APIError.APIInvalidRequest;
        }
        return .delete;
    }

    if (request.is_hidden) |is_hidden| {
        return if (is_hidden) .hide else .unhide;
    }

    return APIError.APIInvalidRequest;
}

pub fn patch(
    _: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
    params: Params,
) !void {
    r.parseCookies(false);

    const request_body = r.body orelse return APIError.APIInvalidRequest;
    const parsed = std.json.parseFromSlice(
        FlightLogPatchRequest,
        arena,
        request_body,
        .{},
    ) catch {
        return APIError.APIInvalidRequest;
    };

    const action = try parseAction(parsed.value);
    var success: bool = undefined;
    switch (action) {
        .delete => {
            const viewer_user_id = try request_user_http.requireUserIdOrCreateAnonymous(
                ctx.io,
                arena,
                &ctx.db,
                r,
            );

            success = try flight_log_repository.delete(
                ctx.io,
                &ctx.db,
                params.entry_id,
                viewer_user_id,
            );
        },
        .hide => {
            _ = try request_user_http.requireAdmin(
                arena,
                &ctx.db,
                r,
            );

            success = try flight_log_repository.hide(
                ctx.io,
                &ctx.db,
                params.entry_id,
            );
        },
        .unhide => {
            _ = try request_user_http.requireAdmin(
                arena,
                &ctx.db,
                r,
            );

            success = try flight_log_repository.unhide(
                &ctx.db,
                params.entry_id,
            );
        },
    }
    if (!success) {
        return APIError.APIFlightLogNotFound;
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
