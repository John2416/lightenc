const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lightenc_mod = b.addModule("lightenc", .{
        .root_source_file = b.path("src/lightenc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkLightencBackend(lightenc_mod, target);

    const unit_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/lightenc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkLightencBackend(unit_tests_mod, target);

    const unit_tests = b.addTest(.{
        .root_module = unit_tests_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run portable unit tests only");
    test_step.dependOn(&run_unit_tests.step);

    const extended = b.option(bool, "extended", "Run extended backend fixtures for less common encodings") orelse false;
    const strict_backend = b.option(bool, "strict-backend", "Fail if a backend fixture encoding is unsupported instead of skipping") orelse false;

    const test_options = b.addOptions();
    test_options.addOption(bool, "extended", extended);
    test_options.addOption(bool, "strict_backend", strict_backend);

    const backend_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/backend_matrix.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lightenc", .module = lightenc_mod },
            .{ .name = "test_options", .module = test_options.createModule() },
        },
        .link_libc = true,
    });
    linkLightencBackend(backend_tests_mod, target);

    const backend_tests = b.addTest(.{
        .root_module = backend_tests_mod,
    });

    const run_backend_tests = b.addRunArtifact(backend_tests);

    const system_step = b.step("test-system", "Run backend smoke tests against WinAPI/iconv on this platform");
    system_step.dependOn(&run_backend_tests.step);

    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/basic.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "lightenc", .module = lightenc_mod }},
        .link_libc = true,
    });
    linkLightencBackend(example_mod, target);

    const example = b.addExecutable(.{
        .name = "lightenc-basic",
        .root_module = example_mod,
    });

    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Run the basic example");
    example_step.dependOn(&run_example.step);
}

fn linkLightencBackend(module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    module.link_libc = true;

    switch (target.result.os.tag) {
        .macos, .ios, .tvos, .watchos, .visionos => {
            module.linkSystemLibrary("iconv", .{});
        },
        else => {},
    }
}
