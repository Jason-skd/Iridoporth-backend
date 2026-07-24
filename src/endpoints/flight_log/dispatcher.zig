const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../../context.zig");

const api_error = @import("../../http/api_error.zig");
const APIError = api_error.Error;

const base_path_endpoint = @import("base_path.zig");

const admin_endpoint = @import("admin.zig");

const entry_endpoint = @import("entry.zig");

const entry_like_endpoint = @import("like.zig");

const FlightLogEndpoint = @This();

path: []const u8 = "/api/v1/flight-log",
error_strategy: zap.Endpoint.ErrorStrategy = .raise,

// GET /api/v1/flight-log => list visible flight log entries
// POST /api/v1/flight-log => create a new flight log entry

// PATCH /api/v1/flight-log/{id} => respond/clear_response/delete/hide/unhide a flight log entry
// by request like .{ .response = "..." } or .{ .clear_response = true } or .{ .is_hidden = true }

// POST /api/v1/flight-log/{id}/like => like a flight log entry
// DELETE /api/v1/flight-log/{id}/like => unlike a flight log entry

const Route = union(enum) {
    base: void,
    admin: void,
    entry: entry_endpoint.Params,
    entry_like: entry_like_endpoint.Params,
};

const RouteParseResult = union(enum) {
    matched: Route,
    not_found,
    invalid_entry_id,

    pub fn strip(self: RouteParseResult) !Route {
        return switch (self) {
            .matched => |route| route,
            .not_found => APIError.APINotFound,
            .invalid_entry_id => APIError.APIInvalidFlightLogEntryId,
        };
    }
};

fn parseRoute(self: *FlightLogEndpoint, path: ?[]const u8) RouteParseResult {
    const base = self.path;
    const path_received = path orelse return .not_found;

    if (std.mem.eql(u8, path_received, base)) {
        return .{ .matched = .base };
    }

    if (!std.mem.startsWith(u8, path_received, base)) {
        return .not_found;
    }

    if (path_received[base.len] != '/') {
        return .not_found;
    }

    const rest = path_received[base.len + 1 ..];

    var iterator = std.mem.splitScalar(u8, rest, '/');
    const first = iterator.next() orelse return .not_found;
    if (first.len == 0) {
        return .not_found;
    }

    if (std.mem.eql(u8, first, "admin")) {
        return if (iterator.peek() == null) .{ .matched = .admin } else .not_found;
    }

    const entry_id = std.fmt.parseInt(i64, first, 10) catch {
        return .invalid_entry_id;
    };

    if (iterator.next()) |second| {
        if (std.mem.eql(u8, second, "like") and iterator.peek() == null) {
            return .{ .matched = .{ .entry_like = .{ .entry_id = entry_id } } };
        }
        return .not_found;
    }

    return .{ .matched = .{ .entry = .{ .entry_id = entry_id } } };
}

pub fn get(
    self: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    const route = try parseRoute(self, r.path).strip();
    return switch (route) {
        .base => base_path_endpoint.get(self, arena, ctx, r),
        .admin => admin_endpoint.get(self, arena, ctx, r),
        else => APIError.APINotFound,
    };
}

pub fn post(
    self: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    const route = try parseRoute(self, r.path).strip();
    return switch (route) {
        .base => base_path_endpoint.post(self, arena, ctx, r),
        .entry_like => |params| entry_like_endpoint.post(
            self,
            arena,
            ctx,
            r,
            params,
        ),
        else => APIError.APINotFound,
    };
}

pub fn patch(
    self: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    const route = try parseRoute(self, r.path).strip();
    return switch (route) {
        .entry => |params| entry_endpoint.patch(
            self,
            arena,
            ctx,
            r,
            params,
        ),
        else => APIError.APINotFound,
    };
}

pub fn delete(
    self: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    const route = try parseRoute(self, r.path).strip();
    return switch (route) {
        .entry_like => |params| entry_like_endpoint.delete(
            self,
            arena,
            ctx,
            r,
            params,
        ),
        else => APIError.APINotFound,
    };
}

test "parseRoute split the path and dispatch" {
    const cases = [_]struct {
        name: []const u8,
        path: ?[]const u8,
        expected: RouteParseResult,
    }{ .{
        .name = "base path",
        .path = "/api/v1/flight-log",
        .expected = .{ .matched = .base },
    }, .{
        .name = "entry path",
        .path = "/api/v1/flight-log/31",
        .expected = .{ .matched = .{ .entry = .{ .entry_id = 31 } } },
    }, .{
        .name = "like path",
        .path = "/api/v1/flight-log/11/like",
        .expected = .{ .matched = .{ .entry_like = .{ .entry_id = 11 } } },
    }, .{
        .name = "not this base",
        .path = "/api/v1/flight-log-foo",
        .expected = .not_found,
    }, .{
        .name = "short path",
        .path = "/api/v1/flight",
        .expected = .not_found,
    }, .{
        .name = "missing path",
        .path = null,
        .expected = .not_found,
    }, .{
        .name = "admin path",
        .path = "/api/v1/flight-log/admin",
        .expected = .{ .matched = .admin },
    }, .{
        .name = "admin path with extra segment is not_found",
        .path = "/api/v1/flight-log/admin/extra",
        .expected = .not_found,
    }, .{
        .name = "invalid id",
        .path = "/api/v1/flight-log/like",
        .expected = .invalid_entry_id,
    } };

    var endpoint = FlightLogEndpoint{};

    for (cases) |case| {
        const result = endpoint.parseRoute(case.path);

        try std.testing.expectEqualDeep(case.expected, result);
    }
}
