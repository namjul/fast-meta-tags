const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "fast-meta-tags",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mvzr = b.dependency("mvzr", .{});
    exe.root_module.addImport("mvzr", mvzr.module("mvzr"));

    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mvzrx = b.dependency("mvzr", .{});
    tests.root_module.addImport("mvzr", mvzrx.module("mvzr"));

    const test_cmd = b.addRunArtifact(tests);
    test_cmd.step.dependOn(b.getInstallStep());
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&test_cmd.step);

    b.installArtifact(exe);
}
