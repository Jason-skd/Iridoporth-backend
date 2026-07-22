const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../../context.zig");

const base_path_endpoint = @import("base_path.zig");

const entry_endpoint = @import("entry.zig");

const entry_like_endpoint = @import("like.zig");

const FlightLogEndpoint = @This();

path: []const u8 = "/api/v1/flight-log",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_console,

// GET /api/v1/flight-log => list visible flight log entries
// POST /api/v1/flight-log => create a new flight log entry

// PATCH /api/v1/flight-log/{id} => respond/delete/hide/unhide(not implemented yet) a flight log entry
// by request like .{ .is_hidden = true }

// POST /api/v1/flight-log/{id}/like => like a flight log entry
// DELETE /api/v1/flight-log/{id}/like => unlike a flight log entry

const Route = union(enum) {
    base: void,
    entry: entry_endpoint.Params,
    entry_like: entry_like_endpoint.Params,
};

fn parseRoute(self: *FlightLogEndpoint, path: ?[]const u8) !Route {
    const base = self.path;
    const path_received = path orelse return error.NotFound;

    if (std.mem.eql(u8, path_received, base)) {
        return .base;
    }

    if (!std.mem.startsWith(u8, path_received, base)) {
        return error.NotFound;
    }

    if (path_received[base.len] != '/') {
        return error.NotFound;
    }

    const rest = path_received[base.len + 1 ..];

    var iterator = std.mem.splitScalar(u8, rest, '/');
    const first = iterator.next() orelse return error.NotFound;
    if (first.len == 0) {
        return error.NotFound;
    }

    const entry_id = try std.fmt.parseInt(i64, first, 10);

    if (iterator.next()) |second| {
        if (std.mem.eql(u8, second, "like") and iterator.peek() == null) {
            return .{ .entry_like = .{ .entry_id = entry_id } };
        }
        return error.NotFound;
    }

    return .{ .entry = .{ .entry_id = entry_id } };
}

pub fn get(
    self: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    const route = try parseRoute(self, r.path);
    return switch (route) {
        .base => base_path_endpoint.get(self, arena, ctx, r),
        else => error.NotFound,
    };
}

pub fn post(
    self: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    const route = try parseRoute(self, r.path);
    return switch (route) {
        .base => base_path_endpoint.post(self, arena, ctx, r),
        .entry_like => |params| entry_like_endpoint.post(
            self,
            arena,
            ctx,
            r,
            params,
        ),
        else => error.NotFound,
    };
}

pub fn patch(
    self: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    const route = try parseRoute(self, r.path);
    return switch (route) {
        .entry => |params| entry_endpoint.patch(
            self,
            arena,
            ctx,
            r,
            params,
        ),
        else => error.NotFound,
    };
}

pub fn delete(
    self: *FlightLogEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    const route = try parseRoute(self, r.path);
    return switch (route) {
        .entry_like => |params| entry_like_endpoint.delete(
            self,
            arena,
            ctx,
            r,
            params,
        ),
        else => error.NotFound,
    };
}

test "parseRoute split the path and dispatch" {
    const Expected = union(enum) {
        ok: Route,
        err: anyerror,
    };

    const cases = [_]struct {
        name: []const u8,
        path: ?[]const u8,
        expected: Expected,
    }{ .{
        .name = "base path",
        .path = "/api/v1/flight-log",
        .expected = .{ .ok = Route.base },
    }, .{
        .name = "entry path",
        .path = "/api/v1/flight-log/31",
        .expected = .{ .ok = Route{ .entry = .{ .entry_id = 31 } } },
    }, .{
        .name = "like path",
        .path = "/api/v1/flight-log/11/like",
        .expected = .{ .ok = Route{ .entry_like = .{ .entry_id = 11 } } },
    }, .{
        .name = "not this base",
        .path = "/api/v1/flight-log-foo",
        .expected = .{ .err = error.NotFound },
    }, .{
        .name = "short path",
        .path = "/api/v1/flight",
        .expected = .{ .err = error.NotFound },
    }, .{
        .name = "missing path",
        .path = null,
        .expected = .{ .err = error.NotFound },
    }, .{
        .name = "invalid id",
        .path = "/api/v1/flight-log/like",
        .expected = .{ .err = error.InvalidCharacter },
    } };

    var endpoint = FlightLogEndpoint{};

    for (cases) |case| {
        const result = endpoint.parseRoute(case.path);

        switch (case.expected) {
            .ok => |expected| try std.testing.expectEqualDeep(
                expected,
                try result,
            ),
            .err => |expected| if (result) |_| {
                return error.TestExpectedError;
            } else |actual| {
                try std.testing.expectEqual(expected, actual);
            },
        }
    }
}
