const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // library
    const lib = b.addStaticLibrary(.{
        .name = "webzocket",
        .root_source_file = .{ .path = "src/mod.zig" },
        .target = target,
        .optimize = optimize,
    });

    // install
    b.installArtifact(lib);

    // module
    const mod = b.createModule(.{ .source_file = .{ .path = "src/mod.zig" } });
    try b.modules.put(b.dupe("webzocket"), mod);

    // tests
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // "zig build test" command
    const run_unit_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
