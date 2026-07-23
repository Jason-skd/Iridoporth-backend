const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const Context = @import("../context.zig");

const response_http = @import("../http/response.zig");

const raspi_status_api = @import("../api/raspi_status.zig");
const RaspiStatusResponse = raspi_status_api.RaspiStatusResponse;

pub const RaspiStatusEndpoint = @This();

path: []const u8 = "/api/v1/raspi/status",
error_strategy: zap.Endpoint.ErrorStrategy = .raise,

pub fn get(
    _: *RaspiStatusEndpoint,
    arena: Allocator,
    ctx: *Context,
    r: zap.Request,
) !void {
    r.setHeader("Content-Type", "application/json") catch {};

    const response = switch (ctx.raspi) {
        .unavailable => RaspiStatusResponse{
            .data = .{
                .available = false,
            },
        },
        .available => |available| blk: {
            const status = available.status;
            break :blk RaspiStatusResponse{
                .data = .{
                    .available = true,
                    .name = available.name,
                    .cpu_temperature = status.cpu_temperature.load(.monotonic),
                    .cpu_usage = status.cpu_usage.load(.monotonic),
                    .memory_usage = status.memory_usage.load(.monotonic),
                },
            };
        },
    };

    try response_http.stringifyAndSendResponse(
        RaspiStatusResponse,
        arena,
        r,
        response,
    );
}
