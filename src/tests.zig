test {
    _ = @import("repositories/flight_log.zig");

    _ = @import("services/flight_log.zig");

    _ = @import("services/raspi_status.zig");

    _ = @import("endpoints/flight_log/dispatcher.zig");

    _ = @import("domain/validation.zig");

    _ = @import("domain/user.zig");

    _ = @import("services/user.zig");
}
