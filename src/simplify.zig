const std = @import("std");
const config = @import("config");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    std.debug.assert(args.len == 2);
    const code = if (config.file) |fname| @embedFile("bf/" ++ fname) else return;

    const cwd = std.fs.cwd();

    const new_fname = args[1];
    var file = try cwd.createFile(new_fname, .{});
    defer file.close();

    const writer = file.writer();

    var loops: usize = 0;
    var closes: usize = 0;
    var depth: usize = 0;

    var last_c: ?u8 = null;
    var count: isize = 0;
    for (code) |c| {
        if (last_c == null) {
            if (c == '[') {
                loops += 1;
                depth = @max(depth, loops - closes);
            } else if (c == ']') return error.UnmatchedClosingBracket;

            switch (c) {
                '>', '<', '+', '-', '.', ',', '[', ']' => {
                    last_c = c;
                    count = if (c == '<' or c == '-') -1 else 1;
                },
                else => {},
            }
            continue;
        }

        const l = last_c.?;
        const prev_count = count;
        switch (c) {
            '>' => count += if (l == '>' or l == '<') 1 else 0,
            '<' => count -= if (l == '>' or l == '<') 1 else 0,
            '+' => count += if (l == '+' or l == '-') 1 else 0,
            '-' => count -= if (l == '+' or l == '-') 1 else 0,
            '.', ',' => count += if (l == c) 1 else 0,
            '[', ']' => {
                count += if (l == c) 1 else 0;
                (if (c == '[') loops else closes) += 1;
                if (closes > loops) return error.UnmatchedClosingBracket;
                depth = @max(depth, loops - closes);
            },
            else => continue,
        }

        if (count == prev_count) {
            try printChar(l, count, writer);
            count = if (c == '<' or c == '-') -1 else 1;
        }

        last_c = c;
    }

    if (last_c) |l| try printChar(l, count, writer);
    try writer.print("{d}", .{depth});

    return if (loops > closes)
        error.UnmatchedOpenBracket
    else if (loops < closes)
        error.UnmatchedClosingBracket
    else {};
}

inline fn printChar(c: u8, count: isize, file: anytype) !void {
    var to_print: u8 = 0;
    var print_count: isize = 0;
    switch (c) {
        '>', '<' => {
            if (count < 0) {
                to_print = '<';
                print_count = -count;
            } else {
                to_print = '>';
                print_count = count;
            }
        },
        '+', '-' => {
            const mod_count = @mod((count + 128), 256) - 128;
            if (mod_count < 0) {
                to_print = '-';
                print_count = -mod_count;
            } else {
                to_print = '+';
                print_count = mod_count;
            }
        },
        else => {
            to_print = c;
            print_count = count;
        },
    }

    if (count != 0) try file.print("{c}{d} ", .{ to_print, print_count });
}
