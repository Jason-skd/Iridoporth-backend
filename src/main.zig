const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zap = @import("zap");

const RaspiStatusEndpoint = @import("endpoints/raspi_status.zig");
const FlightLogEndpoint = @import("endpoints/flight_log.zig");

const raspi_service = @import("services/raspi.zig");

const Context = @import("context.zig");

const App = zap.App.Create(Context);

pub fn main(init: std.process.Init) !void {
    var gpa: std.heap.DebugAllocator(.{
        .thread_safe = true,
    }) = .init;
    defer assert(gpa.deinit() == .ok);
    const gpa_allocator = gpa.allocator();

    const config = try loadConfig(init);

    var app_context = try initContext(gpa_allocator, init.io, config.db_path);
    defer app_context.deinit();

    try startDetachedStatusSampler(&app_context, init.io);

    try App.init(gpa_allocator, &app_context, .{
        .default_error_strategy = .log_to_response,
    });
    defer App.deinit();

    var endpoints = Endpoints{};
    try endpoints.register();

    try listenAndRun(config);
}

const Config = struct {
    public_folder: ?[]const u8,
    port: usize,
    db_path: []const u8,
};

fn loadConfig(init: std.process.Init) !Config {
    const public_folder = init.environ_map.get("IRIDOPORTH_PUBLIC_DIR");
    const port_text = init.environ_map.get("IRIDOPORTH_PORT") orelse "3000";
    const port = try std.fmt.parseInt(usize, port_text, 10);
    const db_path = init.environ_map.get("IRIDOPORTH_DB_PATH") orelse "./data/iridoporth.db";

    return .{
        .public_folder = public_folder,
        .port = port,
        .db_path = db_path,
    };
}

fn initContext(allocator: Allocator, io: std.Io, db_path: []const u8) !Context {
    const db_path_sentinel = try allocator.dupeSentinel(u8, db_path, 0);
    defer allocator.free(db_path_sentinel);

    return try Context.init(io, db_path_sentinel);
}

fn startDetachedStatusSampler(ctx: *Context, io: std.Io) !void {
    const sampler_thread = try std.Thread.spawn(.{}, raspi_service.runStatusSampler, .{
        ctx,
        io,
    });
    sampler_thread.detach();
}

const Endpoints = struct {
    raspi_status: RaspiStatusEndpoint = .{},
    flight_log: FlightLogEndpoint = .{},

    fn register(self: *Endpoints) !void {
        try App.register(&self.raspi_status);
        try App.register(&self.flight_log);
    }
};

fn listenAndRun(config: Config) !void {
    try App.listen(.{
        .interface = "0.0.0.0",
        .port = config.port,
        .public_folder = config.public_folder,
    });

    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
