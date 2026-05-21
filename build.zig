const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zap_dep = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });
    const zap = zap_dep.module("zap");

    const exe = b.addExecutable(.{
        .name = "Iridoporth_backend",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zap", .module = zap },
            },
        }),
    });

    b.installArtifact(exe);

    // build frontend
    const frontend_dir = b.path("../Iridoporth-frontend");
    const frontend_build = b.addSystemCommand(&.{
        "npm",
        "run",
        "build",
    });
    frontend_build.setCwd(frontend_dir);

    const frontend_step = b.step("forntend", "Build the frontend");
    frontend_step.dependOn(&frontend_build.step);

    const install_frontend = b.addInstallDirectory(.{
        .source_dir = b.path("../Iridoporth-frontend/dist"),
        .install_dir = .prefix,
        .install_subdir = "static",
    });
    install_frontend.step.dependOn(&frontend_build.step);

    b.getInstallStep().dependOn(&install_frontend.step);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setEnvironmentVariable(
        "IRIDOPORTH_PUBLIC_DIR",
        b.getInstallPath(.prefix, "static"),
    );
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
