const std = @import("std");
const config = @import("config");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    std.debug.assert(args.len == 2);
    const code = if (config.file != null) @embedFile("simplified") else return;

    const cwd = std.fs.cwd();

    const new_fname = args[1];
    var file = try cwd.createFile(new_fname, .{});
    defer file.close();

    const writer = file.writer();

    var tokens = std.mem.tokenizeScalar(u8, code, ' ');
    var prev_c: ?u8 = null;
    var prev_count: usize = 0;
    while (tokens.next()) |t| {
        if (t.len == 1) {
            if (prev_c) |pc| try writer.print("{c}{d} ", .{ pc, prev_count });
            prev_c = t[0];
            break;
        }
        const c = t[0];
        const count: usize = try std.fmt.parseInt(usize, t[1..], 10);
        if (prev_c) |pc| {
            if (pc == c) {
                prev_count += count;
                continue;
            } else {
                try writer.print("{c}{d} ", .{ pc, prev_count });
            }
        }
        prev_c = c;
        prev_count = count;
    }

    try writer.print("{c}", .{prev_c.?});
}
