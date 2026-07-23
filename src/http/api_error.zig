const std = @import("std");

pub const Error = error{
    APIInvalidRequest,
    APINotFound,
    APIUnauthenticated,
    APIForbidden,
    APIInvalidFlightLogEntryId,
    APIFlightLogNotFound,
};

pub const PublicError = struct {
    status: std.http.Status,
    code: []const u8,
};

pub fn classify(err: anyerror) ?PublicError {
    return switch (err) {
        error.APIInvalidRequest => .{
            .status = .bad_request,
            .code = "invalid_request",
        },
        error.APINotFound => not_found,
        error.APIUnauthenticated => .{
            .status = .unauthorized,
            .code = "unauthenticated",
        },
        error.APIForbidden => .{
            .status = .forbidden,
            .code = "forbidden",
        },
        error.APIInvalidFlightLogEntryId => .{
            .status = .bad_request,
            .code = "invalid_flight_log_entry_id",
        },
        error.APIFlightLogNotFound => .{
            .status = .not_found,
            .code = "flight_log_not_found",
        },
        else => null,
    };
}

pub const not_found = PublicError{
    .status = .not_found,
    .code = "not_found",
};

pub const internal_error = PublicError{
    .status = .internal_server_error,
    .code = "internal_error",
};
