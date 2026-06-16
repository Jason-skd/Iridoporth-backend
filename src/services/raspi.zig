const std = @import("std");

const Context = @import("../context.zig");

pub const Raspi = union(enum) { unavailable: void, available: struct { name: []u8, status: RaspiStatus } };
const RaspiStatus = struct {
    cpu_temperature: std.atomic.Value(f32),
    cpu_usage: std.atomic.Value(f32),
    memory_usage: std.atomic.Value(f32),
};

pub fn init(io: std.Io) Raspi {
    var host_name_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const raspi_name = std.posix.gethostname(&host_name_buf) catch |err| {
        std.debug.print("get raspi name: {}\n", .{err});
        return .unavailable;
    };
    const raspi_status = checkStatus(io) catch |err| {
        std.debug.print("check raspi status: {}\n", .{err});
        return .unavailable;
    };
    return .{ .available = .{
        .name = raspi_name,
        .status = raspi_status,
    } };
}

pub fn runStatusSampler(ctx: *Context, io: std.Io) void {
    sampleStatusLoop(ctx, io) catch |err| {
        std.debug.print("status sampling: {}\n", .{err});
        ctx.raspi = Raspi.unavailable;
    };
}

fn checkStatus(io: std.Io) !RaspiStatus {
    var temp_buf: [1024]u8 = undefined;
    const cpu_temperature = try getCpuTemperature(io, temp_buf[0..]);

    _ = try readCpuTimes(io, temp_buf[0..]);

    const memory_usage = try getMemoryUsage(io, temp_buf[0..]);

    return .{
        .cpu_temperature = std.atomic.Value(f32).init(cpu_temperature),
        .cpu_usage = std.atomic.Value(f32).init(0.0),
        .memory_usage = std.atomic.Value(f32).init(memory_usage),
    };
}

fn getCpuTemperature(io: std.Io, buffer: []u8) !f32 {
    const text = try std.Io.Dir.cwd().readFile(io, "/sys/class/thermal/thermal_zone0/temp", buffer);

    const raw = std.mem.trim(u8, text, " \t\r\n\x00");
    const milli = try std.fmt.parseInt(u64, raw, 10);
    const float = @as(f32, @floatFromInt(milli)) / 1000.0;

    return float;
}

fn getMemoryUsage(io: std.Io, buffer: []u8) !f32 {
    const text = try std.Io.Dir.cwd().readFile(io, "/proc/meminfo", buffer);

    var total: ?u64 = null;
    var available: ?u64 = null;

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (total == null) {
            total = try getValFromMeminfo(line, "MemTotal:");
        }
        if (available == null) {
            available = try getValFromMeminfo(line, "MemAvailable:");
        }
        if (total != null and available != null) {
            break;
        }
    }

    if (total == null or available == null) {
        return error.MissingVal;
    }

    return @as(f32, @floatFromInt(total.? - available.?)) / @as(f32, @floatFromInt(total.?)) * 100.0;
}

fn getValFromMeminfo(line: []const u8, key: []const u8) !?u64 {
    if (!std.mem.startsWith(u8, line, key)) {
        return null;
    }

    var parts = std.mem.tokenizeAny(u8, line, " \t:");

    _ = parts.next();
    const value = parts.next() orelse return error.NoValForKey;

    return try std.fmt.parseInt(u64, value, 10);
}

const CpuTimes = struct {
    idle: u64,
    total: u64,
};

fn readCpuTimes(io: std.Io, buffer: []u8) !CpuTimes {
    const text = try std.Io.Dir.cwd().readFile(io, "/proc/stat", buffer);

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    const first_line = lines.next() orelse return error.BlankFile;
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
    // TODO: whether to use Io.Clock?
    const total_delta = now.total - prev.total;
    if (total_delta == 0) {
        return 0.0;
    }

    const idle_delta = if (now.idle >= prev.idle) now.idle - prev.idle else 0;

    return @as(f32, @floatFromInt(total_delta - idle_delta)) * 100.0 / @as(f32, @floatFromInt(total_delta));
}

fn sampleStatusLoop(ctx: *Context, io: std.Io) !void {
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
            .available => |*available| {
                const status = &available.status;
                status.cpu_temperature.store(cpu_temperature, .monotonic);
                status.cpu_usage.store(cpu_usage, .monotonic);
                status.memory_usage.store(memory_usage, .monotonic);
            },
        }

        prev_cpu_times = current_cpu_times;
    }
}
