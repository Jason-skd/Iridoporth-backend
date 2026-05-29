const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../context.zig");

pub const RaspiStatusEndpoint = @This();

const RaspiStatusResponse = struct { ok: bool = true, data: struct {
    available: bool,
    name: ?[]const u8 = null,
    cpu_temperature: ?f32 = null,
    cpu_usage: ?f32 = null,
    memory_usage: ?f32 = null,
} };

path: []const u8 = "/api/v1/raspi/status",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_console,

pub fn get(_: *RaspiStatusEndpoint, arena: Allocator, ctx: *Context, r: zap.Request) !void {
    r.setHeader("Content-Type", "application/json") catch {};

    const response = switch (ctx.raspi) {
        .unavailable => RaspiStatusResponse{
            .data = .{
                .available = false,
            },
        },
        .status => |status| RaspiStatusResponse{
            .data = .{
                .available = true,
                .name = status.name,
                .cpu_temperature = status.cpu_temperature.load(.monotonic),
                .cpu_usage = status.cpu_usage.load(.monotonic),
                .memory_usage = status.memory_usage.load(.monotonic),
            },
        },
    };

    const body = try std.json.Stringify.valueAlloc(arena, response, .{});
    try r.sendBody(body);
}
