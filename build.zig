const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const file = b.option(
        []const u8,
        "file",
        "Compile a single brainfuck program instead of an interpreter",
    );

    const name = b.option(
        []const u8,
        "name",
        "The name of the executable, defaults to brainzig",
    ) orelse if (file) |fname| blk: {
        var period_idx = fname.len;
        for (fname, 0..) |c, i| period_idx = if (c == '.') i else period_idx;
        break :blk fname[0..period_idx];
    } else "brainzig";

    const options = b.addOptions();
    options.addOption(?[]const u8, "file", file);

    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addOptions("config", options);

    b.installArtifact(exe);

    if (file) |fname| {
        const simplify = b.addExecutable(.{
            .name = "simplify",
            .root_source_file = b.path("src/simplify.zig"),
            .target = b.host,
        });

        simplify.root_module.addOptions("config", options);

        const dedup = b.addExecutable(.{
            .name = "dedup",
            .root_source_file = b.path("src/dedup.zig"),
            .target = b.host,
        });

        dedup.root_module.addOptions("config", options);

        const run_simplify = b.addRunArtifact(simplify);
        const path = run_simplify.addOutputFileArg(fname);

        dedup.root_module.addAnonymousImport(
            "simplified",
            .{ .root_source_file = path },
        );
        const run_dedup = b.addRunArtifact(dedup);
        const dedup_path = run_dedup.addOutputFileArg(fname);

        exe.root_module.addAnonymousImport(
            "simplified",
            .{ .root_source_file = dedup_path },
        );
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
