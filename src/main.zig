const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Context = struct {
    raspi: union(enum) {
        not_available: void,
        name: []const u8,
    },

    pub fn unhandledRequest(_: *Context, _: Allocator, r: zap.Request) anyerror!void {
        r.setStatus(.not_found);
        try r.sendBody("Not Found");
    }

    pub fn unhandledError(_: *Context, r: zap.Request, err: anyerror) void {
        std.debug.print("Unhandled error: {}\n", .{err});
        r.setStatus(.internal_server_error);
        r.sendBody("Internal Server Error") catch {};
    }
};

const RaspiStatus = struct {
    cpu_temperature: f32,
    cpu_usage: f32,
    memory_usage: f32,
};

fn getRaspiStatus() !RaspiStatus {
    // TODO: Implement actual logic to get Raspi status.
    return .{
        .cpu_temperature = 55.0,
        .cpu_usage = 30.0,
        .memory_usage = 40.0,
    };
}

const DeviceStatusEndpoint = struct {
    path: []const u8 = "/api/v1/device/status",
    error_strategy: zap.Endpoint.ErrorStrategy = .raise,

    pub fn get(_: *DeviceStatusEndpoint, arena: Allocator, ctx: *Context, r: zap.Request) !void {
        const DeviceStatusResponse = struct { ok: bool = true, data: struct {
            available: bool,
            name: ?[]const u8,
            cpu_temperature: ?f32 = null,
            cpu_usage: ?f32 = null,
            memory_usage: ?f32 = null,
        } };

        try r.setHeader("Content-Type", "application/json");

        const available: bool, const name: ?[]const u8 = switch (ctx.raspi) {
            .not_available => .{ false, null },
            .name => |name| .{ true, name },
        };

        const response: DeviceStatusResponse = if (available) response: {
            const status = try getRaspiStatus();
            break :response DeviceStatusResponse{
                .ok = true,
                .data = .{
                    .available = true,
                    .name = name,
                    .cpu_temperature = status.cpu_temperature,
                    .cpu_usage = status.cpu_usage,
                    .memory_usage = status.memory_usage,
                },
            };
        } else DeviceStatusResponse{
            .ok = false,
            .data = .{
                .available = false,
                .name = null,
            },
        };

        const body = try std.json.Stringify.valueAlloc(arena, response, .{});
        try r.sendBody(body);
    }
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{
        .thread_safe = true,
    }) = .init;
    defer _ = assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    // TODO: Detect real status of the running server.
    var app_context = Context{
        .raspi = .{ .name = "Raspberry Pi" },
    };

    const App = zap.App.Create(Context);
    try App.init(allocator, &app_context, .{
        .default_error_strategy = .log_to_response,
    });
    defer App.deinit();

    var deviceStatusEndpoint = DeviceStatusEndpoint{};
    try App.register(&deviceStatusEndpoint);

    try App.listen(.{
        .interface = "0.0.0.0",
        .port = 3000,
        .public_folder = "../Iridoporth-frontend/dist",
    });

    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
