const std = @import("std");

pub fn contains(haystack: []const u8, needle: u8) bool {
    for (haystack) |h| if (h == needle) return true;
    return false;
}

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    std.debug.assert(args.len == 2);
    const code = @embedFile("simplified");

    const cwd = std.fs.cwd();

    const new_fname = args[1];
    var file = try cwd.createFile(new_fname, .{});
    defer file.close();

    const writer = file.writer();

    var tokens = std.mem.tokenizeScalar(u8, code, ' ');
    try writer.print("const std = @import(\"std\");\n", .{});
    try writer.print("pub fn main() !void {{\n", .{});
    try writer.print("@setEvalBranchQuota(4_294_967_295);\n", .{});
    try writer.print("var tape = [_]u8{{0}} ** 30_000;\n", .{});
    try writer.print("tape[0] = 0;\n", .{});
    try writer.print("var head: usize = 0;\n", .{});
    try writer.print("head = 0;\n", .{});
    try writer.print("const reader = std.io.getStdIn().reader();\n", .{});
    try writer.print("const writer = std.io.getStdOut().writer();\n", .{});
    try writer.print("if (1 == head) _ = try reader.readByte();\n", .{});
    try writer.print("if (1 == head) try writer.print(\"\", .{{}});\n", .{});
    while (tokens.next()) |t| {
        if (!contains("><+-.,[]", t[0])) break;
        const c = t[0];
        const count: usize = try std.fmt.parseInt(usize, t[1..], 10);
        switch (c) {
            '>' => try writer.print("head += {d};\n", .{count}),
            '<' => try writer.print("head -= {d};\n", .{count}),
            '+' => try writer.print("tape[head] +%= {d};\n", .{count}),
            '-' => try writer.print("tape[head] -%= {d};\n", .{count}),
            '.' => try writer.print("try writer.print(\"{{c}}\", .{{tape[head]}});\n", .{}),
            ',' => try writer.print("tape[head] = reader.readByte() catch 0;\n", .{}),
            '[' => for (0..count) |_| {
                try writer.print("while (tape[head] != 0) {{\n", .{});
            },
            ']' => for (0..count) |_| try writer.print("}}\n", .{}),
            else => unreachable,
        }
    }

    try writer.print("}}", .{});
}
