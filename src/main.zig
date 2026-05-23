const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Raspi = union(enum) { unavailable: void, status: RaspiStatus };

const RaspiStatus = struct {
    name: []const u8,

    cpu_temperature: std.atomic.Value(f32),
    cpu_usage: std.atomic.Value(f32),
    memory_usage: std.atomic.Value(f32),
};

const Context = struct {
    raspi: Raspi,

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

const InvalidContentError = error{
    InvalidCpuStatFormat,
    InvalidMemoryUsedFormat,
};

fn getRaspiName(buffer: *[std.posix.HOST_NAME_MAX]u8) ![]const u8 {
    const host_name = try std.posix.gethostname(buffer);
    return host_name;
}

fn getCpuTemperature(io: std.Io, buffer: []u8) !f32 {
    const text = try std.Io.Dir.cwd().readFile(io, "/sys/class/thermal/thermal_zone0/temp", buffer);

    const raw = std.mem.trim(u8, text, " \t\r\n\x00");
    const milli = try std.fmt.parseInt(i32, raw, 10);
    const float = @as(f32, @floatFromInt(milli)) / 1000.0;

    return float;
}

fn getMemoryUsage(io: std.Io, buffer: []u8) !f32 {
    const text = try std.Io.Dir.cwd().readFile(io, "/proc/meminfo", buffer);

    var total: ?i32 = null;
    var available: ?i32 = null;

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal")) {
            var parts = std.mem.tokenizeAny(u8, line, " \t:");

            _ = parts.next(); // MemTotal
            const value_next = parts.next() orelse return InvalidContentError.InvalidMemoryUsedFormat;

            total = try std.fmt.parseInt(i32, value_next, 10);
        } else if (std.mem.startsWith(u8, line, "MemAvailable")) {
            var parts = std.mem.tokenizeAny(u8, line, " \t:");

            _ = parts.next(); // MemAvailable
            const value_next = parts.next() orelse return InvalidContentError.InvalidMemoryUsedFormat;

            available = try std.fmt.parseInt(i32, value_next, 10);
        }
    }

    const total_value = total orelse return InvalidContentError.InvalidMemoryUsedFormat;
    const available_value = available orelse return InvalidContentError.InvalidMemoryUsedFormat;

    return @as(f32, @floatFromInt(total_value - available_value)) / @as(f32, @floatFromInt(total_value)) * 100.0;
}

const CpuTimes = struct {
    idle: u64,
    total: u64,
};

fn readCpuTimes(io: std.Io, buffer: []u8) !CpuTimes {
    const text = try std.Io.Dir.cwd().readFile(io, "/proc/stat", buffer);

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    const first_line = lines.next() orelse return InvalidContentError.InvalidCpuStatFormat;
    var parts = std.mem.tokenizeAny(u8, first_line, " \t");

    var idle: u64 = 0;
    var total: u64 = 0;

    var index: usize = 0;
    while (parts.next()) |part| : (index += 1) {
        if (index == 0) {
            continue; // "cpu"
        }
        if (index >= 9) {
            break; // guest
        }
        const value = try std.fmt.parseInt(u64, part, 10);
        total += value;
        if (index == 4 or index == 5) {
            idle += value;
        }
    }
    return .{
        .idle = idle,
        .total = total,
    };
}

fn calcCpuUsage(prev: CpuTimes, now: CpuTimes) f32 {
    const total_delta = now.total - prev.total;
    if (total_delta == 0) {
        return 0.0;
    }

    const idle_delta = if (now.idle >= prev.idle) now.idle - prev.idle else 0;

    return @as(f32, @floatFromInt(total_delta - idle_delta)) * 100.0 / @as(f32, @floatFromInt(total_delta));
}

