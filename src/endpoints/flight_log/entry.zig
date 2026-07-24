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

const validation_domain = @import("../../domain/validation.zig");

const FlightLogEndpoint = @import("dispatcher.zig");

pub const Params = struct {
    entry_id: i64,
};

const PatchAction = enum {
    delete,
    hide,
    unhide,
    respond,
    clear_response,
};

fn parseAction(request: FlightLogPatchRequest) APIError!PatchAction {
    var active_count: u2 = 0;

    if (request.is_deleted != null) active_count += 1;
    if (request.is_hidden != null) active_count += 1;
    if (request.response != null) active_count += 1;
    if (request.clear_response == true) active_count += 1;

    if (active_count != 1) {
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

    if (request.response != null) {
        return .respond;
    }

    if (request.clear_response == true) {
        return .clear_response;
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
        .respond => {
            _ = try request_user_http.requireAdmin(
                arena,
                &ctx.db,
                r,
            );

            const content = switch (validation_domain.sanitizeContent(
                parsed.value.response.?,
            )) {
                .ok => |trimmed| trimmed,
                else => return APIError.APIInvalidRequest,
            };

            success = try flight_log_repository.respond(
                ctx.io,
                &ctx.db,
                params.entry_id,
                content,
            );
        },
        .clear_response => {
            _ = try request_user_http.requireAdmin(
                arena,
                &ctx.db,
                r,
            );

            success = try flight_log_repository.clearResponse(
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

test "parseAction recognizes each single action" {
    try std.testing.expectEqual(
        PatchAction.respond,
        try parseAction(.{ .is_deleted = null, .is_hidden = null, .response = "x", .clear_response = null }),
    );
    try std.testing.expectEqual(
        PatchAction.clear_response,
        try parseAction(.{ .is_deleted = null, .is_hidden = null, .response = null, .clear_response = true }),
    );
    try std.testing.expectEqual(
        PatchAction.delete,
        try parseAction(.{ .is_deleted = true, .is_hidden = null, .response = null, .clear_response = null }),
    );
    try std.testing.expectEqual(
        PatchAction.hide,
        try parseAction(.{ .is_deleted = null, .is_hidden = true, .response = null, .clear_response = null }),
    );
    try std.testing.expectEqual(
        PatchAction.unhide,
        try parseAction(.{ .is_deleted = null, .is_hidden = false, .response = null, .clear_response = null }),
    );
}

test "parseAction rejects zero or multiple action fields" {
    const empty: FlightLogPatchRequest = .{
        .is_deleted = null,
        .is_hidden = null,
        .response = null,
        .clear_response = null,
    };
    try std.testing.expectError(
        APIError.APIInvalidRequest,
        parseAction(empty),
    );

    try std.testing.expectError(
        APIError.APIInvalidRequest,
        parseAction(.{ .is_deleted = true, .is_hidden = true, .response = null, .clear_response = null }),
    );

    try std.testing.expectError(
        APIError.APIInvalidRequest,
        parseAction(.{ .is_deleted = null, .is_hidden = null, .response = "x", .clear_response = true }),
    );

    try std.testing.expectError(
        APIError.APIInvalidRequest,
        parseAction(.{ .is_deleted = null, .is_hidden = true, .response = "x", .clear_response = null }),
    );

    try std.testing.expectError(
        APIError.APIInvalidRequest,
        parseAction(.{ .is_deleted = true, .is_hidden = null, .response = "x", .clear_response = null }),
    );
}

test "parseAction rejects is_deleted false" {
    try std.testing.expectError(
        APIError.APIInvalidRequest,
        parseAction(.{ .is_deleted = false, .is_hidden = null, .response = null, .clear_response = null }),
    );
}

test "parseAction treats clear_response null and false as no action" {
    try std.testing.expectEqual(
        PatchAction.respond,
        try parseAction(.{ .is_deleted = null, .is_hidden = null, .response = "x", .clear_response = null }),
    );
    try std.testing.expectEqual(
        PatchAction.respond,
        try parseAction(.{ .is_deleted = null, .is_hidden = null, .response = "x", .clear_response = false }),
    );
}
