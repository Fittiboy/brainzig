const std = @import("std");
const config = @import("config");

const cells: usize = 30_000;

const BrainfuckError = error{
    LeftShiftUnderflow,
    RightShiftOverflow,
    UnmatchedOpenBracket,
    UnmatchedClosingBracket,
};

const Command = union(enum) { Right, Left, Inc, Dec, Write, Read, Open: usize, Close: usize };
const Program = []const Command;

fn parseCodeAlloc(allocator: std.mem.Allocator, code: anytype) !Program {
    var program = std.ArrayList(Command).init(allocator);
    errdefer program.deinit();

    var loop_stack = std.ArrayList(usize).init(allocator);
    defer loop_stack.deinit();

    while (code.readByte()) |c| {
        switch (c) {
            '>' => try program.append(.Right),
            '<' => try program.append(.Left),
            '+' => try program.append(.Inc),
            '-' => try program.append(.Dec),
            '.' => try program.append(.Write),
            ',' => try program.append(.Read),
            '[' => {
                try loop_stack.append(program.items.len);
                try program.append(.{ .Open = undefined });
            },
            ']' => {
                const jump_index = loop_stack.popOrNull() orelse
                    return error.UnmatchedClosingBracket;
                program.items[jump_index] = .{ .Open = program.items.len };
                try program.append(.{ .Close = jump_index });
            },
            else => {},
        }
    } else |_| {}

    if (loop_stack.items.len != 0) return error.UnmatchedOpenBracket;
    return program.toOwnedSlice();
}

fn execute(reader: anytype, writer: anytype, program: Program) !void {
    var pc: usize = 0;
    var tape: [cells]u8 = [_]u8{0} ** cells;
    var head: usize = 0;
    while (pc < program.len) : (pc += 1) {
        switch (program[pc]) {
            .Right => {
                head += 1;
                if (head >= cells) return error.RightShiftOverflow;
            },
            .Left => {
                head, const overflow = @subWithOverflow(head, 1);
                if (overflow == 1) return error.LeftShiftUnderflow;
            },
            .Inc => tape[head] +%= 1,
            .Dec => tape[head] -%= 1,
            .Write => try writer.print("{c}", .{tape[head]}),
            .Read => tape[head] = try reader.readByte(),
            .Open => |c| pc = if (tape[head] == 0) c else pc,
            .Close => |c| pc = if (tape[head] != 0) c else pc,
        }
    }
}

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    const program = prg: {
        var filename: ?[]const u8 = null;
        const args = try std.process.argsAlloc(gpa);
        defer std.process.argsFree(gpa, args);
        filename = if (config.file == null) if (args.len < 2) {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Please provide a brainfuck source file!\n", .{});
            return;
        } else args[1] else config.file;

        const file = try std.fs.cwd().openFile(filename.?, .{});
        defer file.close();
        break :prg try parseCodeAlloc(gpa, file.reader());
    };

    defer gpa.free(program);
    try execute(stdin, stdout, program);
    try stdout.print("\n", .{});
}
