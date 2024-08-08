const std = @import("std");

const cells: usize = 30_000;

pub const BrainfuckError = error{
    LeftShiftUnderflow,
    RightShiftOverflow,
    UnmatchedOpenBracket,
    UnmatchedClosingBracket,
};

pub const Command = enum { Right, Left, Inc, Dec, Write, Read, Open, Close };
pub const Program = []const Command;

pub fn parseCodeAlloc(allocator: std.mem.Allocator, code: anytype) !Program {
    var program = std.ArrayList(Command).init(allocator);
    var loop_depth: isize = 0;
    while (code.readByte()) |c| {
        switch (c) {
            '>' => try program.append(.Right),
            '<' => try program.append(.Left),
            '+' => try program.append(.Inc),
            '-' => try program.append(.Dec),
            '.' => try program.append(.Write),
            ',' => try program.append(.Read),
            '[' => {
                loop_depth += 1;
                try program.append(.Open);
            },
            ']' => {
                loop_depth -= 1;
                try program.append(.Close);
            },
            else => {},
        }
    } else |_| {}
    if (loop_depth == 0) {
        return program.toOwnedSlice();
    } else if (loop_depth < 0) {
        return error.UnmatchedClosingBracket;
    } else return error.UnmatchedOpenBracket;
}

pub fn execute(reader: anytype, writer: anytype, program: Program) !void {
    var pc: usize = 0;
    var tape: [cells]u8 = [_]u8{0} ** cells;
    var i: usize = 0;
    var loop_depth: usize = 0;
    while (pc < program.len) : (pc += 1) {
        switch (program[pc]) {
            .Right => {
                i += 1;
                if (i >= cells) return error.RightShiftOverflow;
            },
            .Left => {
                i, const overflow = @subWithOverflow(i, 1);
                if (overflow == 1) return error.LeftShiftUnderflow;
            },
            .Inc => tape[i] +%= 1,
            .Dec => tape[i] -%= 1,
            .Write => try writer.print("{c}", .{tape[i]}),
            .Read => tape[i] = try reader.readByte(),
            .Open, .Close => |c| {
                const open = (c == .Open);
                const cond = if (open) (tape[i] != 0) else (tape[i] == 0);
                if (cond) {
                    loop_depth = if (open) loop_depth + 1 else loop_depth - 1;
                    continue;
                }
                var skip_depth: usize = 1;
                if (open) pc += 1 else pc -= 1;
                while (true) : (pc = if (open) pc + 1 else pc - 1) {
                    switch (program[pc]) {
                        .Open => skip_depth = if (open) skip_depth + 1 else skip_depth - 1,
                        .Close => skip_depth = if (open) skip_depth - 1 else skip_depth + 1,
                        else => {},
                    }
                    if (skip_depth == 0) break;
                }
            },
        }
    }
}

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);
    if (args.len < 2) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Please provide a brainfuck source file!\n", .{});
        return;
    }

    const program = blk: {
        const file = try std.fs.cwd().openFile(args[1], .{});
        defer file.close();
        break :blk try parseCodeAlloc(gpa, file.reader());
    };

    defer gpa.free(program);
    try execute(stdin, stdout, program);
    try stdout.print("\n", .{});
}
