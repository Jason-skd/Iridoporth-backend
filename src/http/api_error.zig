const std = @import("std");

pub const Error = error{
    ApiInvalidRequest,
    ApiInvalidFlightLogEntryId,
    ApiUnauthenticated,
    ApiForbidden,
    ApiFlightLogNotFound,
};

pub const PublicError = struct {
    status: std.http.Status,
    code: []const u8,
};

pub fn classify(err: anyerror) ?PublicError {
    return switch (err) {
        error.ApiInvalidRequest => .{
            .status = .bad_request,
            .code = "invalid_request",
        },
        error.ApiInvalidFlightLogEntryId => .{
            .status = .bad_request,
            .code = "invalid_flight_log_entry_id",
        },
        error.ApiUnauthenticated => .{
            .status = .unauthorized,
            .code = "unauthenticated",
        },
        error.ApiForbidden => .{
            .status = .forbidden,
            .code = "forbidden",
        },
        error.ApiFlightLogNotFound => .{
            .status = .not_found,
            .code = "flight_log_not_found",
        },
        else => null,
    };
}
