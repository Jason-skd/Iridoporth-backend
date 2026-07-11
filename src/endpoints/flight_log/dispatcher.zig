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
// DELETE /api/v1/flight-log/{id}/like => unlike a flight log entry (not implemented yet)

const Route = union(enum) {
    base: void,
    entry: entry_endpoint.Params,
    entry_like: entry_like_endpoint.Params,
};

fn parseRoute(self: *FlightLogEndpoint, r: zap.Request) !Route {
    const base = self.path;
    const path_received = r.path orelse return error.NotFound;

    if (path_received.len == base.len) {
        return .base;
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
        if (std.mem.eql(u8, second, "like")) {
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
    const route = try parseRoute(self, r);
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
    const route = try parseRoute(self, r);
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
    const route = try parseRoute(self, r);
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
    const route = try parseRoute(self, r);
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
