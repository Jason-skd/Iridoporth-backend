test {
    _ = @import("repositories/flight_log.zig");

    _ = @import("services/flight_log.zig");

    _ = @import("services/raspi_status.zig");

    _ = @import("endpoints/flight_log/dispatcher.zig");
}