fn statusSamplingWorker(ctx: *Context, io: std.Io) !void {
    var temp_buffer: [1024]u8 = undefined;
    var prev_cpu_times = try readCpuTimes(io, temp_buffer[0..]);

    while (true) {
        io.sleep(.fromSeconds(1), .awake) catch {};

        const cpu_temperature = try getCpuTemperature(io, temp_buffer[0..]);

        const current_cpu_times = try readCpuTimes(io, temp_buffer[0..]);
        const cpu_usage = calcCpuUsage(prev_cpu_times, current_cpu_times);

        const memory_usage = try getMemoryUsage(io, temp_buffer[0..]);

        switch (ctx.raspi) {
            .unavailable => return,
            .status => |*status| {
                status.cpu_temperature.store(cpu_temperature, .monotonic);
                status.cpu_usage.store(cpu_usage, .monotonic);
                status.memory_usage.store(memory_usage, .monotonic);
            },
        }

        prev_cpu_times = current_cpu_times;
    }
}

fn statusSampler(ctx: *Context, io: std.Io) void {
    statusSamplingWorker(ctx, io) catch |err| {
        std.debug.print("status sampling: {}\n", .{err});
        ctx.raspi = Raspi.unavailable;
    };
}
const device_status_endpoint = "/api/v1/device/status";

const DeviceStatusEndpoint = struct {
    path: []const u8 = device_status_endpoint,
    error_strategy: zap.Endpoint.ErrorStrategy = .log_to_console,

    pub fn get(_: *DeviceStatusEndpoint, arena: Allocator, ctx: *Context, r: zap.Request) !void {
        const DeviceStatusResponse = struct { ok: bool = true, data: struct {
            available: bool,
            name: ?[]const u8 = null,
            cpu_temperature: ?f32 = null,
            cpu_usage: ?f32 = null,
            memory_usage: ?f32 = null,
        } };

        r.setHeader("Content-Type", "application/json") catch {};

        const response = switch (ctx.raspi) {
            .unavailable => DeviceStatusResponse{
                .data = .{
                    .available = false,
                },
            },
            .status => |status| DeviceStatusResponse{
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
};

pub fn main(init: std.process.Init) !void {
    var gpa: std.heap.DebugAllocator(.{
        .thread_safe = true,
    }) = .init;
    defer _ = assert(gpa.deinit() == .ok);

    const gpa_allocator = gpa.allocator();

    const public_folder = init.environ_map.get("IRIDOPORTH_PUBLIC_DIR") orelse "zig-out/static";

    var raspi: Raspi = .unavailable;
    init_raspi: {
        var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const raspi_name = getRaspiName(&hostname_buf) catch |err| {
            std.debug.print("get raspi name: {}\n", .{err});
            break :init_raspi;
        };

        var temp_buf: [1024]u8 = undefined;
        const cpu_temperature = getCpuTemperature(init.io, temp_buf[0..]) catch |err| {
            std.debug.print("get cpu temperature: {}\n", .{err});
            break :init_raspi;
        };

        _ = readCpuTimes(init.io, temp_buf[0..]) catch |err| {
            std.debug.print("read cpu times: {}\n", .{err});
            break :init_raspi;
        };

        const memory_usage = getMemoryUsage(init.io, temp_buf[0..]) catch |err| {
            std.debug.print("get memory usage: {}\n", .{err});
            break :init_raspi;
        };

        raspi = .{ .status = .{
            .name = raspi_name,
            .cpu_temperature = std.atomic.Value(f32).init(cpu_temperature),
            .cpu_usage = std.atomic.Value(f32).init(0.0),
            .memory_usage = std.atomic.Value(f32).init(memory_usage),
        } };
    }

    var app_context = Context{
        .raspi = raspi,
    };

    const sampler_thread = try std.Thread.spawn(.{}, statusSampler, .{
        &app_context,
        init.io,
    });
    sampler_thread.detach();

    const App = zap.App.Create(Context);
    try App.init(gpa_allocator, &app_context, .{
        .default_error_strategy = .log_to_response,
    });
    defer App.deinit();

    var deviceStatusEndpoint = DeviceStatusEndpoint{};
    try App.register(&deviceStatusEndpoint);

    try App.listen(.{
        .interface = "0.0.0.0",
        .port = 3000,
        .public_folder = public_folder,
    });

    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
