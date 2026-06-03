const std = @import("std");

const zap = @import("zap");

const Context = @import("../context.zig");

const FlightLogService = @import("../services/flight_log.zig");
const FlightLogEntry = FlightLogService.Entry;

const FlightLogEndpoint = @This();

const FlightLogGetResponse = struct { ok: bool, data: struct {
    entries: []const FlightLogEntry,
} };

const FlightLogPostRequest = struct {
    content: []const u8,
    callsign: ?[]const u8,
};

const FlightLogPostResponse = struct { ok: bool, data: struct {
    id: i64,
    created_at: i64,
} };

path: []const u8 = "/api/v1/flight-log",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_console,

pub fn get(_: *FlightLogEndpoint, arena: std.mem.Allocator, ctx: *Context, r: zap.Request) !void {
    r.setHeader("Content-Type", "application/json") catch {};

    const entries = try FlightLogService.listAll(&ctx.db, arena);

    const response = FlightLogGetResponse{
        .ok = true,
        .data = .{
            .entries = entries,
        },
    };

    const body = try std.json.Stringify.valueAlloc(arena, response, .{});
    try r.sendBody(body);
}

pub fn post(_: *FlightLogEndpoint, arena: std.mem.Allocator, ctx: *Context, r: zap.Request) !void {
    r.setHeader("Content-Type", "application/json") catch {};

    const body = r.body orelse return error.InvalidRequest;
    const parsed = try std.json.parseFromSlice(FlightLogPostRequest, arena, body, .{});

    const result = try FlightLogService.insert(&ctx.db, ctx.io, parsed.value.content, parsed.value.callsign);

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
